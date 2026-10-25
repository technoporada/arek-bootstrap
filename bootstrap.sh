#!/usr/bin/env bash
# =============================================================================
# arek-bootstrap — self-setup projektu
#
# Wykrywa stack (Python / Node / Go / Rust / PHP / Ruby / bash / Docker),
# wybiera właściwy menedżer pakietów, instaluje zależności i zapisuje
# "stempel" w .arek-bootstrap/state. Dzięki temu kolejne uruchomienia są
# szybkie, a zmiana manifestu automatycznie wymusza ponowną instalację.
#
# Użycie: ./bootstrap.sh [opcje]
# Pomoc:  ./bootstrap.sh --help
# =============================================================================
set -Eeuo pipefail

VERSION="2.1.0"
ROOT="${AREK_BOOTSTRAP_ROOT:-}"
STATE_DIR=""
SCAN_DEPTH=3

CHECK_ONLY=0
DRY_RUN=0
FORCE=0
ALL=0
LIST=0
DO_AUDIT=1
REFRESH_THREATS=0
NO_SCRIPTS=${AREK_NO_SCRIPTS:-0}
DOCKER_UP=0
QUIET=0
VERBOSE=0
USE_COLOR=1
LANG_FORCE=""

GREEN=""
YELLOW=""
RED=""
CYAN=""
NC=""

PROJECTS=""
SELECTED=""
DONE=0
SKIPPED=0

# ---------------------------------------------------------------------------
# Logowanie
# ---------------------------------------------------------------------------
log() {
  if [ "$QUIET" = 0 ]; then
    printf '%s[+]%s %s\n' "$GREEN" "$NC" "$1"
  fi
  return 0
}

ok() {
  if [ "$QUIET" = 0 ]; then
    printf '  %s[ok]%s %s\n' "$GREEN" "$NC" "$1"
  fi
  return 0
}

warn() {
  printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$1" >&2
  return 0
}

err() {
  printf '%s[x]%s %s\n' "$RED" "$NC" "$1" >&2
}

debug() {
  if [ "$VERBOSE" = 1 ]; then
    printf '  %s[dbg]%s %s\n' "$CYAN" "$NC" "$1"
  fi
  return 0
}

section() {
  if [ "$QUIET" = 0 ]; then
    printf '\n%s== %s ==%s\n' "$CYAN" "$1" "$NC"
  fi
  return 0
}

die() {
  err "$1"
  exit 1
}

on_error() {
  local code=$1
  local line=$2
  local cmd=$3
  err "nieoczekiwany błąd (kod $code) w linii $line: $cmd"
  exit "$code"
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

have() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<EOF
arek-bootstrap $VERSION — jeden skrypt stawia projekt.

Użycie:
  ./bootstrap.sh [opcje]

Opcje:
  --check, --check-only  tylko raport: wykryte projekty, narzędzia, stan stempli
  --list                 wypisz wykryte projekty i wyjdź
  --lang <stack>         wymuś stack dla katalogu głównego
  --root <katalog>       katalog projektu (domyślnie: bieżący katalog)
  --all                  przetwórz także projekty w podkatalogach (monorepo)
  --depth <n>            maksymalna głębokość skanowania (domyślnie: $SCAN_DEPTH)
  --dry-run, -n          pokaż polecenia, ale nic nie zmieniaj
  --force, -f            ignoruj stemple i wykonaj instalację od nowa
  --no-audit             pomiń audyt podatności i weryfikację podpisów
  --no-scripts           nie uruchamiaj skryptów instalacyjnych pakietów
                         (npm/pnpm/yarn/bun --ignore-scripts, composer --no-scripts)
  --refresh-threats      odśwież lokalną bazę zagrożeń (osv-scanner) i przeskanuj projekt
  --docker-up            po walidacji uruchom docker compose up -d --build
  --quiet, -q            tylko ostrzeżenia i błędy
  --verbose, -v          dodatkowe informacje diagnostyczne
  --no-color             wyłącz kolory
  --version              pokaż wersję
  -h, --help             ta pomoc

Stosy:
  python  node  go  rust  php  ruby  bash  docker

Wykrywanie:
  Katalog główny ma pierwszeństwo. Jeśli ma manifest kodu (np. package.json),
  podkatalogi są pomijane — użyj --all, aby przetworzyć również je.
  Gdy katalog główny nie ma manifestu kodu, bootstrap schodzi do podkatalogów.

Stemple:
  .arek-bootstrap/state/*.stamp — hash manifestów + wersja bootstrapu.
  Zmiana requirements.txt, package.json, lockfile itp. wymusza reinstalację.

Bezpieczeństwo:
  Skrypt nie pobiera i nie uruchamia kodu przez "curl | bash", nie nadpisuje
  .env i preferuje instalacje odtwarzalne z lockfile (--frozen/--locked/ci).
EOF
}

# ---------------------------------------------------------------------------
# Argumenty i kolory
# ---------------------------------------------------------------------------
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
      --check|--check-only)
        CHECK_ONLY=1
        ;;
      --dry-run|-n)
        DRY_RUN=1
        ;;
      --force|-f)
        FORCE=1
        ;;
      --all)
        ALL=1
        ;;
      --list)
        LIST=1
        ;;
      --no-audit)
        DO_AUDIT=0
        ;;
      --no-scripts)
        NO_SCRIPTS=1
        ;;
      --refresh-threats)
        REFRESH_THREATS=1
        ;;
      --docker-up)
        DOCKER_UP=1
        ;;
      --quiet|-q)
        QUIET=1
        ;;
      --verbose|-v)
        VERBOSE=1
        ;;
      --no-color)
        USE_COLOR=0
        ;;
      --lang)
        [ "$#" -ge 2 ] || die "--lang wymaga wartości"
        LANG_FORCE=$2
        shift
        ;;
      --lang=*)
        LANG_FORCE=${1#*=}
        ;;
      --root)
        [ "$#" -ge 2 ] || die "--root wymaga katalogu"
        ROOT=$2
        shift
        ;;
      --root=*)
        ROOT=${1#*=}
        ;;
      --depth)
        [ "$#" -ge 2 ] || die "--depth wymaga liczby"
        SCAN_DEPTH=$2
        shift
        ;;
      --depth=*)
        SCAN_DEPTH=${1#*=}
        ;;
      --)
        shift
        [ "$#" -eq 0 ] || die "nieoczekiwany argument: $1"
        break
        ;;
      -*)
        die "nieznany argument: $1 (zobacz --help)"
        ;;
      *)
        die "nieoczekiwany argument: $1 (zobacz --help)"
        ;;
    esac
    shift
  done

  case "$SCAN_DEPTH" in
    ''|*[!0-9]*)
      die "--depth musi być liczbą"
      ;;
  esac

  if [ "$SCAN_DEPTH" -lt 1 ]; then
    die "--depth musi być >= 1"
  fi

  case "$LANG_FORCE" in
    ""|python|node|go|rust|php|ruby|bash|docker)
      ;;
    *)
      die "nieznany stack: $LANG_FORCE (dozwolone: python node go rust php ruby bash docker)"
      ;;
  esac
}

init_colors() {
  if [ "$USE_COLOR" = 1 ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'
    CYAN=$'\033[0;36m'
    NC=$'\033[0m'
  fi
}

# ---------------------------------------------------------------------------
# Wykrywanie projektów
# ---------------------------------------------------------------------------
stack_for_file() {
  case "$1" in
    requirements.txt|pyproject.toml|setup.py|setup.cfg|Pipfile|Pipfile.lock|uv.lock|poetry.lock)
      printf 'python\n'
      ;;
    package.json)
      printf 'node\n'
      ;;
    go.mod)
      printf 'go\n'
      ;;
    Cargo.toml)
      printf 'rust\n'
      ;;
    composer.json)
      printf 'php\n'
      ;;
    Gemfile)
      printf 'ruby\n'
      ;;
    compose.yaml|compose.yml|docker-compose.yaml|docker-compose.yml)
      printf 'docker\n'
      ;;
    *)
      return 1
      ;;
  esac
}

add_stack() {
  local dir=$1
  local stack=$2
  local line d s found=0 out=""

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    s=${line#*|}
    if [ "$d" = "$dir" ]; then
      case ",$s," in
        *",$stack,"*)
          return 0
          ;;
      esac
      line="$d|$s,$stack"
      found=1
    fi
    out="${out}${line}"$'\n'
  done <<< "$PROJECTS"

  if [ "$found" = 0 ]; then
    out="${out}${dir}|${stack}"$'\n'
  fi
  PROJECTS=$out
}

has_code_stack() {
  local dir=$1
  local line d s stack
  local -a stacks=()

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    [ "$d" = "$dir" ] || continue
    s=${line#*|}
    IFS=',' read -ra stacks <<< "$s"
    for stack in "${stacks[@]}"; do
      case "$stack" in
        python|node|go|rust|php|ruby)
          return 0
          ;;
      esac
    done
  done <<< "$PROJECTS"

  return 1
}

scan_projects() {
  local f rel base dir stack

  PROJECTS=""

  while IFS= read -r -d '' f; do
    rel=${f#./}
    case "$rel" in
      */*)
        dir=${rel%/*}
        base=${rel##*/}
        ;;
      *)
        dir=""
        base=$rel
        ;;
    esac
    if stack=$(stack_for_file "$base"); then
      add_stack "$dir" "$stack"
    fi
  done < <(
    find . -maxdepth "$SCAN_DEPTH" \
      \( -type d \( \
        -name .git -o -name node_modules -o -name .venv -o -name venv -o \
        -name vendor -o -name target -o -name dist -o -name build -o \
        -name .tox -o -name __pycache__ -o -name .mypy_cache -o \
        -name .pytest_cache -o -name .ruff_cache -o -name .arek-bootstrap -o \
        -name .idea -o -name .vscode \
      \) -prune \) -o \
      -type f \( \
        -name requirements.txt -o -name pyproject.toml -o -name setup.py -o \
        -name setup.cfg -o -name Pipfile -o -name Pipfile.lock -o \
        -name uv.lock -o -name poetry.lock -o -name package.json -o \
        -name go.mod -o -name Cargo.toml -o -name composer.json -o \
        -name Gemfile -o -name compose.yaml -o -name compose.yml -o \
        -name docker-compose.yaml -o -name docker-compose.yml \
      \) -print0
  )

  while IFS= read -r -d '' f; do
    rel=${f#./}
    case "$rel" in
      */*)
        dir=${rel%/*}
        base=${rel##*/}
        ;;
      *)
        dir=""
        base=$rel
        ;;
    esac
    if [ -z "$dir" ] || [ "$base" = "main.sh" ] || [ "$base" = "run.sh" ] || [ "$base" = "bootstrap.sh" ]; then
      if ! has_code_stack "$dir"; then
        add_stack "$dir" bash
      fi
    fi
  done < <(
    find . -maxdepth "$SCAN_DEPTH" \
      \( -type d \( \
        -name .git -o -name node_modules -o -name .venv -o -name venv -o \
        -name vendor -o -name target -o -name dist -o -name build -o \
        -name .tox -o -name __pycache__ -o -name .arek-bootstrap \
      \) -prune \) -o \
      -type f -name '*.sh' -print0
  )
}

is_primary_stack() {
  case "$1" in
    python|node|go|rust|php|ruby)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

root_has_primary() {
  local line d s stack
  local -a stacks=()

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    [ -z "$d" ] || continue
    s=${line#*|}
    IFS=',' read -ra stacks <<< "$s"
    for stack in "${stacks[@]}"; do
      if is_primary_stack "$stack"; then
        return 0
      fi
    done
  done <<< "$PROJECTS"

  return 1
}

select_projects() {
  local line d ignored=0

  PROJECTS=""
  SELECTED=""

  if [ -n "$LANG_FORCE" ]; then
    SELECTED="|$LANG_FORCE"$'\n'
    return 0
  fi

  scan_projects
  [ -n "$PROJECTS" ] || return 0

  PROJECTS=$(printf '%s' "$PROJECTS" | LC_ALL=C sort)

  if [ "$ALL" = 1 ]; then
    SELECTED=$PROJECTS
    return 0
  fi

  if root_has_primary; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      d=${line%%|*}
      if [ -z "$d" ]; then
        SELECTED="${SELECTED}${line}"$'\n'
      else
        ignored=$((ignored + 1))
      fi
    done <<< "$PROJECTS"
  else
    SELECTED=$PROJECTS
  fi

  if [ "$ignored" -gt 0 ]; then
    warn "pomijam $ignored projekt(y) w podkatalogach — użyj --all, aby przetworzyć wszystkie"
  fi
}

print_projects_list() {
  local line d s label

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    s=${line#*|}
    label=${d:-.}
    printf '  %-30s %s\n' "$label" "$s"
  done <<< "$SELECTED"
}

# ---------------------------------------------------------------------------
# Stemle (idempotencja)
# ---------------------------------------------------------------------------
hash_stdin() {
  if have sha256sum; then
    sha256sum | awk '{print $1}'
  elif have shasum; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1 "-" $2}'
  fi
}

hash_files() {
  local dir=$1
  shift

  if [ "$#" -eq 0 ]; then
    printf '' | hash_stdin
    return 0
  fi

  (
    cd "$dir" || exit 1
    if have sha256sum; then
      sha256sum -- "$@"
    elif have shasum; then
      shasum -a 256 -- "$@"
    else
      cksum -- "$@"
    fi
  ) | hash_stdin
}

manifest_names() {
  case "$1" in
    python)
      printf '%s\n' requirements.txt pyproject.toml setup.py setup.cfg \
        Pipfile Pipfile.lock uv.lock poetry.lock .python-version
      ;;
    node)
      printf '%s\n' package.json package-lock.json npm-shrinkwrap.json \
        pnpm-lock.yaml yarn.lock bun.lock bun.lockb .nvmrc .node-version
      ;;
    go)
      printf '%s\n' go.mod go.sum
      ;;
    rust)
      printf '%s\n' Cargo.toml Cargo.lock rust-toolchain.toml rust-toolchain
      ;;
    php)
      printf '%s\n' composer.json composer.lock
      ;;
    ruby)
      printf '%s\n' Gemfile Gemfile.lock .ruby-version
      ;;
    docker)
      printf '%s\n' compose.yaml compose.yml docker-compose.yaml docker-compose.yml
      ;;
    bash)
      ;;
  esac
}

hash_manifests() {
  local dir=$1
  local stack=$2
  local f sum=""
  local -a files=()

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$dir/$f" ]; then
      files+=("$f")
    fi
  done < <(manifest_names "$stack")

  if [ "$stack" = "bash" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      files+=("$f")
    done < <(
      cd "$dir" || exit 1
      find . -maxdepth "$SCAN_DEPTH" -type f -name '*.sh' \
        -not -path './.git/*' -not -path './node_modules/*' \
        -not -path './.venv/*' -not -path './.arek-bootstrap/*' \
        2>/dev/null | LC_ALL=C sort | sed 's|^\./||'
    )
  fi

  if [ "${#files[@]}" -gt 0 ]; then
    sum=$(hash_files "$dir" "${files[@]}")
  fi

  printf '%s|%s|%s' "$VERSION" "$stack" "$sum" | hash_stdin
}

state_path() {
  local slug=${1:-root}
  local stack=$2

  slug=${slug//\//__}
  slug=${slug// /_}
  printf '%s/state/%s.%s.stamp' "$STATE_DIR" "$slug" "$stack"
}

artifact_ok() {
  local abs=$1
  local stack=$2

  case "$stack" in
    python)
      [ -x "$abs/.venv/bin/python" ] || [ -x "$abs/.venv/Scripts/python.exe" ]
      ;;
    node)
      [ -d "$abs/node_modules" ]
      ;;
    php)
      [ -d "$abs/vendor" ]
      ;;
    *)
      return 0
      ;;
  esac
}

stamp_current() {
  local abs=$1
  local slug=$2
  local stack=$3
  local file want have_hash

  [ "$FORCE" = 1 ] && return 1

  file=$(state_path "$slug" "$stack")
  [ -f "$file" ] || return 1

  want=$(hash_manifests "$abs" "$stack")
  have_hash=$(<"$file")
  [ "$want" = "$have_hash" ] || return 1

  artifact_ok "$abs" "$stack"
}

write_stamp() {
  local abs=$1
  local slug=$2
  local stack=$3
  local file tmp

  [ "$DRY_RUN" = 1 ] && return 0

  file=$(state_path "$slug" "$stack")
  mkdir -p "$(dirname "$file")"
  tmp="$file.tmp.$$"
  hash_manifests "$abs" "$stack" > "$tmp"
  mv -f "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# Wykonywanie poleceń
# ---------------------------------------------------------------------------
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry-run]%s %s\n' "$YELLOW" "$NC" "$*"
    return 0
  fi
  "$@"
}

setup_env() {
  [ -f .env.example ] || return 0

  if [ -f .env ]; then
    debug ".env już istnieje — nie nadpisuję"
    return 0
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] cp .env.example .env"
    return 0
  fi

  cp -- .env.example .env
  log ".env utworzony z .env.example — uzupełnij sekrety"
}

# ---------------------------------------------------------------------------
# Weryfikacja łańcucha dostaw
# ---------------------------------------------------------------------------
warn_no_lockfile() {
  warn "$1: brak lockfile — instalacja nie jest powtarzalna. Zacommituj lockfile."
}

lockfile_for_stack() {
  local stack=$1
  local f

  case "$stack" in
    node)
      for f in package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb; do
        if [ -f "$f" ]; then
          printf '%s' "$f"
          return 0
        fi
      done
      ;;
    python)
      for f in uv.lock poetry.lock Pipfile.lock; do
        if [ -f "$f" ]; then
          printf '%s' "$f"
          return 0
        fi
      done
      if [ -f requirements.txt ] && grep -q -- '--hash=' requirements.txt; then
        printf 'requirements.txt (hashes)'
        return 0
      fi
      ;;
    go)
      if [ -f go.sum ]; then
        printf 'go.sum'
        return 0
      fi
      ;;
    rust)
      if [ -f Cargo.lock ]; then
        printf 'Cargo.lock'
        return 0
      fi
      ;;
    php)
      if [ -f composer.lock ]; then
        printf 'composer.lock'
        return 0
      fi
      ;;
    ruby)
      if [ -f Gemfile.lock ]; then
        printf 'Gemfile.lock'
        return 0
      fi
      ;;
  esac

  return 1
}

docker_compose_file() {
  local f

  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done

  return 1
}

check_docker_pins() {
  local label=$1
  local file img

  file=$(docker_compose_file) || return 0

  while IFS= read -r img; do
    [ -n "$img" ] || continue
    case "$img" in
      *'@sha256:'*)
        ;;
      *)
        warn "$label: obraz '$img' nie jest przypięty digestem (@sha256:…) — tag można podmienić"
        ;;
    esac
  done < <(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$file" | tr -d "\"'")

  return 0
}

# ---------------------------------------------------------------------------
# Audyt zależności (natywne narzędzia, jeśli są zainstalowane)
# ---------------------------------------------------------------------------
audit_stack() {
  local stack=$1
  local pm lockfile=0

  [ "$DO_AUDIT" = 1 ] || return 0

  case "$stack" in
    python)
      if have pip-audit; then
        log "pip-audit"
        run pip-audit || warn "pip-audit zgłasza podatności — przejrzyj: pip-audit --fix"
      else
        warn "python: brak pip-audit — zainstaluj: python -m pip install pip-audit"
      fi
      if [ -f requirements.txt ] && grep -q -- '--hash=' requirements.txt; then
        log "requirements.txt ma hashe — integralność zweryfikowana przez pip"
      fi
      ;;
    node)
      pm=$(node_manager)
      case "$pm" in
        npm)
          if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
            lockfile=1
          fi
          log "npm audit"
          run npm audit || warn "npm audit zgłasza podatności — przejrzyj: npm audit fix"
          if [ "$lockfile" = 1 ]; then
            log "npm audit signatures (podpisy rejestru)"
            run npm audit signatures || warn "npm audit signatures: weryfikacja podpisów nie powiodła się (starszy npm?)"
          fi
          ;;
        pnpm)
          log "pnpm audit"
          run pnpm audit || warn "pnpm audit zgłasza podatności"
          ;;
        yarn)
          log "yarn audit"
          run yarn audit || warn "yarn audit zgłasza podatności"
          ;;
        bun)
          warn "bun: brak wbudowanego audytu — użyj osv-scanner"
          ;;
      esac
      if have osv-scanner; then
        log "osv-scanner (node)"
        run osv-scanner scan source -r . || warn "osv-scanner zgłasza podatności"
      else
        warn "node: zainstaluj osv-scanner dla głębszego skanu (https://google.github.io/osv-scanner/)"
      fi
      ;;
    go)
      if have govulncheck; then
        log "govulncheck"
        run govulncheck ./... || warn "govulncheck zgłasza podatności"
      else
        warn "go: zainstaluj govulncheck (go install golang.org/x/vuln/cmd/govulncheck@latest)"
      fi
      if have osv-scanner; then
        log "osv-scanner (go)"
        run osv-scanner scan source -r . || warn "osv-scanner zgłasza podatności"
      fi
      ;;
    rust)
      if have cargo-audit; then
        log "cargo audit"
        run cargo audit || warn "cargo audit zgłasza podatności"
      else
        warn "rust: zainstaluj cargo-audit (cargo install cargo-audit)"
      fi
      if have osv-scanner; then
        log "osv-scanner (rust)"
        run osv-scanner scan source -r . || warn "osv-scanner zgłasza podatności"
      fi
      ;;
    php)
      log "composer audit"
      run composer audit --no-interaction || warn "composer audit zgłasza podatności"
      if have osv-scanner; then
        log "osv-scanner (php)"
        run osv-scanner scan source -r . || warn "osv-scanner zgłasza podatności"
      fi
      ;;
    ruby)
      if have bundler-audit; then
        log "bundler-audit"
        run bundler-audit check --update || warn "bundler-audit zgłasza podatności"
      else
        warn "ruby: zainstaluj bundler-audit (gem install bundler-audit)"
      fi
      if have osv-scanner; then
        log "osv-scanner (ruby)"
        run osv-scanner scan source -r . || warn "osv-scanner zgłasza podatności"
      fi
      ;;
    docker)
      if have osv-scanner; then
        log "osv-scanner (docker)"
        run osv-scanner scan source -r . || warn "osv-scanner zgłasza podatności"
      fi
      if have trivy; then
        log "trivy (obrazy)"
        # skanuje compose; bez blokowania
        run trivy config . || warn "trivy zgłasza problemy w konfiguracji"
      fi
      ;;
  esac
}

refresh_threats() {
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  section "Odświeżanie bazy zagrożeń"

  if have osv-scanner; then
    log "osv-scanner dostępny — skanuję projekt (pobierze aktualną bazę OSV)"
    if run osv-scanner scan source -r .; then
      ok "osv-scanner zakończony"
    else
      warn "osv-scanner zgłosił podatności lub błąd — przejrzyj wynik powyżej"
    fi
  else
    warn "brak osv-scanner — zainstaluj: https://google.github.io/osv-scanner/installation/"
  fi

  if have pip-audit; then
    log "pip-audit (python)"
    run pip-audit || warn "pip-audit zgłasza podatności"
  fi

  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$STATE_DIR/state"
    printf '%s\n' "$ts" > "$STATE_DIR/state/threats.stamp"
    log "znacznik odświeżenia: $STATE_DIR/state/threats.stamp ($ts)"
  else
    warn "dry-run: znacznik nie został zapisany"
  fi

  if ! have osv-scanner || ! have pip-audit || ! have cargo-audit || ! have govulncheck || ! have bundler-audit; then
    log "Zainstaluj brakujące narzędzia audytu (user-level):"
    have pip-audit || printf '  pip-audit: python -m pip install --user pip-audit  (albo: uv tool install pip-audit)\n'
    have osv-scanner || printf '  osv-scanner: https://google.github.io/osv-scanner/installation/\n'
    have cargo-audit || printf '  cargo-audit: cargo install cargo-audit\n'
    have govulncheck || printf '  govulncheck: go install golang.org/x/vuln/cmd/govulncheck@latest\n'
    have bundler-audit || printf '  bundler-audit: gem install bundler-audit\n'
  fi
}

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
pick_python() {
  local candidate

  for candidate in python3 python; do
    if have "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

python_manager() {
  if [ -f uv.lock ] && have uv; then
    printf 'uv\n'
  elif [ -f poetry.lock ] && have poetry; then
    printf 'poetry\n'
  elif [ -f Pipfile ] && have pipenv; then
    printf 'pipenv\n'
  else
    printf 'venv\n'
  fi
}

# Ścieżka do interpretera w .venv bywa różna (Linux: bin/python,
# Git-Bash/Windows: Scripts/python.exe). Nie zakładamy jednej.
venv_python_path() {
  if [ -x .venv/Scripts/python.exe ]; then
    printf '.venv/Scripts/python.exe'
  else
    printf '.venv/bin/python'
  fi
}

check_python_version() {
  local py=$1
  local want cur

  [ -f .python-version ] || return 0
  want=$(head -n 1 .python-version | tr -d 'v[:space:]')
  [ -n "$want" ] || return 0

  cur=$("$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
  case "$want" in
    "$cur"|"$cur".*)
      ;;
    *)
      warn ".python-version wymaga $want, a używany Python to $cur — jeśli to .venv, usuń go i uruchom ponownie"
      ;;
  esac
}

setup_python() {
  local py pm py_ver installed=0 vpy
  local -a pip_args=()

  if ! py=$(pick_python); then
    die "Python: brak python3 w PATH"
  fi

  py_ver=$("$py" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')
  log "python $py_ver ($py)"

  if [ -f uv.lock ] && ! have uv; then
    warn "uv.lock istnieje, ale brak uv — używam fallbacku"
  fi
  if [ -f poetry.lock ] && ! have poetry; then
    warn "poetry.lock istnieje, ale brak poetry — używam fallbacku"
  fi
  if [ -f Pipfile ] && ! have pipenv; then
    warn "Pipfile istnieje, ale brak pipenv — używam fallbacku"
  fi

  pm=$(python_manager)
  log "menedżer: $pm"

  case "$pm" in
    uv)
      run uv sync --frozen || die "uv sync nie powiódł się"
      ;;
    poetry)
      export POETRY_VIRTUALENVS_IN_PROJECT=1
      run poetry install --no-interaction --no-ansi || die "poetry install nie powiódł się"
      ;;
    pipenv)
      export PIPENV_VENV_IN_PROJECT=1
      run pipenv install --dev || die "pipenv install nie powiódł się"
      ;;
    venv)
      if [ ! -d .venv ]; then
        log "tworzę .venv"
        run "$py" -m venv .venv || die "nie udało się utworzyć .venv (Debian/Ubuntu: sudo apt install python3-venv)"
      fi
      vpy=$(venv_python_path)
      if [ "$DRY_RUN" = 0 ] && [ ! -x "$vpy" ]; then
        die ".venv istnieje, ale brak interpretera ($vpy) — usuń .venv i uruchom ponownie"
      fi

      log "aktualizuję pip"
      if ! run "$vpy" -m pip install --upgrade pip; then
        warn "nie udało się zaktualizować pip — kontynuuję z obecną wersją"
      fi

      if [ -f requirements.txt ]; then
        log "instaluję requirements.txt"
        pip_args=()
        if grep -q -- '--hash=' requirements.txt; then
          log "requirements.txt ma hashe — wymuszam --require-hashes"
          pip_args+=(--require-hashes)
        else
          warn "requirements.txt bez hashy — nie da się zweryfikować integralności pakietów"
        fi
        run "$vpy" -m pip install ${pip_args[@]+"${pip_args[@]}"} -r requirements.txt || die "instalacja requirements.txt nie powiodła się"
        installed=1
      fi

      if [ -f pyproject.toml ] && grep -qE '^\[(project|tool\.poetry)\]' pyproject.toml; then
        log "instaluję projekt w trybie editable"
        run "$vpy" -m pip install -e . || die "instalacja editable nie powiodła się"
        installed=1
      elif [ -f setup.py ] || [ -f setup.cfg ]; then
        log "instaluję projekt w trybie editable"
        run "$vpy" -m pip install -e . || die "instalacja editable nie powiodła się"
        installed=1
      fi

      if [ "$installed" = 0 ]; then
        warn "brak requirements.txt / pyproject.toml — utworzyłem samo .venv"
      fi

      if [ "$DRY_RUN" = 0 ]; then
        if ! "$vpy" -m pip check; then
          warn "pip check zgłasza problemy — przejrzyj wynik powyżej"
        fi
      fi
      ;;
  esac

  if [ -x .venv/bin/python ] || [ -x .venv/Scripts/python.exe ]; then
    check_python_version "$(venv_python_path)"
  else
    check_python_version "$py"
  fi
}

# ---------------------------------------------------------------------------
# Node
# ---------------------------------------------------------------------------
node_manager() {
  local declared=""

  if have node && [ -f package.json ]; then
    declared=$(node -e 'try{var p=require("./package.json");process.stdout.write(p.packageManager||"")}catch(e){}' 2>/dev/null || true)
  fi

  if [ -n "$declared" ]; then
    printf '%s' "${declared%%@*}"
    return 0
  fi

  if [ -f pnpm-lock.yaml ]; then
    printf 'pnpm\n'
  elif [ -f yarn.lock ]; then
    printf 'yarn\n'
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then
    printf 'bun\n'
  else
    printf 'npm\n'
  fi
}

yarn_major() {
  local version
  version=$(yarn --version 2>/dev/null || printf '1')
  printf '%s' "${version%%.*}"
}

setup_node() {
  local pm major lockfile=0
  local -a ni=()

  have node || die "Node: brak node w PATH"

  pm=$(node_manager)
  have "$pm" || die "Node: wykryto menedżer '$pm', ale nie ma go w PATH (spróbuj: corepack enable)"

  if [ "$NO_SCRIPTS" = 1 ]; then
    ni+=(--ignore-scripts)
  fi

  log "node $(node -v), menedżer: $pm"
  if [ -f .nvmrc ]; then
    log ".nvmrc: $(head -n 1 .nvmrc)"
  fi
  if [ "$NO_SCRIPTS" = 1 ]; then
    log "pomijam skrypty instalacyjne pakietów (--no-scripts)"
  fi

  case "$pm" in
    npm)
      if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
        lockfile=1
        log "npm ci (lockfile)"
        run npm ci ${ni[@]+"${ni[@]}"} || die "npm ci nie powiódł się"
      else
        warn_no_lockfile "node"
        log "npm install (brak lockfile)"
        run npm install ${ni[@]+"${ni[@]}"} || die "npm install nie powiódł się"
      fi
      ;;
    pnpm)
      if [ -f pnpm-lock.yaml ]; then
        lockfile=1
        log "pnpm install --frozen-lockfile"
        run pnpm install --frozen-lockfile ${ni[@]+"${ni[@]}"} || die "pnpm install nie powiódł się"
      else
        warn_no_lockfile "node"
        log "pnpm install (brak lockfile)"
        run pnpm install ${ni[@]+"${ni[@]}"} || die "pnpm install nie powiódł się"
      fi
      ;;
    yarn)
      major=$(yarn_major)
      case "$major" in
        0|1)
          if [ -f yarn.lock ]; then
            lockfile=1
            log "yarn install --frozen-lockfile"
            run yarn install --frozen-lockfile ${ni[@]+"${ni[@]}"} || die "yarn install nie powiódł się"
          else
            warn_no_lockfile "node"
            log "yarn install (brak lockfile)"
            run yarn install ${ni[@]+"${ni[@]}"} || die "yarn install nie powiódł się"
          fi
          ;;
        *)
          log "yarn install --immutable (Yarn $major)"
          if [ "$NO_SCRIPTS" = 1 ]; then
            run env YARN_ENABLE_SCRIPTS=false yarn install --immutable || die "yarn install nie powiódł się"
          else
            run yarn install --immutable || die "yarn install nie powiódł się"
          fi
          ;;
      esac
      ;;
    bun)
      if [ -f bun.lockb ] || [ -f bun.lock ]; then
        lockfile=1
        log "bun install --frozen-lockfile"
        run bun install --frozen-lockfile ${ni[@]+"${ni[@]}"} || die "bun install nie powiódł się"
      else
        warn_no_lockfile "node"
        log "bun install (brak lockfile)"
        run bun install ${ni[@]+"${ni[@]}"} || die "bun install nie powiódł się"
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Go / Rust / PHP / Ruby
# ---------------------------------------------------------------------------
setup_go() {
  have go || die "Go: brak go w PATH"
  log "$(go version)"
  [ -f go.sum ] || warn_no_lockfile "go"
  run go mod download || die "go mod download nie powiódł się"
  run go mod verify || warn "go mod verify zgłasza problemy"
}

setup_rust() {
  have cargo || die "Rust: brak cargo w PATH"
  log "$(cargo --version)"
  if [ -f Cargo.lock ]; then
    run cargo fetch --locked || die "cargo fetch --locked nie powiódł się"
  else
    warn_no_lockfile "rust"
    run cargo fetch || die "cargo fetch nie powiódł się"
  fi
}

setup_php() {
  local -a ca=()

  have composer || die "PHP: brak composer w PATH"
  log "$(composer --version 2>/dev/null | head -n 1)"
  [ -f composer.lock ] || warn_no_lockfile "php"

  if [ "$NO_SCRIPTS" = 1 ]; then
    ca+=(--no-scripts)
  fi

  run composer install --no-interaction --prefer-dist ${ca[@]+"${ca[@]}"} || die "composer install nie powiódł się"
}

setup_ruby() {
  have bundle || die "Ruby: brak bundlera (gem install bundler)"
  log "$(ruby --version 2>/dev/null || printf 'ruby')"

  if [ -f Gemfile.lock ]; then
    if [ "$DRY_RUN" = 0 ]; then
      run bundle config set --local frozen true || warn "bundle config frozen nie powiódł się"
    fi
  else
    warn_no_lockfile "ruby"
  fi

  if [ "$DRY_RUN" = 1 ]; then
    run bundle install
  elif bundle check >/dev/null 2>&1; then
    log "gemy już zainstalowane"
  else
    run bundle install || die "bundle install nie powiódł się"
  fi
}

# ---------------------------------------------------------------------------
# bash / Docker
# ---------------------------------------------------------------------------
setup_bash() {
  local f bad=0

  while IFS= read -r -d '' f; do
    if ! bash -n "$f" 2>/dev/null; then
      warn "bash: błąd składni w ${f#./}"
      bad=1
    fi
  done < <(
    find . -maxdepth "$SCAN_DEPTH" \
      \( -type d \( \
        -name .git -o -name node_modules -o -name .venv -o -name venv -o \
        -name vendor -o -name target -o -name .arek-bootstrap \
      \) -prune \) -o \
      -type f -name '*.sh' -print0
  )

  if [ "$bad" = 1 ]; then
    die "bash: popraw błędy składni"
  fi
  log "bash: składnia skryptów OK"
}

setup_docker() {
  local file=""

  file=$(docker_compose_file) || file=""

  if [ -z "$file" ]; then
    warn "docker: brak pliku compose w tym katalogu"
    return 0
  fi

  check_docker_pins "docker"

  if have docker && docker compose version >/dev/null 2>&1; then
    log "waliduję $file (docker compose)"
    run docker compose -f "$file" config -q || die "docker compose: niepoprawny $file"
    if [ "$DOCKER_UP" = 1 ]; then
      log "docker compose up -d --build"
      run docker compose -f "$file" up -d --build || die "docker compose up nie powiódł się"
    fi
  elif have docker-compose; then
    log "waliduję $file (docker-compose)"
    run docker-compose -f "$file" config -q || die "docker-compose: niepoprawny $file"
    if [ "$DOCKER_UP" = 1 ]; then
      log "docker-compose up -d --build"
      run docker-compose -f "$file" up -d --build || die "docker-compose up nie powiódł się"
    fi
  else
    warn "docker: brak docker compose — pomijam walidację $file"
  fi
}

# ---------------------------------------------------------------------------
# Raport
# ---------------------------------------------------------------------------
show_tool() {
  local label=$1
  shift
  local out

  if have "$1"; then
    out=$("$@" 2>&1) || out="(błąd)"
    out=${out%%$'\n'*}
  else
    out="brak"
  fi

  printf '  %-9s %s\n' "$label:" "$out"
}

print_report() {
  local line d s stack label abs status
  local -a stacks=()

  section "Projekty"
  print_projects_list

  section "Status stempli"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    s=${line#*|}
    label=${d:-.}
    abs="$ROOT${d:+/$d}"
    IFS=',' read -ra stacks <<< "$s"
    for stack in "${stacks[@]}"; do
      if stamp_current "$abs" "$d" "$stack"; then
        status="aktualne"
      else
        status="do zrobienia"
      fi
      printf '  %-24s %-8s %s\n' "$label" "$stack" "$status"
    done
  done <<< "$SELECTED"

  section "Narzędzia"
  show_tool python python3 --version
  show_tool node node --version
  show_tool npm npm --version
  show_tool pnpm pnpm --version
  show_tool yarn yarn --version
  show_tool bun bun --version
  show_tool go go version
  show_tool cargo cargo --version
  show_tool php php --version
  show_tool composer composer --version
  show_tool ruby ruby --version
  show_tool bundle bundle --version
  show_tool docker docker --version
  show_tool uv uv --version
  show_tool poetry poetry --version
  show_tool pipenv pipenv --version

  section "Audyt (narzędzia)"
  printf '  %-14s %s\n' "pip-audit:" "$(have pip-audit && echo dostępny || echo brak)"
  printf '  %-14s %s\n' "cargo-audit:" "$(have cargo-audit && echo dostępny || echo brak)"
  printf '  %-14s %s\n' "govulncheck:" "$(have govulncheck && echo dostępny || echo brak)"
  printf '  %-14s %s\n' "bundler-audit:" "$(have bundler-audit && echo dostępny || echo brak)"
  printf '  %-14s %s\n' "osv-scanner:" "$(have osv-scanner && echo dostępny || echo brak)"
  printf '  %-14s %s\n' "trivy:" "$(have trivy && echo dostępny || echo brak)"

  section "Stan"
  printf '  katalog stanu: %s\n' ".arek-bootstrap"
  printf '  wersja:        %s\n' "$VERSION"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  tryb:          dry-run (nic nie zostanie zmienione)\n'
  fi
}

print_security_report() {
  local line d s stack abs label lf
  local -a stacks=()

  section "Łańcuch dostaw"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    s=${line#*|}
    abs="$ROOT${d:+/$d}"
    label=${d:-.}
    [ -d "$abs" ] || continue

    pushd "$abs" >/dev/null

    IFS=',' read -ra stacks <<< "$s"
    for stack in "${stacks[@]}"; do
      case "$stack" in
        docker)
          check_docker_pins "$label"
          ;;
        bash)
          ;;
        *)
          if lf=$(lockfile_for_stack "$stack"); then
            printf '  %-24s %-8s lockfile: %s\n' "$label" "$stack" "$lf"
          else
            printf '  %-24s %-8s %s\n' "$label" "$stack" "brak lockfile"
            warn "$label ($stack): brak lockfile — instalacja nie jest powtarzalna"
          fi
          ;;
      esac
    done

    popd >/dev/null
  done <<< "$SELECTED"
}

# ---------------------------------------------------------------------------
# Główna pętla
# ---------------------------------------------------------------------------
process_selected() {
  local line d s stack abs label
  local -a stacks=()

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d=${line%%|*}
    s=${line#*|}
    abs="$ROOT${d:+/$d}"
    label=${d:-.}

    section "$label"
    pushd "$abs" >/dev/null
    setup_env

    IFS=',' read -ra stacks <<< "$s"
    for stack in "${stacks[@]}"; do
      if stamp_current "$abs" "$d" "$stack"; then
        ok "$stack — aktualne (pomijam)"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi

      if ! declare -F "setup_$stack" >/dev/null 2>&1; then
        popd >/dev/null
        die "brak obsługi stacku: $stack"
      fi

      log "$stack — konfiguruję"
      "setup_$stack"
      audit_stack "$stack"
      write_stamp "$abs" "$d" "$stack"
      DONE=$((DONE + 1))
    done

    popd >/dev/null
  done <<< "$SELECTED"
}

main() {
  parse_args "$@"
  init_colors

  [ -n "$ROOT" ] || ROOT=$PWD
  [ -d "$ROOT" ] || die "katalog projektu nie istnieje: $ROOT"
  ROOT="$(cd "$ROOT" && pwd)" || die "nie mogę wejść do katalogu: $ROOT"
  STATE_DIR="$ROOT/.arek-bootstrap"
  cd "$ROOT" || die "nie mogę wejść do katalogu projektu: $ROOT"

  if [ "$QUIET" = 0 ]; then
    printf '%s%s%s\n' "$CYAN" "arek-bootstrap $VERSION — self-setup projektu ($ROOT)" "$NC"
  fi

  select_projects

  if [ "$REFRESH_THREATS" = 1 ]; then
    refresh_threats
    exit 0
  fi

  if [ "$LIST" = 1 ]; then
    if [ -z "$SELECTED" ]; then
      warn "nie wykryto żadnego projektu"
    else
      section "Projekty"
      print_projects_list
    fi
    exit 0
  fi

  if [ -z "$SELECTED" ]; then
    if [ "$CHECK_ONLY" = 1 ]; then
      warn "nie wykryto projektu — brak manifestów i skryptów"
      exit 0
    fi
    die "nie wykryto projektu (szukam: requirements.txt, pyproject.toml, package.json, go.mod, Cargo.toml, composer.json, Gemfile, compose.yaml, *.sh). Użyj --lang, aby wymusić stack, albo --root <katalog>, aby wskazać projekt."
  fi

  if [ "$CHECK_ONLY" = 1 ]; then
    print_security_report
    print_report
    log "Tryb check-only — nic nie zmieniono."
    exit 0
  fi

  section "Wykryte projekty"
  print_projects_list

  process_selected

  section "Gotowe"
  if [ "$QUIET" = 0 ]; then
    printf '  wykonane stacki: %d, pominięte (aktualne): %d\n' "$DONE" "$SKIPPED"
  fi
  if [ "$DRY_RUN" = 1 ]; then
    warn "dry-run: żadne zmiany nie zostały zapisane"
  fi
  if [ "$QUIET" = 0 ]; then
    printf '\n  Uruchom projekt zgodnie z README.md projektu.\n'
  fi
}

main "$@"
