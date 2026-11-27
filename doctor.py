#!/usr/bin/env python3
"""arek-bootstrap doctor: szybki audyt higieny i bezpieczeństwa repo.

Bez zależności zewnętrznych. Nie modyfikuje repo. Nie wypisuje pełnych sekretów.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path

VERSION = "0.1.0"

SKIP_DIRS = {
    ".git", ".venv", "venv", "node_modules", "__pycache__", ".mypy_cache",
    ".pytest_cache", ".ruff_cache", ".tox", "dist", "build", ".arek-bootstrap",
}
TEXT_EXT = {
    ".py", ".sh", ".bash", ".zsh", ".js", ".ts", ".tsx", ".jsx", ".json", ".yml",
    ".yaml", ".toml", ".ini", ".cfg", ".conf", ".env", ".md", ".txt", ".html",
    ".css", ".xml", ".sql", ".go", ".rs", ".php", ".rb", ".java", ".c", ".h",
    ".cpp", ".hpp", ".cs", ".ps1", ".dockerfile", "", ".example", ".sample",
}

SECRET_RULES = [
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("github-pat", re.compile(r"\bghp_[A-Za-z0-9]{20,}\b")),
    ("github-fine-grained", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("openai-key", re.compile(r"\bsk-[A-Za-z0-9]{20,}\b")),
    ("aws-access-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    ("generic-secret-assignment", re.compile(r"(?i)\b(api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*['\"]?([A-Za-z0-9_\-./+=]{12,})")),
]

FORGOT_CONFIGS = [
    (".env", "FAIL", "Plik środowiskowy może zawierać sekrety"),
    (".env.local", "FAIL", "Lokalny plik środowiskowy może zawierać sekrety"),
    ("config.ini", "WARN", "Lokalny config może zawierać ścieżki/sekrety"),
    (".vscode", "WARN", "Konfig IDE; czasem celowy, ale często lokalny"),
    (".idea", "WARN", "Konfig IDE; zwykle lokalny"),
    (".codex", "WARN", "Konfig agenta; może zawierać lokalne ustawienia/ścieżki"),
    (".opencode", "WARN", "Konfig agenta/narzędzia; sprawdź, czy celowo w repo"),
    (".claude", "WARN", "Konfig agenta; może zawierać lokalne ustawienia"),
    (".cursor", "WARN", "Konfig narzędzia AI/IDE"),
    (".aider", "WARN", "Konfig narzędzia AI"),
    (".continue", "WARN", "Konfig narzędzia AI"),
    (".idx", "WARN", "Konfig środowiska IDX/Firebase Studio; zwykle lokalny/projektowy"),
]

INJECTION_RULES = [
    ("prompt-injection", re.compile(r"(?i)\b(ignore (all|previous|above) instructions|system prompt|developer message|you are chatgpt|act as)\b")),
    ("hidden-unicode", re.compile(r"[\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]")),
]


@dataclass
class Finding:
    severity: str
    kind: str
    path: str
    line: int | None
    message: str
    sample: str | None = None
    rule: str | None = None


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=str(cwd), text=True, capture_output=True)


def git_files(root: Path) -> tuple[list[Path], bool]:
    p = run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], root)
    if p.returncode != 0:
        return [], False
    items = [x for x in p.stdout.split("\0") if x]
    return [root / x for x in items], True


def walk_files(root: Path) -> list[Path]:
    out = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            out.append(Path(dp) / fn)
    return out


def is_text_file(path: Path) -> bool:
    if path.suffix.lower() in TEXT_EXT:
        return True
    try:
        with path.open("rb") as f:
            chunk = f.read(4096)
        return b"\x00" not in chunk
    except Exception:
        return False


PLACEHOLDER_VALUES = {
    "changeme", "change_me", "example", "from_example", "moja_wartosc",
    "your_password", "your_secret", "your_token", "password", "secret",
    "token", "dummy", "test", "sample", "placeholder", "xxx", "yyyy",
}


def is_placeholder(value: str) -> bool:
    v = value.strip().strip("'\"").lower()
    return v in PLACEHOLDER_VALUES or v.startswith("<") and v.endswith(">")


def redact(value: str) -> str:
    v = value.strip()
    if len(v) <= 12:
        return "*" * len(v)
    return f"{v[:4]}…{v[-4:]}"


def rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except Exception:
        return str(path)


def scan_secrets(path: Path, root: Path) -> list[Finding]:
    findings = []
    if not is_text_file(path):
        return findings
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return findings
    for i, line in enumerate(lines, 1):
        for name, rx in SECRET_RULES:
            m = rx.search(line)
            if not m:
                continue
            sample_src = m.group(0)
            if name == "generic-secret-assignment" and m.lastindex and m.lastindex >= 2:
                sample_src = m.group(2)
                if is_placeholder(sample_src):
                    continue
                # Pomiń typowe odwołania do zmiennych/pól w kodzie, np. token: s.accessToken
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*", sample_src):
                    after = line[m.end(2):m.end(2) + 1]
                    before = line[m.start(2) - 1:m.start(2)] if m.start(2) > 0 else ""
                    if before not in "'\"" and after not in "'\"":
                        # Kropkowany identyfikator lub identyfikator użyty jako wyrażenie
                        if "." in sample_src or after in ".([?,;):]}":
                            continue
            findings.append(Finding(
                severity="FAIL",
                kind="secret",
                path=rel(path, root),
                line=i,
                message=f"Wykryto możliwy sekret: {name}",
                sample=redact(sample_src),
                rule=name,
            ))
            break
    return findings


def scan_injection(path: Path, root: Path) -> list[Finding]:
    findings = []
    if not is_text_file(path):
        return findings
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return findings
    lines = text.splitlines()
    for name, rx in INJECTION_RULES:
        m = rx.search(text)
        if not m:
            continue
        line = text[:m.start()].count("\n") + 1
        line_text = lines[line - 1] if 0 < line <= len(lines) else ""
        if "re.compile(" in line_text or "INJECTION_RULES" in line_text or "SECRET_RULES" in line_text:
            continue
        findings.append(Finding(
            severity="WARN",
            kind="untrusted",
            path=rel(path, root),
            line=line,
            message=f"Wykryto podejrzany marker: {name}",
            sample=redact(m.group(0)),
            rule=name,
        ))
    return findings


def scan_forgotten_configs(root: Path) -> list[Finding]:
    findings = []
    for name, severity, msg in FORGOT_CONFIGS:
        p = root / name
        if p.exists():
            findings.append(Finding(
                severity=severity,
                kind="config",
                path=name,
                line=None,
                message=msg,
                rule=f"config:{name}",
            ))
    return findings


def scan_gitignore(root: Path) -> list[Finding]:
    findings = []
    gi = root / ".gitignore"
    if not gi.exists():
        findings.append(Finding(
            severity="WARN", kind="gitignore", path=".gitignore", line=None,
            message="Brak .gitignore – łatwo przypadkiem commitnąć pliki lokalne",
            rule="gitignore:missing",
        ))
        return findings
    text = gi.read_text(encoding="utf-8", errors="ignore")
    needed = [".env", "*.key", ".venv/", "__pycache__/", ".DS_Store"]
    for pat in needed:
        if pat not in text:
            findings.append(Finding(
                severity="WARN", kind="gitignore", path=".gitignore", line=None,
                message=f".gitignore nie zawiera typowego wpisu: {pat}",
                rule=f"gitignore:{pat}",
            ))
    return findings


def should_scan_file(path: Path, root: Path) -> bool:
    try:
        relp = path.resolve().relative_to(root.resolve())
    except Exception:
        return False
    if any(part in SKIP_DIRS for part in relp.parts):
        return False
    if path.is_dir():
        return False
    try:
        if path.stat().st_size > 1_000_000:
            return False
    except Exception:
        return False
    return True


def collect_findings(root: Path) -> list[Finding]:
    files, is_git = git_files(root)
    if not is_git:
        files = walk_files(root)
    findings = []
    findings.extend(scan_forgotten_configs(root))
    findings.extend(scan_gitignore(root))
    seen = set()
    for p in files:
        if not should_scan_file(p, root):
            continue
        rp = str(p.resolve())
        if rp in seen:
            continue
        seen.add(rp)
        findings.extend(scan_secrets(p, root))
        findings.extend(scan_injection(p, root))
    # dedupe
    uniq = []
    seenf = set()
    for f in findings:
        key = (f.severity, f.kind, f.path, f.line, f.rule, f.message)
        if key in seenf:
            continue
        seenf.add(key)
        uniq.append(f)
    return uniq


def summarize(findings: list[Finding]) -> dict:
    sev = {"FAIL": 0, "WARN": 0, "INFO": 0}
    for f in findings:
        sev[f.severity] = sev.get(f.severity, 0) + 1
    return {"fail": sev["FAIL"], "warn": sev["WARN"], "info": sev["INFO"], "total": len(findings)}


def print_text(findings: list[Finding], root: Path) -> int:
    s = summarize(findings)
    print(f"arek-bootstrap doctor {VERSION}")
    print(f"Root: {root}")
    print(f"Wynik: FAIL={s['fail']} WARN={s['warn']} INFO={s['info']}")
    print()
    if not findings:
        print("[OK] Nie znaleziono oczywistych problemów w podstawowym skanie.")
        return 0
    for f in findings:
        loc = f"{f.path}:{f.line}" if f.line else f.path
        sample = f" sample={f.sample}" if f.sample else ""
        print(f"[{f.severity}] {f.kind} {loc} - {f.message}{sample}")
    print()
    print("Uwaga: to skaner sygnałów, nie dowód bezpieczeństwa.")
    return 1 if s["fail"] else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="arek-bootstrap doctor")
    ap.add_argument("path", nargs="?", default=".", help="katalog repo/projektu")
    ap.add_argument("--json", action="store_true", help="wynik jako JSON")
    ap.add_argument("--version", action="version", version=VERSION)
    args = ap.parse_args()
    root = Path(args.path).resolve()
    if not root.exists():
        print(f"Brak ścieżki: {root}", file=sys.stderr)
        return 2
    findings = collect_findings(root)
    if args.json:
        payload = {"version": VERSION, "root": str(root), "summary": summarize(findings), "findings": [asdict(f) for f in findings]}
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 1 if summarize(findings)["fail"] else 0
    return print_text(findings, root)


if __name__ == "__main__":
    raise SystemExit(main())
