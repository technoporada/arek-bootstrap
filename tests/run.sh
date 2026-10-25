#!/usr/bin/env bash
# =============================================================================
# Testy arek-bootstrap. Bez sieci, bez instalowania zależności.
#
# Uruchomienie: bash tests/run.sh
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$ROOT/bootstrap.sh"
MAKE="$ROOT/make_project.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/arek-bootstrap-tests.XXXXXX")"

PASS=0
FAIL=0
OUT=""
RC=0

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf '       %s\n' "$2"
  fi
}

run_cmd() {
  local dir=$1
  shift
  if OUT=$(cd "$dir" && "$@" 2>&1); then
    RC=0
  else
    RC=$?
  fi
}

assert_rc_zero() {
  if [ "$RC" -eq 0 ]; then
    pass "$1"
  else
    fail "$1" "kod wyjścia: $RC"
  fi
}

assert_rc_nonzero() {
  if [ "$RC" -ne 0 ]; then
    pass "$1"
  else
    fail "$1" "oczekiwano błędu, kod wyjścia: 0"
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local msg=$3
  case "$haystack" in
    *"$needle"*)
      pass "$msg"
      ;;
    *)
      fail "$msg" "brak: '$needle'"
      ;;
  esac
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  local msg=$3
  case "$haystack" in
    *"$needle"*)
      fail "$msg" "nie oczekiwano: '$needle'"
      ;;
    *)
      pass "$msg"
      ;;
  esac
}

assert_file() {
  if [ -f "$1" ]; then
    pass "$2"
  else
    fail "$2" "brak pliku: $1"
  fi
}

assert_no_file() {
  if [ ! -e "$1" ]; then
    pass "$2"
  else
    fail "$2" "plik istnieje: $1"
  fi
}

assert_dir() {
  if [ -d "$1" ]; then
    pass "$2"
  else
    fail "$2" "brak katalogu: $1"
  fi
}

assert_eq() {
  if [ "$1" = "$2" ]; then
    pass "$3"
  else
    fail "$3" "oczekiwano '$2', jest '$1'"
  fi
}

assert_file_contains() {
  local file=$1
  local needle=$2
  local msg=$3
  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    pass "$msg"
  else
    fail "$msg" "brak '$needle' w $file"
  fi
}

assert_file_not_contains() {
  local file=$1
  local needle=$2
  local msg=$3
  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    fail "$msg" "nie oczekiwano '$needle' w $file"
  else
    pass "$msg"
  fi
}

have() {
  command -v "$1" >/dev/null 2>&1
}

# =============================================================================
printf '\n== help / wersja ==\n'
run_cmd "$TMP" "$BOOTSTRAP" --help
assert_rc_zero "--help kończy się kodem 0"
assert_contains "$OUT" "Użycie:" "--help pokazuje użycie"
assert_contains "$OUT" "--check-only" "--help pokazuje tryb check-only"
assert_contains "$OUT" "--no-scripts" "--help pokazuje --no-scripts"

run_cmd "$TMP" "$BOOTSTRAP" --version
assert_rc_zero "--version kończy się kodem 0"
assert_contains "$OUT" "2.1.0" "--version pokazuje wersję"

run_cmd "$TMP" "$BOOTSTRAP" --nieznana-opcja
assert_rc_nonzero "nieznana opcja kończy się błędem"

run_cmd "$TMP" "$BOOTSTRAP" --lang brainfuck
assert_rc_nonzero "nieznany stack kończy się błędem"

# =============================================================================
printf '\n== wykrywanie: Python ==\n'
py="$TMP/py"
mkdir -p "$py"
cat > "$py/pyproject.toml" <<'EOF'
[project]
name = "x"
version = "0.1.0"
EOF

run_cmd "$py" "$BOOTSTRAP" --check-only
assert_rc_zero "check-only dla Pythona kończy się kodem 0"
assert_contains "$OUT" "python" "wykryto python"
assert_contains "$OUT" "brak lockfile" "check-only ostrzega o braku lockfile"
assert_no_file "$py/.venv" "check-only nie tworzy .venv"
assert_no_file "$py/.arek-bootstrap" "check-only nie tworzy stanu"
assert_no_file "$py/.env" "check-only nie tworzy .env"

# =============================================================================
printf '\n== wykrywanie: monorepo Node ==\n'
mono="$TMP/mono"
mkdir -p "$mono/apps/api" "$mono/apps/web"
printf '{"name":"api"}\n' > "$mono/apps/api/package.json"
printf '{"name":"web"}\n' > "$mono/apps/web/package.json"

run_cmd "$mono" "$BOOTSTRAP" --list
assert_rc_zero "--list w monorepo kończy się kodem 0"
assert_contains "$OUT" "apps/api" "--list pokazuje apps/api"
assert_contains "$OUT" "apps/web" "--list pokazuje apps/web"
assert_contains "$OUT" "node" "--list pokazuje stack node"
assert_no_file "$mono/.arek-bootstrap" "--list nie tworzy stanu"

lock="$TMP/locknode"
mkdir -p "$lock"
printf '{"name":"locknode","lockfileVersion":3}\n' > "$lock/package.json"
printf '{}\n' > "$lock/package-lock.json"

run_cmd "$lock" "$BOOTSTRAP" --check-only
assert_rc_zero "check-only dla node z lockfile kończy się kodem 0"
assert_contains "$OUT" "lockfile: package-lock.json" "check-only rozpoznaje lockfile npm"

# =============================================================================
printf '\n== katalog główny ma pierwszeństwo ==\n'
rootpref="$TMP/rootpref"
mkdir -p "$rootpref/sub"
printf '{"name":"root"}\n' > "$rootpref/package.json"
printf '{"name":"sub"}\n' > "$rootpref/sub/package.json"

run_cmd "$rootpref" "$BOOTSTRAP" --list
assert_contains "$OUT" "." "--list pokazuje katalog główny"
assert_not_contains "$OUT" "sub " "bez --all podkatalog jest pomijany"
assert_contains "$OUT" "pomijam" "jest ostrzeżenie o pominiętych podkatalogach"

run_cmd "$rootpref" "$BOOTSTRAP" --list --all
assert_contains "$OUT" "sub" "--all pokazuje podkatalog"

# =============================================================================
printf '\n== idempotencja (bash) ==\n'
b1="$TMP/b1"
mkdir -p "$b1"
printf '#!/usr/bin/env bash\necho b1\n' > "$b1/main.sh"

run_cmd "$b1" "$BOOTSTRAP"
assert_rc_zero "pierwszy bootstrap bash kończy się kodem 0"
assert_dir "$b1/.arek-bootstrap/state" "powstał katalog stanu"
assert_contains "$OUT" "bash — konfiguruję" "pierwszy przebieg konfiguruje bash"

run_cmd "$b1" "$BOOTSTRAP"
assert_rc_zero "drugi bootstrap bash kończy się kodem 0"
assert_contains "$OUT" "aktualne (pomijam)" "drugi przebieg pomija aktualny stack"

printf '\n# zmiana\n' >> "$b1/main.sh"
run_cmd "$b1" "$BOOTSTRAP"
assert_not_contains "$OUT" "aktualne (pomijam)" "zmiana skryptu unieważnia stempel"
assert_contains "$OUT" "bash: składnia skryptów OK" "zmieniony skrypt jest sprawdzany"

run_cmd "$b1" "$BOOTSTRAP" --force
assert_not_contains "$OUT" "aktualne (pomijam)" "--force wymusza ponowne wykonanie"

# =============================================================================
printf '\n== dry-run ==\n'
dry="$TMP/dry"
mkdir -p "$dry"
printf '#!/usr/bin/env bash\necho dry\n' > "$dry/main.sh"
printf 'APP_ENV=dev\n' > "$dry/.env.example"

run_cmd "$dry" "$BOOTSTRAP" --dry-run
assert_rc_zero "dry-run kończy się kodem 0"
assert_contains "$OUT" "[dry-run]" "dry-run pokazuje polecenia"
assert_no_file "$dry/.env" "dry-run nie tworzy .env"
assert_no_file "$dry/.arek-bootstrap" "dry-run nie tworzy stanu"

# =============================================================================
printf '\n== .env z .env.example ==\n'
envp="$TMP/envp"
mkdir -p "$envp"
printf '#!/usr/bin/env bash\necho env\n' > "$envp/main.sh"
printf 'SECRET=from_example\n' > "$envp/.env.example"

run_cmd "$envp" "$BOOTSTRAP"
assert_rc_zero "bootstrap z .env.example kończy się kodem 0"
assert_file "$envp/.env" "powstał .env"
assert_file_contains "$envp/.env" "SECRET=from_example" ".env ma treść przykładu"

printf 'SECRET=moja_wartosc\n' > "$envp/.env"
run_cmd "$envp" "$BOOTSTRAP" --force
assert_file_contains "$envp/.env" "SECRET=moja_wartosc" "istniejący .env nie jest nadpisywany"

# =============================================================================
printf '\n== monorepo bash ==\n'
mm="$TMP/mm"
mkdir -p "$mm/apps/a" "$mm/apps/b"
printf '#!/usr/bin/env bash\necho a\n' > "$mm/apps/a/main.sh"
printf '#!/usr/bin/env bash\necho b\n' > "$mm/apps/b/main.sh"

run_cmd "$mm" "$BOOTSTRAP"
assert_rc_zero "monorepo bash kończy się kodem 0"
stamps=$(find "$mm/.arek-bootstrap/state" -type f -name '*.stamp' | wc -l | tr -d ' ')
assert_eq "$stamps" "2" "powstały dwa stemple dla dwóch podprojektów"

# =============================================================================
printf '\n== --root ==\n'
rp="$TMP/rootproj"
mkdir -p "$rp"
printf '#!/usr/bin/env bash\necho root\n' > "$rp/main.sh"

run_cmd "$TMP" "$BOOTSTRAP" --root "$rp"
assert_rc_zero "--root działa spoza katalogu projektu"
assert_dir "$rp/.arek-bootstrap/state" "stan powstał w katalogu --root"
assert_no_file "$TMP/.arek-bootstrap" "stan nie powstał w bieżącym katalogu"

# =============================================================================
printf '\n== symlink / dowolna ścieżka ==\n'
linkbin="$TMP/bin"
mkdir -p "$linkbin"
ln -s "$BOOTSTRAP" "$linkbin/arek-bootstrap"
ln -s "$MAKE" "$linkbin/arek-make-project"

linkwork="$TMP/linkwork"
mkdir -p "$linkwork"

run_cmd "$linkwork" "$linkbin/arek-make-project" linkproj bash --no-git
assert_rc_zero "generator działa przez symlink"
assert_file "$linkwork/linkproj/main.sh" "generator przez symlink tworzy pliki"

run_cmd "$linkwork/linkproj" "$linkbin/arek-bootstrap"
assert_rc_zero "bootstrap działa przez symlink"
assert_dir "$linkwork/linkproj/.arek-bootstrap/state" "bootstrap przez symlink tworzy stan"

# =============================================================================
printf '\n== --lang ==\n'
forced="$TMP/forced"
mkdir -p "$forced"

run_cmd "$forced" "$BOOTSTRAP" --lang bash --dry-run
assert_rc_zero "--lang bash kończy się kodem 0"
assert_contains "$OUT" "bash — konfiguruję" "--lang wymusza stack bash"
assert_no_file "$forced/.arek-bootstrap" "--lang --dry-run nie tworzy stanu"

# =============================================================================
printf '\n== Docker (wykrywanie) ==\n'
dock="$TMP/dock"
mkdir -p "$dock"
cat > "$dock/compose.yaml" <<'EOF'
services:
  app:
    image: alpine
EOF

run_cmd "$dock" "$BOOTSTRAP" --check-only
assert_rc_zero "check-only dla compose kończy się kodem 0"
assert_contains "$OUT" "docker" "wykryto docker"
assert_contains "$OUT" "nie jest przypięty digestem" "check-only ostrzega o obrazie bez digestu"

digest="$TMP/digest"
mkdir -p "$digest"
cat > "$digest/compose.yaml" <<'EOF'
services:
  app:
    image: alpine@sha256:0000000000000000000000000000000000000000000000000000000000000000
EOF

run_cmd "$digest" "$BOOTSTRAP" --check-only
assert_rc_zero "check-only dla obrazu z digestem kończy się kodem 0"
assert_not_contains "$OUT" "nie jest przypięty digestem" "obraz z digestem nie daje ostrzeżenia"

# =============================================================================
printf '\n== --no-scripts ==\n'
nos="$TMP/noscripts"
mkdir -p "$nos"
printf '#!/usr/bin/env bash\necho nos\n' > "$nos/main.sh"

run_cmd "$nos" "$BOOTSTRAP" --no-scripts --dry-run
assert_rc_zero "--no-scripts jest akceptowane"
assert_contains "$OUT" "bash — konfiguruję" "--no-scripts nie blokuje normalnego wykrywania"

# =============================================================================
printf '\n== generator: Python ==\n'
gen="$TMP/gen"
mkdir -p "$gen"

run_cmd "$gen" "$MAKE" demo-py python --no-git
assert_rc_zero "make_project python kończy się kodem 0"
assert_file "$gen/demo-py/pyproject.toml" "powstał pyproject.toml"
assert_file "$gen/demo-py/main.py" "powstał main.py"
assert_file "$gen/demo-py/bootstrap.sh" "powstał bootstrap.sh"
assert_file "$gen/demo-py/LICENSE" "powstała licencja MIT"
assert_file "$gen/demo-py/.env.example" "powstał .env.example"
assert_file "$gen/demo-py/.editorconfig" "powstał .editorconfig"
assert_file_contains "$gen/demo-py/main.py" "Działa! (demo-py - python)" "main.py ma poprawną nazwę"
# shellcheck disable=SC2016
assert_file_not_contains "$gen/demo-py/main.py" '${NAME}' "main.py nie ma surowego placeholdera"
assert_file_contains "$gen/demo-py/README.md" "# demo-py" "README ma nazwę projektu"

run_cmd "$gen/demo-py" "$BOOTSTRAP" --check-only
assert_rc_zero "wygenerowany projekt przechodzi check-only"
assert_contains "$OUT" "python" "wygenerowany projekt jest wykrywany jako python"

# =============================================================================
printf '\n== generator: pozostałe typy ==\n'
for spec in \
  "demo-node:node:package.json" \
  "demo-go:go:go.mod" \
  "demo-rust:rust:Cargo.toml" \
  "demo-php:php:composer.json" \
  "demo-ruby:ruby:Gemfile" \
  "demo-bash:bash:main.sh"
do
  name=${spec%%:*}
  rest=${spec#*:}
  type=${rest%%:*}
  expected=${rest#*:}

  run_cmd "$gen" "$MAKE" "$name" "$type" --no-git
  assert_rc_zero "make_project $type kończy się kodem 0"
  assert_file "$gen/$name/$expected" "make_project $type tworzy $expected"
done

assert_file "$gen/demo-rust/src/main.rs" "Rust ma src/main.rs"
assert_file_contains "$gen/demo-node/main.js" "Działa! (demo-node - node)" "Node ma poprawny main.js"

# =============================================================================
printf '\n== generator: opcje ==\n'
run_cmd "$gen" "$MAKE" demo-docker bash --no-git --with-docker
assert_rc_zero "make_project --with-docker kończy się kodem 0"
assert_file "$gen/demo-docker/Dockerfile" "--with-docker tworzy Dockerfile"
assert_file "$gen/demo-docker/compose.yaml" "--with-docker tworzy compose.yaml"
assert_file "$gen/demo-docker/.dockerignore" "--with-docker tworzy .dockerignore"

run_cmd "$gen" "$MAKE" demo-nolicense bash --no-git --license none
assert_rc_zero "make_project --license none kończy się kodem 0"
assert_no_file "$gen/demo-nolicense/LICENSE" "--license none nie tworzy LICENSE"

if have git; then
  run_cmd "$gen" "$MAKE" demo-git bash
  assert_rc_zero "make_project z git kończy się kodem 0"
  assert_dir "$gen/demo-git/.git" "make_project inicjuje repozytorium git"
fi

mkdir -p "$gen/into"
run_cmd "$gen" "$MAKE" demo-into bash --no-git --into "$gen/into"
assert_rc_zero "make_project --into kończy się kodem 0"
assert_file "$gen/into/demo-into/main.sh" "--into tworzy projekt w wskazanym katalogu"

# =============================================================================
printf '\n== generator: walidacja ==\n'
run_cmd "$gen" "$MAKE" "../evil" python --no-git
assert_rc_nonzero "nazwa z ukośnikiem jest odrzucana"
assert_no_file "$TMP/evil" "path traversal nie tworzy katalogu"

run_cmd "$gen" "$MAKE" "-zla" python --no-git
assert_rc_nonzero "nazwa zaczynająca się od - jest odrzucana"

mkdir -p "$gen/existing"
run_cmd "$gen" "$MAKE" existing python --no-git
assert_rc_nonzero "istniejący katalog jest odrzucany"

run_cmd "$gen" "$MAKE" demo-bad brainfuck --no-git
assert_rc_nonzero "nieznany typ jest odrzucany"

# Generator bez bootstrap.sh powinien posprzątać niekompletny projekt.
lone="$TMP/lone"
mkdir -p "$lone"
cp -- "$MAKE" "$lone/make_project.sh"
run_cmd "$TMP" "$lone/make_project.sh" orphan bash --no-git
assert_rc_nonzero "brak bootstrap.sh przerywa generowanie"
assert_no_file "$TMP/orphan" "niekompletny projekt jest usuwany"

# =============================================================================
printf '\n== utwardzenie repo ==\n'
assert_file "$ROOT/SECURITY.md" "istnieje SECURITY.md"
assert_file "$ROOT/.github/dependabot.yml" "istnieje konfiguracja Dependabota"

wf_dir="$ROOT/.github/workflows"
assert_dir "$wf_dir" "istnieje katalog workflowów"

for wf in "$wf_dir"/*.yml; do
  [ -f "$wf" ] || continue
  assert_file_contains "$wf" "persist-credentials: false" "$(basename "$wf"): checkout nie zostawia poświadczeń" 2>/dev/null || true
done

if grep -rqE '^[[:space:]]*uses:[[:space:]]*[^#]+@[0-9a-f]{40}([[:space:]]|$)' "$wf_dir"; then
  pass "akcje w workflowach są przypięte do pełnego SHA"
else
  fail "akcje w workflowach są przypięte do pełnego SHA" "brak uses: ...@<40-hex>"
fi

if grep -rnE '^[[:space:]]*uses:[[:space:]]*[^#]+@(v[0-9]+|main|master)([[:space:]]|$)' "$wf_dir"; then
  fail "brak akcji na ruchomym tagu" "znaleziono uses: ...@tag"
else
  pass "brak akcji na ruchomym tagu"
fi

assert_file "$wf_dir/release.yml" "istnieje workflow release"
assert_file_contains "$wf_dir/ci.yml" "sha256sum -c" "CI weryfikuje ShellCheck SHA256"

# =============================================================================
printf '\n== puste repozytorium ==\n'
empty="$TMP/empty"
mkdir -p "$empty"
run_cmd "$empty" "$BOOTSTRAP" --check-only
assert_rc_zero "check-only w pustym katalogu kończy się kodem 0"
assert_contains "$OUT" "nie wykryto projektu" "pusty katalog daje czytelny komunikat"

printf '\n----------------------------------------\n'
printf 'Wynik: %d ok, %d failed\n' "$PASS" "$FAIL"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
