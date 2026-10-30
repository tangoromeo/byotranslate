#!/usr/bin/env python3
"""Проверка длин полей карточки App Store по docs/appstore/listing.md."""
import re, sys
from pathlib import Path
text = Path(__file__).with_name("listing.md").read_text(encoding="utf-8")
LIMITS = {"Name": 30, "Название": 30, "Subtitle": 30, "Подзаголовок": 30,
          "Keywords": 100, "Ключевые слова": 100, "Promotional text": 170, "Промо-текст": 170,
          "Description": 4000, "Описание": 4000}
ok = True
for field, limit in LIMITS.items():
    for m in re.finditer(r"\*\*" + re.escape(field) + r":\*\*[ \n]?(.*?)(?=\n\*\*|\n## |\Z)", text, re.S):
        value = m.group(1).strip()
        n = len(value)
        flag = "OK " if n <= limit else "ДЛИННО"
        ok &= n <= limit
        print(f"{flag} {field:16} {n:5}/{limit}")
sys.exit(0 if ok else 1)
