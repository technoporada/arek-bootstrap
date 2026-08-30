# arek-bootstrap

**"Każdy projekt stawia się sam."**

Filozofia: wchodzisz w projekt, odpalam jeden skrypt i środowisko jest gotowe.
Bez czytania 40 kroków instrukcji, bez rozwiązywania konfliktów wersji, bez
dłubania w venv. Dokładnie to, czego sam brakowało autorowi w setkach
projektów pobieranych z GitHub.

## Co to robi

- **`bootstrap.sh`** — uniwersalny self-setup:
  - wykrywa język projektu (Python / Node / bash)
  - tworzy `.venv` i instaluje zależności (`requirements.txt` / `pyproject.toml`)
  - dla Node: `npm install` + **`npm audit`** (kontrola podatności)
  - tworzy `.env` z `.env.example` (bez ręcznej kopii)
  - tryb `--check-only` → tylko raport środowiska
- **`make_project.sh <nazwa> <python|node|bash>`** — generator nowych projektów:
  - szkielet, bootstrap, README, `.gitignore`, licencja — od razu
  - nowy projekt zaczyna się z gotową automatyzacją, nie z pustką

## Przykład

```bash
# postaw istniejący projekt
cd jakis_projekt
../arek-bootstrap/bootstrap.sh

# stwórz nowy projekt w ~3 sekundy
./make_project.sh moja_nauka python
cd moja_nauka
./bootstrap.sh
```

## Wymagania

- `bash`, `python3`, `node/npm` (opcjonalnie wg języka projektu)

## Zasady stojące za tym

1. **Minimalizm zależności** — mniej paczek = mniej powierzchni ataku.
2. **Aktualizacje** — pip/pip i audit z automatu.
3. **Zero magicznych kroków** — jeden skrypt, jeden wynik.
4. **Bezpieczeństwo** — `.env` nigdy w git, `npm audit` domyślnie.

## Autor

**Arek** — pseudonim **h5n1** (z czasów IRC, ~2001). Samouk: od mIRC
i skryptów-pomysłów po pełne automatyzacje pisane z pomocą AI. Ta narzędziownia
wyrosła z frustracji setkami projektów z GitHub, które "nie umiały się ustawić".
Niech kolejni (i przyszły Ty) nie muszą tego przechodzić.

## Licencja

MIT — rób co chcesz, może ktoś (albo przyszły Ty) uniknie problemów,
które sam miałeś.