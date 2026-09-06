#!/usr/bin/env python3
"""Reject signing material and recognizable secrets without printing their values."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


CONTENT_RULES = [
    ("private key", re.compile(rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")),
    ("GitHub credential", re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})\b")),
    ("AWS access key", re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("fixed signing team", re.compile(
        rb"(?im)^[ \t]*(?:(?:export|readonly|declare|typeset)"
        rb"(?:[ \t]+-[A-Za-z]+)*[ \t]+(?:--[ \t]+)?)?"
        rb"[\"']?(?:DEVELOPMENT_TEAM|DevelopmentTeam|EXPECTED_TEAM_ID|CI_TEAM_ID)"
        rb"[\"']?[ \t]*[:=][ \t]*[\"']?[A-Z0-9]{10}\b")),
    ("fixed signing team comparison", re.compile(
        rb"(?im)\$\{?(?:DEVELOPMENT_TEAM|DevelopmentTeam|EXPECTED_TEAM_ID|CI_TEAM_ID)\b\}?"
        rb"[\"']?[ \t]+(?:!=|==|=)[ \t]+[\"']?[A-Z0-9]{10}\b")),
    ("fixed signing team comparison", re.compile(
        rb"(?im)\b[A-Z0-9]{10}[\"']?[ \t]+(?:!=|==|=)[ \t]+[\"']?"
        rb"\$\{?(?:DEVELOPMENT_TEAM|DevelopmentTeam|EXPECTED_TEAM_ID|CI_TEAM_ID)\b\}?")),
    ("fixed signing team", re.compile(
        rb"(?i)\b(?:Apple Developer Team|Team ID)\s*[:=]?\s*[`\"']*[A-Z0-9]{10}\b")),
    ("export signing team", re.compile(
        rb"<key>teamID</key>\s*<string>[A-Z0-9]{10}</string>")),
    ("personal signing certificate", re.compile(
        rb"(?:Apple (?:Development|Distribution)|iPhone (?:Developer|Distribution)|Developer ID (?:Application|Installer)):\s+[^\s<]")),
    ("signing certificate fingerprint", re.compile(
        rb"(?im)^\s*[\"']?CODE_SIGN_IDENTITY(?:\[[^\]]+\])*[\"']?\s*[:=]\s*[\"']?[A-F0-9]{40}\b")),
]


def forbidden_path(name: str) -> bool:
    path = Path(name)
    lower = path.name.lower()
    signing_suffixes = (".p8", ".p12", ".pfx", ".key", ".pem", ".cer", ".crt",
                        ".mobileprovision", ".provisionprofile", ".ipa", ".pkg", ".dmg",
                        ".dsym.zip", ".xcuserstate")
    return (lower.endswith(signing_suffixes)
            or lower.endswith(".local.xcconfig")
            or (lower.startswith(".env") and lower != ".env.example")
            or (lower.startswith("exportoptions") and lower.endswith(".plist"))
            or path.parts[0].lower() in {".build", "build", "deriveddata", "dist"}
            or any(part.lower() == "xcuserdata"
                   or part.lower().endswith((".xcarchive", ".xcresult", ".app", ".dsym", ".dsyms"))
                   for part in path.parts))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="inspect exactly the Git index instead of working files")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="Git checkout to inspect")
    args = parser.parse_args()
    root = args.root.resolve()
    command = ["git", "-C", str(root), "ls-files", "--cached", "-z"]
    if not args.staged:
        command += ["--others", "--exclude-standard"]
    names = sorted(set(subprocess.check_output(command).split(b"\0")) - {b""})
    failures = []
    for raw_name in names:
        name = os.fsdecode(raw_name)
        path = root / name
        if not args.staged and not path.exists() and not path.is_symlink():
            continue
        if forbidden_path(name):
            failures.append((name, "private configuration, signing material, or build artifact"))
            continue
        if args.staged:
            content = subprocess.check_output(["git", "-C", str(root), "show", f":{name}"])
        elif path.is_symlink():
            # Inspect the link itself, never follow it outside the checkout.
            content = os.fsencode(os.readlink(path))
        elif path.is_file():
            content = path.read_bytes()
        else:
            continue
        for label, pattern in CONTENT_RULES:
            if pattern.search(content):
                failures.append((name, label))
                break
    for name, reason in failures:
        print(f"error: {name}: {reason}; keep it outside public Git history", file=sys.stderr)
    if failures:
        return 1
    print(f"Public file checks passed ({'Git index' if args.staged else 'working files'}; {len(names)} paths).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
