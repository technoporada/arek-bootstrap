# arek-bootstrap

**„Każdy projekt stawia się sam.” / "Every project should set itself up."**

Jeden skrypt, który rozpoznaje stack, stawia środowisko, wykrywa braki i robi podstawowy audyt higieny repo.  
One script that detects the stack, bootstraps the environment, spots missing pieces, and runs a basic repo hygiene audit.

---

## 🇵🇱 Polski

### Co to robi

- **Bootstrap środowiska**: wykrywa Python/Node/Go/Rust/PHP/Ruby/bash/Docker, wybiera menedżer pakietów, instaluje zależności.
- **Wykrywanie po kodzie**: gdy brakuje manifestu (`requirements.txt`, `package.json` itd.), próbuje wykryć stack po plikach (`.py`, `.js`, `.go`...).
- **Inferencja zależności Pythona**: jeśli jest `app.py`, ale brak manifestu, generuje `requirements.inferred.txt` na podstawie importów i próbuje zainstalować.
- **Doctor**: `doctor.py`/`--doctor` sprawdza sekrety, zapomniane configi (`.env`, `.vscode`, `.codex`, `.opencode`...), podejrzane markery i braki w `.gitignore`.
- **Idempotencja**: stemple w `.arek-bootstrap/state/` pomijają pracę, gdy nic się nie zmieniło.

### Szybki start

```bash
# w katalogu projektu
./bootstrap.sh

# raport bez zmian
./bootstrap.sh --check-only

# audyt higieny/bezpieczeństwa
./bootstrap.sh --doctor
# albo
python3 doctor.py .
```

Nowy projekt:

```bash
./make_project.sh moja_nauka python
cd moja_nauka
./bootstrap.sh
```

### Ważne opcje

```text
--check, --check-only  raport: projekty, narzędzia, stemple
--doctor               audyt higieny/bezpieczeństwa repo (doctor.py)
--list                 wypisz wykryte projekty
--all                  przetwórz też podkatalogi (monorepo)
--dry-run, -n          pokaż polecenia, bez zmian
--force, -f            ignoruj stemple
--no-audit             pomiń audyt podatności
--no-scripts           wyłącz lifecycle scripts npm/composer
--install              instaluj brakujące narzędzia (jawnie!)
--refresh-threats      odśwież bazę zagrożeń (osv-scanner)
--docker-up            docker compose up -d --build po walidacji
```

### Doctor – co sprawdza

| Obszar | Przykłady | Zachowanie |
|---|---|---|
| Sekrety | klucze prywatne, tokeny GitHub/OpenAI/AWS/JWT, `SECRET=...` | `FAIL`, próbka zamaskowana |
| Zapomniane configi | `.env`, `.codex`, `.opencode`, `.claude`, `.vscode`, `.idea` | `WARN/FAIL` zależnie od typu |
| Gitignore | brak `.gitignore`, brak typowych wpisów | `WARN` |
| Podejrzane markery | prompt-injection, ukryte znaki Unicode | `WARN` |

Doctor to skaner sygnałów, nie dowód bezpieczeństwa.

### Bezpieczeństwo

- Nie nadpisuje `.env`.
- Preferuje lockfile (`npm ci`, `--frozen-lockfile`, `uv sync --frozen`, `cargo fetch --locked`).
- `--no-scripts` wyłącza lifecycle scripts przy instalacji zależności.
- `--install` może instalować brakujące narzędzia; instalatory user-level (uv/nvm/rustup) są uruchamiane **tylko na jawne żądanie**. Traktuj to jako świadomy krok, nie domyślny automat.
- `doctor.py` nie wypisuje pełnych sekretów w raporcie.

### Testy

```bash
bash -n bootstrap.sh make_project.sh tests/run.sh
bash tests/run.sh
```

---

## 🇬🇧 English

### What it does

- **Environment bootstrap**: detects Python/Node/Go/Rust/PHP/Ruby/bash/Docker, picks a package manager, installs dependencies.
- **Code-file detection**: when manifests are missing (`requirements.txt`, `package.json`, etc.), it tries to detect the stack from source files (`.py`, `.js`, `.go`...).
- **Python dependency inference**: if there's `app.py` but no manifest, it generates `requirements.inferred.txt` from imports and tries to install them.
- **Doctor**: `doctor.py`/`--doctor` checks for secrets, forgotten configs (`.env`, `.vscode`, `.codex`, `.opencode`...), suspicious markers, and missing `.gitignore` entries.
- **Idempotency**: stamps in `.arek-bootstrap/state/` skip work when nothing changed.

### Quick start

```bash
# inside a project
./bootstrap.sh

# report only, no changes
./bootstrap.sh --check-only

# hygiene/security audit
./bootstrap.sh --doctor
# or
python3 doctor.py .
```

New project:

```bash
./make_project.sh my_project python
cd my_project
./bootstrap.sh
```

### Key options

```text
--check, --check-only  report: projects, tools, stamps
--doctor               repo hygiene/security audit (doctor.py)
--list                 list detected projects
--all                  process subdirectories too (monorepo)
--dry-run, -n          show commands, no changes
--force, -f            ignore stamps
--no-audit             skip vulnerability audit
--no-scripts           disable npm/composer lifecycle scripts
--install              install missing tools (explicit!)
--refresh-threats      refresh threat DB (osv-scanner)
--docker-up            docker compose up -d --build after validation
```

### Doctor – what it checks

| Area | Examples | Behavior |
|---|---|---|
| Secrets | private keys, GitHub/OpenAI/AWS/JWT tokens, `SECRET=...` | `FAIL`, masked sample |
| Forgotten configs | `.env`, `.codex`, `.opencode`, `.claude`, `.vscode`, `.idea` | `WARN/FAIL` depending on type |
| Gitignore | missing `.gitignore`, missing common entries | `WARN` |
| Suspicious markers | prompt-injection, hidden Unicode chars | `WARN` |

Doctor is a signal scanner, not proof of security.

### Security

- Does not overwrite `.env`.
- Prefers lockfiles (`npm ci`, `--frozen-lockfile`, `uv sync --frozen`, `cargo fetch --locked`).
- `--no-scripts` disables dependency lifecycle scripts.
- `--install` may install missing tools; user-level installers (uv/nvm/rustup) run **only on explicit request**. Treat it as a conscious step, not a silent default.
- `doctor.py` never prints full secrets in reports.

### Tests

```bash
bash -n bootstrap.sh make_project.sh tests/run.sh
bash tests/run.sh
```

---

## Autor / Author

**Arek** — pseudonim **h5n1** (IRC, ~2001). Samouk: od mIRC i skryptów do automatyzacji z pomocą AI.  
Self-taught: from mIRC/scripts to AI-assisted automation.

## Licencja / License

MIT.