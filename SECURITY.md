# Bezpieczeństwo

## Zgłaszanie problemów

Jeśli znajdziesz podatność w `bootstrap.sh` albo `make_project.sh`, otwórz
prywatny security advisory w repozytorium GitHub (Security → Advisories) albo
napisz bezpośrednio do autora. Nie publikuj exploita, zanim poprawka nie
trafi do `main`.

## Co ten projekt robi, żeby nie być „kolejnym ogniwem”

Ataki na łańcuch dostaw (Shai-Hulud, Miasma, Team PCP, LiteLLM i dziesiątki
innych w 2025–2026) wykorzystują trzy rzeczy: **ruchome wersje**, **skrypty
instalacyjne** i **przejęte poświadczenia**. `arek-bootstrap` ogranicza je
po stronie, którą kontroluje:

- **Lockfile zamiast „latest”** — gdy lockfile istnieje, używane są
  `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile`,
  `uv sync --frozen`, `cargo fetch --locked`, `composer install` z
  `composer.lock`, `bundle install` z `frozen=true`.
- **Brak lockfile'a jest głośno sygnalizowany** — instalacja bez lockfile'a
  nie jest powtarzalna i może pobrać inną wersję niż u autora.
- **Weryfikacja podpisów npm** — `npm audit signatures` sprawdza podpisy
  rejestru dla paczek z lockfile'a.
- **Hashowanie requirements** — jeśli `requirements.txt` zawiera `--hash=`,
  pip dostaje `--require-hashes`.
- **Opcja `--no-scripts`** — wyłącza lifecycle scripts npm/pnpm/yarn/bun
  (`--ignore-scripts`) oraz skrypty Composera (`--no-scripts`). Włącz ją przy
  pierwszej instalacji nieznanej zależności.
- **Obrazy Docker** — `--check-only` ostrzega o obrazach bez przypięcia
  digestem (`@sha256:…`); tag, nawet wersjonowany, można podmienić.
- **Zero `curl | bash`** — skrypt nie pobiera i nie uruchamia kodu z sieci.
- **Akcje GitHub przypięte do SHA** — CI nie używa ruchomych tagów, a
  Dependabot pilnuje aktualizacji.
- **`.env` nigdy nie jest nadpisywany** i jest ignorowany przez git.

## Ostatnie incydenty (2025–2026)

Krótka ściągawka — pełne analizy w źródłach:

| Kampania | Kiedy | Skala |
|---|---|---|
| Shai-Hulud #1 | IX 2025 | 500+ pakietów npm |
| Team PCP (Trivy, Checkmarx, telnyx, LiteLLM 1.82.7/1.82.8) | III 2026 | 78 330 sekretów, 2 186 organizacji |
| Miasma (Red Hat → dalej) | VI 2026 | 57 pakietów / 286+ wersji, 647 tys. pobrań/mies. |
| Mini Shai-Hulud (TanStack, Mistral AI, UiPath, OpenSearch) | V 2026 | setki złośliwych wersji |
| Shai-Hulud: keyv/cacheable | VIII 2026 | 400+ pakietów / 1700+ wersji |
| PhantomSub | IX 2026 | 101 pakietów npm |
| LiteLLM 1.107.0 | X 2026 | 7 wheels + obraz Docker |
| Razem | VIII 2025–VIII 2026 | **56 potwierdzonych ataków**, ~1 co 3 dni od III 2026 |

Źródła: [StepSecurity](https://www.stepsecurity.io/blog/state-of-open-source-supply-chain-attacks),
[JFrog](https://research.jfrog.com/post/shai-hulud-is-back-august/),
[NHS CC-4781](https://digital.nhs.uk/cyber-alerts/2026/cc-4781),
[Aikido – LiteLLM 1.107.0](https://www.aikido.dev/blog/litellm-compromised-infostealer-rat).

Zaktualizuj lokalną bazę zagrożeń: `./bootstrap.sh --refresh-threats` (wymaga
`osv-scanner` i/lub `pip-audit`).

## Czego ten projekt nie gwarantuje

- Nie jest sandboxem. `pip install`, `npm ci` i `composer install` nadal
  uruchamiają kod zależności (build backend, postinstall), chyba że użyjesz
  `--no-scripts` — a i to nie chroni przed złośliwym kodem w samym pakiecie.
- Nie wykrywa zero-day w zależnościach. `npm audit`/`composer audit` widzą
  tylko znane podatności, a nie celowo złośliwe wydania.
- Nie chroni przed przejęciem twojego konta npm/PyPI/GitHub. Kluczowe są
  tokeny z minimalnymi uprawnieniami, 2FA i trusted publishing (OIDC).

## Jeśli podejrzewasz kompromitację

1. **Traktuj maszynę/runner jako zainfekowany** — nie „czyść”, tylko odtwórz
   z czystego obrazu.
2. **Unieważnij tokeny**: npm (szczególnie z `bypass_2fa` i prawem zapisu),
   GitHub PAT/OAuth, Actions secrets, AWS/GCP/Azure, SSH, klucze podpisujące.
3. **Sprawdź wszystkie gałęzie**, nie tylko domyślną, pod kątem obcych
   commitów i plików hakerskich (`.vscode/tasks.json`, `.claude/settings.json`,
   `.github/workflows/*`).
4. **Wyczyść cache i `node_modules`/`.venv`**, potem zainstaluj ponownie z
   zaufanego lockfile'a.
5. **Zgłoś** incydent do rejestru (npm/PyPI) i sprawdź OSV:
   <https://osv.dev/list>.

## Szybki audyt lokalny

```bash
./bootstrap.sh --check-only     # lockfile'e, stemple, przypięcie obrazów
./bootstrap.sh --no-scripts     # instalacja bez lifecycle scripts
npm audit signatures            # podpisy paczek npm
sha256sum -c SHA256SUMS        # weryfikacja pobranych skryptów z release
git status --short              # nic nie powinno pojawić się przypadkiem
```

Warto też włączyć w GitHubie: Dependabot alerts, secret scanning, CodeQL
i „Require approval for all outside collaborators”.
