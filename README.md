# arek-bootstrap

**„Każdy projekt stawia się sam.”**

Jeden skrypt, który wchodzi w projekt, rozpoznaje stack i doprowadza
środowisko do stanu używalności. Bez czytania 40 kroków instrukcji, bez
zgadywania, czy `npm install` czy `npm ci`, bez ręcznego kopiowania `.env`.

Wersja 2 porządkuje to, co w wersji 1 było zbyt naiwne: wykrywanie wielu
stacków, menedżerów pakietów, monorepo, Docker oraz — przede wszystkim —
**idempotencja**. Drugie uruchomienie nie robi nic, jeśli nic się nie zmieniło.

## Szybki start

Skrypty nie mają zaszytych ścieżek. `bootstrap.sh` działa na **bieżącym
katalogu** (albo na `--root <katalog>`), a `make_project.sh` tworzy projekt
w bieżącym katalogu (albo w `--into <katalog>`).

### Istniejący projekt

```bash
AREK="/sciezka/do/arek-bootstrap"   # ustaw raz, gdziekolwiek leży repo
cd /sciezka/do/projektu
"$AREK/bootstrap.sh"
```

albo, jeśli bootstrap jest już skopiowany do projektu:

```bash
./bootstrap.sh
```

### Nowy projekt

```bash
AREK="/sciezka/do/arek-bootstrap"
cd /sciezka/do/katalogu
"$AREK/make_project.sh" moja_nauka python
cd moja_nauka
./bootstrap.sh
```

### Z dowolnego miejsca (symlink w PATH)

Zamiast wpisywać pełną ścieżkę za każdym razem:

```bash
mkdir -p ~/.local/bin
ln -sf "$PWD/bootstrap.sh"     ~/.local/bin/arek-bootstrap
ln -sf "$PWD/make_project.sh"  ~/.local/bin/arek-make-project

# ~/.local/bin musi być w PATH
```

Potem:

```bash
cd /dowolny/projekt && arek-bootstrap
cd /dowolny/katalog  && arek-make-project nowy-projekt python
```

`make_project.sh` rozwiązuje symlink, więc nadal znajdzie `bootstrap.sh`
w repo arek-bootstrap.

Generator tworzy szkielet, bootstrap, README, `.gitignore`, `.editorconfig`,
`.env.example`, licencję MIT i opcjonalnie pliki Dockera.

## Co wykrywa

| Stack | Sygnały | Co robi |
|---|---|---|
| Python | `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile`, `uv.lock`, `poetry.lock` | `uv sync`, `poetry install`, `pipenv install` albo `.venv` + `pip` (`--require-hashes`, gdy są hashe) |
| Node | `package.json` + lockfile / pole `packageManager` | `npm ci`/`npm install`, `pnpm`, `yarn`, `bun` + audyt i `npm audit signatures` |
| Go | `go.mod` | `go mod download` + `go mod verify` |
| Rust | `Cargo.toml` | `cargo fetch --locked` (gdy jest `Cargo.lock`) |
| PHP | `composer.json` | `composer install` + `composer audit` |
| Ruby | `Gemfile` | `bundle check` / `bundle install` (`frozen` przy lockfile'u) |
| bash | `*.sh`, `main.sh`, `run.sh` | `bash -n` na wszystkich skryptach |
| Docker | `compose.yaml`, `docker-compose.yml` | walidacja `docker compose config`, opcjonalnie `up -d --build` |

Wybór menedżera Python/Node nie jest zgadywany „w ciemno”: najpierw liczy się
lockfile lub pole `packageManager`, dopiero potem domyślny menedżer.

## Inteligentniejsze wykrywanie

### Katalog główny ma pierwszeństwo

Jeśli w katalogu głównym jest manifest kodu (`package.json`, `pyproject.toml`,
`go.mod`…), bootstrap traktuje go jako projekt i **nie** schodzi do podkatalogów.
To chroni przed przypadkowym instalowaniem zależności w `examples/` albo
`vendor/`.

```bash
./bootstrap.sh --list      # co zostało wykryte?
./bootstrap.sh --all       # świadomie przetwórz także podkatalogi
```

### Monorepo

Gdy katalog główny nie ma manifestu kodu (albo ma tylko `compose.yaml` lub
skrypty), bootstrap sam schodzi do podkatalogów:

```text
repo/
├── apps/api/package.json      -> node
├── apps/web/package.json      -> node
├── scripts/deploy.sh          -> bash
└── compose.yaml               -> docker
```

```bash
./bootstrap.sh                 # wykryje apps/api, apps/web, scripts, docker
./bootstrap.sh --list          # tylko pokaż plan
./bootstrap.sh --depth 2       # ogranicz głębokość skanowania
```

Skanowanie domyślnie sięga 3 poziomów i pomija `.git`, `node_modules`, `.venv`,
`vendor`, `target`, `dist`, `build` itd.

### Idempotencja i stemple

Po udanym stacku bootstrap zapisuje w `.arek-bootstrap/state/` hash swoich
manifestów i wersji. Kolejne uruchomienie:

- **pomija** stack, jeśli manifesty się nie zmieniły i artefakt istnieje
  (`.venv`, `node_modules`, `vendor`),
- **wykonuje ponownie**, jeśli zmienił się `package.json`, lockfile,
  `requirements.txt`, skrypt bash albo sam bootstrap,
- **nie nadpisuje** istniejącego `.env`.

`.arek-bootstrap/` jest lokalnym stanem — dodaj go do `.gitignore`.
Generator robi to automatycznie.

## Opcje bootstrapu

```text
--check, --check-only  raport: projekty, narzędzia, stan stempli (bez zmian)
--list                 wypisz wykryte projekty i wyjdź
--lang <stack>         wymuś stack dla katalogu głównego
--root <katalog>       wskaż katalog projektu (domyślnie: bieżący)
--all                  przetwórz także projekty w podkatalogach
--depth <n>            maksymalna głębokość skanowania (domyślnie 3)
--dry-run, -n          pokaż polecenia, ale nic nie zmieniaj
--force, -f            ignoruj stemple i wykonaj instalację od nowa
--no-audit             pomiń audyt podatności i weryfikację podpisów
--no-scripts           wyłącz lifecycle scripts npm/pnpm/yarn/bun i Composera
--refresh-threats      odśwież bazę zagrożeń (osv-scanner) i przeskanuj projekt
--docker-up            po walidacji uruchom docker compose up -d --build
--quiet, -q            tylko ostrzeżenia i błędy
--verbose, -v          dodatkowa diagnostyka
--no-color             bez kolorów
-h, --help             pomoc
--version              wersja
```

Przykłady:

```bash
./bootstrap.sh --check-only            # co by się stało?
./bootstrap.sh --dry-run               # pokaż komendy
./bootstrap.sh --force                 # przebuduj środowisko od zera
./bootstrap.sh --lang python --root .  # wymuś Python w tym katalogu
```

## Generator projektów

```bash
./make_project.sh <nazwa> [python|node|go|rust|php|ruby|bash|auto]
```

Domyślnie tworzy projekt w bieżącym katalogu, inicjuje git (`main`) i dodaje
licencję MIT. Opcje:

```text
--lang <typ>        to samo co argument [typ]
--into <katalog>    gdzie utworzyć projekt (domyślnie: bieżący katalog)
--license mit|none  licencja (domyślnie: mit)
--with-docker       Dockerfile + compose.yaml + .dockerignore
--no-git            bez git init
--git               wymuś git init
```

Przykłady:

```bash
./make_project.sh api node --with-docker
./make_project.sh narzedzie python --license none
./make_project.sh skrypt bash --no-git
```

Nazwa może zawierać litery, cyfry, `.`, `_` i `-`. Ścieżki, spacje i wiodące
`.`/`_` są odrzucane. Generator nie nadpisuje istniejących katalogów.

## Wymagania

- **Linux** + bash 4+ (skrypt używa m.in. GNU `find -maxdepth`)
- `python3`, `node`/`npm`, `go`, `cargo`, `composer`, `bundle`, `docker` —
  tylko te, które są potrzebne dla wykrytego stacku
- `git` opcjonalnie (dla generatora)
- `sha256sum` albo `shasum`; w ostateczności `cksum`

## Bezpieczeństwo łańcucha dostaw

Skrypt nie jest sandboxem, ale nie dokłada się do typowych błędów, które
wykorzystują ataki na pakiety (Shai-Hulud, Miasma, Team PCP i podobne):

- lockfile ma pierwszeństwo (`npm ci`, `--frozen-lockfile`, `uv sync --frozen`,
  `cargo fetch --locked`, `bundle ... frozen`), a jego brak jest ostrzeżeniem;
- `npm audit signatures` weryfikuje podpisy rejestru, `composer audit` —
  znane podatności;
- `requirements.txt` z `--hash=` wymusza `--require-hashes`;
- `--no-scripts` wyłącza lifecycle scripts npm/pnpm/yarn/bun i Composera —
  warto go użyć przy pierwszej instalacji nieznanej zależności;
- `--check-only` ostrzega o obrazach Dockera bez `@sha256:` (tag można
  podmienić) i o brakach lockfile'ów;
- obrazy w szablonach `make_project.sh` są przypięte do digestu (`@sha256:…`),
  więc `docker build` jest powtarzalny.
- skrypt nigdy nie robi `curl | bash` ani nie nadpisuje `.env`;
- akcje w CI są przypięte do pełnego SHA, a Dependabot pilnuje aktualizacji.

Szczegóły i procedura reagowania na kompromitację: [SECURITY.md](SECURITY.md).

## Narzędzia audytu (opcjonalne, ale zalecane)

`arek-bootstrap` wykrywa i uruchamia je, jeśli są zainstalowane; przy braku
daje ostrzeżenie i instrukcję instalacji:

```bash
# uniwersalny skaner (wszystkie ekosystemy)
# https://google.github.io/osv-scanner/installation/
# Python
python -m pip install --user pip-audit
# Rust
cargo install cargo-audit
# Go
go install golang.org/x/vuln/cmd/govulncheck@latest
# Ruby
gem install bundler-audit
```

Odświeżenie lokalnej bazy zagrożeń i skan projektu:

```bash
./bootstrap.sh --refresh-threats
```

## Rozwój

```bash
bash -n bootstrap.sh make_project.sh tests/run.sh
shellcheck bootstrap.sh make_project.sh tests/run.sh
bash tests/run.sh
```

Testy działają bez sieci: nie wykonują `pip install` ani `npm install`.
Sprawdzają wykrywanie, monorepo, idempotencję, `--dry-run`, `--root`,
generator i walidację argumentów.

CI (GitHub Actions) uruchamia składnię, przypięty ShellCheck (z weryfikacją
SHA256) i testy na Ubuntu. Tag `v*` uruchamia dodatkowo workflow release,
który publikuje skrypty i plik `SHA256SUMS`.

## Zasady

1. **Jedno polecenie** — bez łańcucha magicznych kroków.
2. **Idempotencja** — powtórne uruchomienie nie psuje i nie powtarza pracy.
3. **Jawne decyzje** — `--check-only`, `--list` i `--dry-run` zanim coś się stanie.
4. **Minimum niespodzianek** — `.env` nie jest nadpisywany, nieznane opcje
   kończą się błędem, brak narzędzia daje czytelny komunikat.
5. **Bezpieczeństwo** — `.env` poza git, lockfile zamiast ruchomych wersji,
   audyt i weryfikacja podpisów domyślnie włączone, `--no-scripts` do
   instalacji nieznanych zależności.

## Autor

**Arek** — pseudonim **h5n1** (z czasów IRC, ~2001). Samouk: od mIRC i
skryptów-pomysłów po pełne automatyzacje pisane z pomocą AI. Ta narzędziownia
wyrosła z frustracji setkami projektów z GitHuba, które „nie umiały się
ustawić”. Niech kolejni (i przyszły Ty) nie muszą tego przechodzić.

## Licencja

MIT — rób co chcesz, może ktoś (albo przyszły Ty) uniknie problemów, które
sam miałeś.
