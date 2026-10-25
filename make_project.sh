#!/usr/bin/env bash
# =============================================================================
# make_project.sh — generator szkieletu nowego projektu "po Arku".
#
# Tworzy projekt z bootstrapem, README, .gitignore, .editorconfig, .env.example,
# opcjonalną licencją i — jeśli chcesz — Dockerfile + compose.
#
# Użycie:
#   ./make_project.sh <nazwa> [python|node|go|rust|php|ruby|bash|auto]
#   ./make_project.sh <nazwa> --with-docker
#   ./make_project.sh <nazwa> python --no-git
# =============================================================================
set -Eeuo pipefail

VERSION="2.0.0"
SOURCE=${BASH_SOURCE[0]}
if command -v readlink >/dev/null 2>&1; then
  SOURCE=$(readlink -f "$SOURCE" 2>/dev/null || printf '%s' "$SOURCE")
fi
ROOT="$(cd "$(dirname "$SOURCE")" && pwd)"
NAME=""
TYPE="python"
LICENSE_TYPE="mit"
DO_GIT=1
WITH_DOCKER=0
POSITIONAL=0
INTO="$PWD"
SLUG=""
YEAR=""
TARGET=""
CREATED=0

err() {
  printf '\033[0;31m[x]\033[0m %s\n' "$1" >&2
}

warn() {
  printf '\033[1;33m[!]\033[0m %s\n' "$1" >&2
  return 0
}

log() {
  printf '\033[0;32m[+]\033[0m %s\n' "$1"
}

die() {
  err "$1"
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

cleanup_partial() {
  local code=$?

  if [ "$code" -ne 0 ] && [ "$CREATED" = 1 ] && [ -n "$TARGET" ] && [ -d "$TARGET" ]; then
    cd / 2>/dev/null || true
    rm -rf -- "$TARGET"
    warn "usunięto niekompletny projekt: $TARGET"
  fi
}

trap cleanup_partial EXIT

usage() {
  cat <<EOF
make_project.sh $VERSION — generator projektu

Użycie:
  ./make_project.sh <nazwa> [typ] [opcje]

Typy:
  python (domyślnie), node, go, rust, php, ruby, bash, auto

Opcje:
  --lang <typ>       to samo co argument [typ]
  --into <katalog>   gdzie utworzyć projekt (domyślnie: bieżący katalog)
  --license mit|none licencja (domyślnie: mit)
  --with-docker      dodaj Dockerfile, compose.yaml i .dockerignore
  --no-git           nie inicjuj repozytorium git
  --git              wymuś git init (domyślnie)
  -h, --help         ta pomoc
  --version          pokaż wersję

Przykłady:
  ./make_project.sh moja_nauka python
  ./make_project.sh front --lang node --with-docker
  ./make_project.sh skrypt bash --no-git
EOF
}

add_positional() {
  case "$POSITIONAL" in
    0)
      NAME=$1
      ;;
    1)
      TYPE=$1
      ;;
    *)
      die "za dużo argumentów pozycyjnych (zobacz --help)"
      ;;
  esac
  POSITIONAL=$((POSITIONAL + 1))
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --version)
        printf '%s\n' "$VERSION"
        exit 0
        ;;
      --lang)
        [ "$#" -ge 2 ] || die "--lang wymaga wartości"
        TYPE=$2
        shift
        ;;
      --lang=*)
        TYPE=${1#*=}
        ;;
      --into)
        [ "$#" -ge 2 ] || die "--into wymaga katalogu"
        INTO=$2
        shift
        ;;
      --into=*)
        INTO=${1#*=}
        ;;
      --license)
        [ "$#" -ge 2 ] || die "--license wymaga wartości (mit|none)"
        LICENSE_TYPE=$2
        shift
        ;;
      --license=*)
        LICENSE_TYPE=${1#*=}
        ;;
      --with-docker)
        WITH_DOCKER=1
        ;;
      --no-git)
        DO_GIT=0
        ;;
      --git)
        DO_GIT=1
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          add_positional "$1"
          shift
        done
        break
        ;;
      -*)
        die "nieznany argument: $1 (zobacz --help)"
        ;;
      *)
        add_positional "$1"
        ;;
    esac
    shift
  done

  [ -n "$NAME" ] || die "podaj nazwę projektu (zobacz --help)"

  case "$TYPE" in
    python|node|go|rust|php|ruby|bash|auto)
      ;;
    *)
      die "nieznany typ: $TYPE (python|node|go|rust|php|ruby|bash|auto)"
      ;;
  esac

  case "$LICENSE_TYPE" in
    mit|none)
      ;;
    *)
      die "nieznana licencja: $LICENSE_TYPE (mit|none)"
      ;;
  esac

  if [ "$TYPE" = "auto" ]; then
    if have python3; then
      TYPE=python
    elif have node; then
      TYPE=node
    elif have go; then
      TYPE=go
    else
      TYPE=bash
    fi
  fi
}

validate_name() {
  case "$NAME" in
    ""|.|..|-*|.*|_*|*[!A-Za-z0-9._-]*)
      die "niedozwolona nazwa: '$NAME' (dozwolone: litery, cyfry, ., _, -; bez spacji, ukośników i wiodącego . lub _)"
      ;;
  esac

  if [ "${#NAME}" -gt 64 ]; then
    die "nazwa jest za długa (maks. 64 znaki)"
  fi
}

render_to() {
  local dest=$1
  local line

  : > "$dest"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line//__NAME__/$NAME}
    line=${line//__SLUG__/$SLUG}
    line=${line//__TYPE__/$TYPE}
    line=${line//__YEAR__/$YEAR}
    line=${line//__RUN__/$RUN_CMD}
    printf '%s\n' "$line" >> "$dest"
  done
}

write_common_files() {
  render_to README.md <<'EOF'
# __NAME__

Krótki opis projektu.

## Stack

- `__TYPE__`
- bootstrap: `./bootstrap.sh`

## Start

```bash
./bootstrap.sh
__RUN__
```

## Struktura

- `main.*` — punkt wejścia
- `bootstrap.sh` — wykrywa środowisko i instaluje zależności
- `.env.example` — wzór konfiguracji (skopiuj do `.env`)
- `.arek-bootstrap/` — lokalny stan bootstrapu (nie commituj)

## Uwagi

Projekt wygenerowany przez `make_project.sh` z arek-bootstrap.
Uzupełnij README, kod, `.env` oraz — jeśli istnieje — autora w `LICENSE`.
EOF

  cat > .editorconfig <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 4
trim_trailing_whitespace = true

[*.{js,json,yml,yaml,md}]
indent_size = 2

[Makefile]
indent_style = tab
EOF

  cat > .env.example <<'EOF'
# Skopiuj ten plik do .env i uzupełnij wartości.
# .env jest ignorowany przez git.

# APP_ENV=development
# APP_PORT=8080
EOF

  cat > .gitignore <<'EOF'
# środowiska i zależności
.venv/
venv/
node_modules/
vendor/
target/
__pycache__/
*.py[cod]

# konfiguracja i logi
.env
.env.*
!.env.example
*.log

# build i raporty
dist/
build/
coverage/
reports/

# stan bootstrapu
.arek-bootstrap/

# system
.DS_Store
EOF

  case "$TYPE" in
    python)
      cat >> .gitignore <<'EOF'
.pytest_cache/
.mypy_cache/
.ruff_cache/
*.egg-info/
EOF
      ;;
    node)
      cat >> .gitignore <<'EOF'
.pnpm-store/
npm-debug.log*
yarn-error.log*
EOF
      ;;
    go)
      cat >> .gitignore <<'EOF'
/bin/
*.test
coverage.out
EOF
      ;;
    php)
      cat >> .gitignore <<'EOF'
composer.phar
EOF
      ;;
    ruby)
      cat >> .gitignore <<'EOF'
.bundle/
EOF
      ;;
  esac
}

write_python() {
  RUN_CMD=".venv/bin/python main.py"

  cat > pyproject.toml <<EOF
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "$NAME"
version = "0.1.0"
description = "$NAME"
readme = "README.md"
requires-python = ">=3.10"
dependencies = []

[tool.setuptools]
py-modules = ["main"]
EOF

  cat > main.py <<EOF
def main() -> None:
    print("Działa! ($NAME - python)")


if __name__ == "__main__":
    main()
EOF
}

write_node() {
  RUN_CMD="npm start"

  cat > package.json <<EOF
{
  "name": "$SLUG",
  "version": "0.1.0",
  "private": true,
  "description": "$NAME",
  "main": "main.js",
  "scripts": {
    "start": "node main.js",
    "test": "node --test"
  },
  "engines": {
    "node": ">=18"
  }
}
EOF

  cat > main.js <<EOF
console.log("Działa! ($NAME - node)");
EOF
}

write_go() {
  RUN_CMD="go run ."

  cat > go.mod <<EOF
module $SLUG

go 1.21
EOF

  cat > main.go <<EOF
package main

import "fmt"

func main() {
	fmt.Println("Działa! ($NAME - go)")
}
EOF
}

write_rust() {
  RUN_CMD="cargo run"
  local rust_slug=${SLUG//./-}

  cat > Cargo.toml <<EOF
[package]
name = "$rust_slug"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

  mkdir -p src
  cat > src/main.rs <<EOF
fn main() {
    println!("Działa! ($NAME - rust)");
}
EOF
}

write_php() {
  RUN_CMD="php main.php"

  cat > composer.json <<EOF
{
  "name": "app/$SLUG",
  "description": "$NAME",
  "type": "project",
  "require": {}
}
EOF

  cat > main.php <<EOF
<?php

echo "Działa! ($NAME - php)\n";
EOF
}

write_ruby() {
  RUN_CMD="ruby main.rb"

  cat > Gemfile <<'EOF'
source "https://rubygems.org"
EOF

  cat > main.rb <<EOF
puts "Działa! ($NAME - ruby)"
EOF
}

write_bash() {
  RUN_CMD="./main.sh"

  cat > main.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

echo "Działa! ($NAME - bash)"
EOF
  chmod +x main.sh
}

write_docker() {
  case "$TYPE" in
    python)
      cat > Dockerfile <<'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml README.md ./
COPY main.py ./
RUN pip install --no-cache-dir .

CMD ["python", "main.py"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
.venv
__pycache__
*.py[cod]
EOF
      ;;
    node)
      cat > Dockerfile <<'EOF'
FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY . .

CMD ["npm", "start"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
node_modules
npm-debug.log*
EOF
      ;;
    go)
      cat > Dockerfile <<'EOF'
FROM golang:1.23-alpine AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app .

FROM alpine:3.20
RUN adduser -D app
USER app
COPY --from=build /out/app /app
CMD ["/app"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
EOF
      ;;
    rust)
      local rust_slug=${SLUG//./-}
      cat > Dockerfile <<EOF
FROM rust:1.82-slim AS build

WORKDIR /src
COPY Cargo.toml ./
COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim
COPY --from=build /src/target/release/$rust_slug /app
CMD ["/app"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
target
EOF
      ;;
    php)
      cat > Dockerfile <<'EOF'
FROM composer:2 AS vendor

WORKDIR /app
COPY composer.json ./
RUN composer install --no-dev --no-interaction --prefer-dist --no-scripts

FROM php:8.3-cli

WORKDIR /app
COPY --from=vendor /app/vendor ./vendor
COPY . .

CMD ["php", "main.php"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
EOF
      ;;
    ruby)
      cat > Dockerfile <<'EOF'
FROM ruby:3.3-slim

WORKDIR /app
COPY Gemfile ./
RUN bundle install
COPY . .

CMD ["ruby", "main.rb"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
.bundle
vendor
EOF
      ;;
    bash)
      cat > Dockerfile <<'EOF'
FROM bash:5

WORKDIR /app
COPY . .

CMD ["bash", "main.sh"]
EOF
      cat > .dockerignore <<'EOF'
.git
.env
.arek-bootstrap
EOF
      ;;
  esac

  cat > compose.yaml <<'EOF'
services:
  app:
    build: .
    restart: unless-stopped
EOF
}

write_license() {
  render_to LICENSE <<'EOF'
MIT License

Copyright (c) __YEAR__ <autor>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
}

init_git() {
  [ "$DO_GIT" = 1 ] || return 0

  if ! have git; then
    warn "git: brak w PATH — pomijam git init"
    return 0
  fi

  if git -C "$TARGET" init -q -b main 2>/dev/null; then
    log "git: repozytorium zainicjowane (main)"
  else
    git -C "$TARGET" init -q || die "git init nie powiódł się"
    git -C "$TARGET" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
    log "git: repozytorium zainicjowane"
  fi
}

main() {
  parse_args "$@"
  validate_name

  mkdir -p "$INTO" || die "nie mogę utworzyć katalogu docelowego: $INTO"
  INTO="$(cd "$INTO" && pwd)" || die "nie mogę wejść do katalogu docelowego: $INTO"
  TARGET="$INTO/$NAME"

  if [ -e "$TARGET" ]; then
    die "'$TARGET' już istnieje"
  fi

  SLUG=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')
  YEAR=$(date +%Y)
  RUN_CMD=""

  mkdir -p "$TARGET"
  CREATED=1
  cd "$TARGET" || die "nie mogę wejść do $TARGET"

  printf '\033[0;36m[+]\033[0m Tworzę projekt %s (typ: %s)\n' "$NAME" "$TYPE"

  case "$TYPE" in
    python) write_python ;;
    node) write_node ;;
    go) write_go ;;
    rust) write_rust ;;
    php) write_php ;;
    ruby) write_ruby ;;
    bash) write_bash ;;
  esac

  write_common_files

  [ -f "$ROOT/bootstrap.sh" ] || die "brak $ROOT/bootstrap.sh — nie mogę dodać bootstrapu"
  cp -- "$ROOT/bootstrap.sh" ./bootstrap.sh
  chmod +x ./bootstrap.sh

  if [ "$LICENSE_TYPE" = "mit" ]; then
    write_license
  fi

  if [ "$WITH_DOCKER" = 1 ]; then
    write_docker
    log "docker: Dockerfile + compose.yaml"
  fi

  init_git

  printf '\n'
  log "Projekt '$NAME' gotowy: $TARGET"
  printf '    cd %s\n' "$NAME"
  printf '    ./bootstrap.sh\n'
  printf '    %s\n' "$RUN_CMD"
  printf '    (uzupełnij README.md, .env i kod)\n'
}

main "$@"
