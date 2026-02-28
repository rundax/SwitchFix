#!/usr/bin/env python3
"""Merge uk_UA.txt and uk_full.txt into a normalized Ukrainian dictionary."""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from pathlib import Path

ACCENT = "\u0301"
WHITESPACE_RE = re.compile(r"\s")


def normalize_word(raw: str) -> str:
    word = raw.strip().lower().replace("’", "'")
    if not word:
        return ""
    word = unicodedata.normalize("NFC", word.replace(ACCENT, ""))
    return word


def is_cyrillic_char(ch: str) -> bool:
    code = ord(ch)
    return 0x0400 <= code <= 0x052F


def is_valid_word(word: str) -> bool:
    if not word:
        return False
    if WHITESPACE_RE.search(word):
        return False
    if any(ch.isdigit() for ch in word):
        return False
    if any(ord(ch) < 32 for ch in word):
        return False

    # Allow apostrophe-like punctuation used in Ukrainian words.
    allowed_punct = {"'", "-"}
    letters = 0
    for ch in word:
        if ch in allowed_punct:
            continue
        if not is_cyrillic_char(ch):
            return False
        letters += 1

    return letters > 0


def load_words(path: Path, *, filter_phrases: bool) -> tuple[set[str], dict[str, int]]:
    words: set[str] = set()
    stats = {
        "lines_total": 0,
        "empty": 0,
        "phrases": 0,
        "invalid": 0,
        "too_short": 0,
    }

    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            stats["lines_total"] += 1
            normalized = normalize_word(line)
            if not normalized:
                stats["empty"] += 1
                continue

            if filter_phrases and WHITESPACE_RE.search(normalized):
                stats["phrases"] += 1
                continue

            if not is_valid_word(normalized):
                stats["invalid"] += 1
                continue

            if len(normalized) <= 2:
                stats["too_short"] += 1
                continue

            words.add(normalized)

    return words, stats


def write_words(path: Path, words: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for word in sorted(words):
            fh.write(word)
            fh.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uk-ua", type=Path, default=Path("Sources/Dictionary/Resources/uk_UA.txt"))
    parser.add_argument("--uk-full", type=Path, default=Path("Sources/Dictionary/Resources/uk_full.txt"))
    parser.add_argument("--merged-out", type=Path, default=Path("plan/artifacts/uk_UA_merged.txt"))
    parser.add_argument("--custom-out", type=Path, default=Path("plan/artifacts/uk_UA_custom.txt"))
    parser.add_argument("--report-out", type=Path, default=Path("plan/artifacts/uk_UA_merge_report.json"))
    parser.add_argument("--replace-runtime", action="store_true", help="Overwrite uk_UA.txt with merged output")
    args = parser.parse_args()

    uk_ua_words, uk_ua_stats = load_words(args.uk_ua, filter_phrases=False)
    uk_full_words, uk_full_stats = load_words(args.uk_full, filter_phrases=True)

    merged = uk_ua_words | uk_full_words
    only_uk_ua = uk_ua_words - uk_full_words
    only_uk_full = uk_full_words - uk_ua_words
    intersection = uk_ua_words & uk_full_words

    write_words(args.merged_out, merged)
    write_words(args.custom_out, only_uk_ua)

    if args.replace_runtime:
        write_words(args.uk_ua, merged)

    report = {
        "inputs": {
            "uk_ua": str(args.uk_ua),
            "uk_full": str(args.uk_full),
        },
        "stats": {
            "uk_ua": uk_ua_stats,
            "uk_full": uk_full_stats,
            "uk_ua_words": len(uk_ua_words),
            "uk_full_words": len(uk_full_words),
            "merged_words": len(merged),
            "intersection": len(intersection),
            "only_uk_ua": len(only_uk_ua),
            "only_uk_full": len(only_uk_full),
        },
        "outputs": {
            "merged": str(args.merged_out),
            "custom": str(args.custom_out),
            "report": str(args.report_out),
            "replace_runtime": bool(args.replace_runtime),
        },
    }

    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    args.report_out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Merged words: {len(merged):,}")
    print(f"Only uk_UA: {len(only_uk_ua):,}")
    print(f"Only uk_full: {len(only_uk_full):,}")
    print(f"Report: {args.report_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
