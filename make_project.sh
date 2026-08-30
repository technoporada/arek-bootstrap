#!/bin/bash
# ============================================================================
# make_project.sh — generuje szkielet nowego projektu "po Arku":
# projekt od razu z bootstrapem, gitignore, README i licencją.
# Żaden nowy projekt nie zaczyna się od zera w bólu.
#
# Użycie:
#   ./make_project.sh moj_nowy_projekt python
#   ./make_project.sh moj_front node
# ============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

NAME="${1:?Użycie: make_project.sh <nazwa> [python|node|bash]}"
LANG_TYPE="${2:-auto}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ -e "$ROOT/$NAME" ]; then
  echo -e "${RED}[X]${NC} '$NAME' już istnieje."
  exit 1
fi

mkdir -p "$ROOT/$NAME"
cd "$ROOT/$NAME"

echo -e "${CYAN}[+]${NC} Tworzę projekt '$NAME' (typ: $LANG_TYPE)"

# --- Wspólne pliki ---
cat > README.md <<EOF
# $NAME

${NAME} — opis tutaj.

## Self-setup

Ten projekt stawia się sam:

\`\`\`bash
./bootstrap.sh
\`\`\`

## Wymagania

- (lista minimalnych narzędzi, np. Python 3.10+ / Node 20+)
EOF

cat > .gitignore <<'EOF'
# środowiska
.venv/
venv/
node_modules/
__pycache__/
*.pyc

# dane i build
.env
*.log
dist/
build/
reports/
EOF

# --- Pliki specyficzne dla języka ---
case "$LANG_TYPE" in
  python|auto)
    if [ "$LANG_TYPE" = auto ] && ! command -v python3 >/dev/null; then
      LANG_TYPE=node
    fi
    ;;
esac

case "$LANG_TYPE" in
  python)
    echo "" > requirements.txt
    cat > main.py <<'EOF'
def main():
    print("Działa! (${NAME} — python)")


if __name__ == "__main__":
    main()
EOF
    ;;
  node)
    npm init -y >/dev/null 2>&1 || true
    node -e "const p=require('./package.json'); p.scripts={start:'node main.js'}; require('fs').writeFileSync('package.json', JSON.stringify(p,null,2));"
    printf 'console.log("Działa! (%s — node)");\n' "$NAME" > main.js
    ;;
  bash|auto)
    cat > main.sh <<'EOF'
#!/bin/bash
echo "Działa! (skrypt bash)"
EOF
    ;;
  *)
    echo -e "${RED}[X]${NC} Nieznany typ: $LANG_TYPE (python|node|bash)"
    exit 1
    ;;
esac

# Bootstrap w projekcie
cp "$ROOT/bootstrap.sh" "./bootstrap.sh"
chmod +x "./bootstrap.sh" "./main.sh" 2>/dev/null || true

echo ""
echo -e "${GREEN}[+]${NC} Projekt '$NAME' gotowy:"
echo "    cd $NAME"
echo "    ./bootstrap.sh   # postawi środowisko sam"
echo "    (uzupełnij README.md i kod)"