#!/usr/bin/env python3
"""Extract EN/TR locale maps from localization_service.dart."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
src = ROOT / "lib/services/localization_service.dart"
content = src.read_text(encoding="utf-8")

m_en = re.search(r"'en': \{(.+?)\},\s*'tr':", content, re.DOTALL)
m_tr = re.search(r"'tr': \{(.+?)\},\s*\};", content, re.DOTALL)
if not m_en or not m_tr:
    raise SystemExit("parse failed")

out_dir = ROOT / "lib/l10n"
out_dir.mkdir(parents=True, exist_ok=True)

for lang, body in [("en", m_en.group(1).strip()), ("tr", m_tr.group(1).strip())]:
    var = f"k{lang.capitalize()}Strings"
    out = (
        f"/// {lang.upper()} locale strings for Cinema+.\n"
        f"const Map<String, String> {var} = {{\n"
        f"{body}\n"
        f"}};\n"
    )
    (out_dir / f"{lang}.dart").write_text(out, encoding="utf-8")
    print(f"wrote {lang}.dart ({body.count(chr(10))} lines)")
