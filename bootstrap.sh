#!/bin/bash
# ============================================================================
# arek-bootstrap — jeden skrypt stawia projekt od zera.
# Filozofia: żaden kolejny Arek (ani obca osoba) nie ma się męczyć z venv,
# wersjami i zależnościami. Projekt ma sam się ustawić.
#
# Użycie:
#   ./bootstrap.sh                     # wykryj język i postaw projekt
#   ./bootstrap.sh --lang python|node  # wymuś język
#   ./bootstrap.sh --check-only        # tylko sprawdź środowisko
# ============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[X]${NC} $1"; exit 1; }

CHECK_ONLY=0; FORCE_LANG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1 ;;
    --lang) FORCE_LANG="$2"; shift ;;
    *) warn "Nieznany argument: $1" ;;
  esac
  shift
done

detect_lang() {
  [ -n "$FORCE_LANG" ] && { echo "$FORCE_LANG"; return; }
  if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ]; then echo "python"; return; fi
  if [ -f package.json ]; then echo "node"; return; fi
  if [ -f *.sh ]; then echo "bash"; return; fi
  echo "unknown"
}

setup_python() {
  log "Python: tworzę venv..."
  command -v python3 >/dev/null || fail "brak python3"
  [ -d .venv ] || python3 -m venv .venv
  source .venv/bin/activate
  log "venv: aktualizuję pip..."
  pip install --upgrade pip -q
  if [ -f requirements.txt ]; then
    log "venv: instaluje wymagania z requirements.txt..."
    pip install -r requirements.txt
  fi
  if [ -f pyproject.toml ]; then
    log "venv: instaluje w trybie editable..."
    pip install -e . -q
  fi
  log "venv: kontrola pip check..."
  pip check || warn "pip check zgłasza uwagi"
}

setup_node() {
  command -v node >/dev/null || fail "brak node"
  command -v npm  >/dev/null || fail "brak npm"
  log "node $(node -v)"
  if [ -d node_modules ]; then warn "node_modules już istnieje — pomijam install"; else
    log "npm: instaluję zależności..."
    npm install
  fi
  log "npm: audyt bezpieczeństwa..."
  npm audit || warn "npm audit zgłasza podatności — przejrzyj: npm audit fix"
}

setup_bash() {
  log "bash: projekt oparty o skrypty — tylko kontrola składni"
  local bad=0
  for f in *.sh; do
    bash -n "$f" 2>/dev/null || { warn "błąd składni: $f"; bad=1; }
  done
  [ "$bad" = 0 ] && log "bash: składnia wszystkich skryptów OK"
}

env_from_example() {
  if [ -f .env.example ] && [ ! -f .env ]; then
    cp .env.example .env
    log ".env utworzony z .env.example — uzupełnij prawdziwe wartości"
  fi
}

check_env() {
  log "----- RAPORT ŚRODOWISKA -----"
  echo "  katalog:   $ROOT"
  echo "  język:     $(detect_lang)"
  echo "  python:    $(command -v python3 >/dev/null && python3 --version 2>&1 || echo brak)"
  echo "  node:      $(command -v node >/dev/null && node -v 2>&1 || echo brak)"
  [ -f .venv/bin/python ] && echo "  venv:      OK" || echo "  venv:      brak (zostanie utworzony)"
  echo "  disk użycie: $(du -sh . 2>/dev/null | cut -f1)"
}

main() {
  log "arek-bootstrap — self-setup projektu"
  check_env
  LANG_NAME=$(detect_lang)
  [ "$LANG_NAME" = "unknown" ] && fail "Nie wykryto języka projektu (requirements.txt/package.json/*.sh)."

  if [ "$CHECK_ONLY" = 1 ]; then
    log "Tryb check-only — koniec."
    exit 0
  fi

  env_from_example

  case "$LANG_NAME" in
    python) setup_python ;;
    node)   setup_node ;;
    bash)   setup_bash ;;
  esac

  log "--- Gotowe. Projekt postawiony. ---"
  echo ""
  echo "  Uruchom projekt zgodnie z README.md projektu."
}

main "$@"