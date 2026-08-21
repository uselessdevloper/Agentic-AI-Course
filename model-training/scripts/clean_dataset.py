"""
Dataset Cleaner for train.jsonl
================================
Fixes identified issues:
  1. Template/Hugo tags in questions  → DROP those rows
  2. Template/Hugo tags in answers    → CLEAN (strip/replace the tags)
  3. MkDocs ::: auto-doc answers      → DROP (useless content)
  4. TODO placeholder answers         → DROP
  5. Very short answers (<50 chars)   → DROP
  6. Version-number-only questions    → DROP
  7. Answers starting with raw date   → CLEAN (strip leading date line)
  8. Markdown image links in answers  → CLEAN (remove image lines)
  9. YAML front-matter in answers     → CLEAN (strip front-matter block)
 10. Duplicate rows                   → DROP
"""

import json
import re
import sys
from pathlib import Path
from collections import defaultdict

# ── Patterns ────────────────────────────────────────────────────────────────
TEMPLATE_TAG   = re.compile(r'\{\{%.*?%\}\}|\{\{<.*?>\}\}|\{\{\..*?\}\}|\{\{.*?\}\}')
FRONT_MATTER   = re.compile(r'^---\n.*?\n---\n', re.DOTALL)
MD_IMAGE       = re.compile(r'!\[.*?\]\([^)]*\)\n?')
LEADING_DATE   = re.compile(r'^\d{4}-\d{2}-\d{2}\s*\n+')
VERSION_Q      = re.compile(r'^(Explain the key concepts covered in:|What is )\s*[\d\.\-\_]+\??\s*$', re.IGNORECASE)
MKDOCS_START   = re.compile(r'^:::')
BLANK_OR_TODO  = re.compile(r'^\s*(TODO|FIXME|WIP)?\s*$', re.IGNORECASE)


def has_template_tags(text: str) -> bool:
    return bool(TEMPLATE_TAG.search(text))


def clean_answer(text: str) -> str:
    """Apply all answer-level cleaning transforms."""
    # 1. Strip YAML front-matter
    text = FRONT_MATTER.sub('', text)
    # 2. Strip leading release date line (e.g. "2017-11-20\n\n")
    text = LEADING_DATE.sub('', text)
    # 3. Remove inline markdown images (broken relative paths)
    text = MD_IMAGE.sub('', text)
    # 4. Clean leftover template tags from answers (replace with empty)
    text = TEMPLATE_TAG.sub('', text)
    # 5. Collapse 3+ blank lines to 2
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def is_bad_row(user: str, asst: str) -> tuple:
    """Return (should_drop, reason)."""
    # Question contains template tags -> meaningless Q
    if has_template_tags(user):
        return True, "template_tag_in_question"

    # Version number as question
    if VERSION_Q.match(user.strip()):
        return True, "version_number_question"

    # Answer is MkDocs auto-doc stub
    if MKDOCS_START.match(asst.strip()):
        return True, "mkdocs_autodoc_stub"

    # TODO / placeholder answer
    if BLANK_OR_TODO.match(asst.strip()) or (len(asst.strip()) < 20 and "TODO" in asst):
        return True, "todo_placeholder"

    # Empty question or answer
    if not user.strip() or not asst.strip():
        return True, "empty_field"

    return False, ""


def is_short_after_clean(asst: str) -> bool:
    return len(asst.strip()) < 50


# ── Main ────────────────────────────────────────────────────────────────────
def clean_dataset(input_path: str, output_path: str):
    input_path  = Path(input_path)
    output_path = Path(output_path)

    stats = defaultdict(int)
    seen  = set()   # for dedup
    kept  = 0
    i     = 0

    with open(input_path)  as fin, \
         open(output_path, "w") as fout:

        for i, raw in enumerate(fin):
            raw = raw.strip()
            if not raw:
                continue

            # Parse
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                stats["invalid_json"] += 1
                continue

            msgs = obj.get("messages", [])
            user = next((m["content"] for m in msgs if m["role"] == "user"),  "")
            asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")

            # Drop checks
            drop, reason = is_bad_row(user, asst)
            if drop:
                stats[f"dropped_{reason}"] += 1
                continue

            # Clean answer
            cleaned_asst = clean_answer(asst)

            # Drop if still too short after cleaning
            if is_short_after_clean(cleaned_asst):
                stats["dropped_too_short_after_clean"] += 1
                continue

            # Dedup
            key = (user.strip()[:200], cleaned_asst.strip()[:200])
            if key in seen:
                stats["dropped_duplicate"] += 1
                continue
            seen.add(key)

            # Rebuild and write
            for m in msgs:
                if m["role"] == "assistant":
                    m["content"] = cleaned_asst

            fout.write(json.dumps(obj, ensure_ascii=False) + "\n")
            kept += 1

    # Report
    total_in  = i + 1
    total_out = kept
    dropped   = total_in - total_out

    print(f"\n{'='*60}")
    print(f" DATASET CLEANING REPORT")
    print(f"{'='*60}")
    print(f"  Input rows   : {total_in:>7}")
    print(f"  Output rows  : {total_out:>7}  ({total_out/total_in*100:.1f}% kept)")
    print(f"  Total dropped: {dropped:>7}  ({dropped/total_in*100:.1f}%)")
    print(f"\n  Drop reasons:")
    for k, v in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"    {k:<40} {v:>5}")
    print(f"{'='*60}\n")
    print(f"  Clean dataset saved to: {output_path}")


if __name__ == "__main__":
    BASE = Path(__file__).parent.parent / "data" / "datasets"

    input_file  = BASE / "train.jsonl"
    output_file = BASE / "train_clean.jsonl"

    print(f"Input  : {input_file}")
    print(f"Output : {output_file}")
    clean_dataset(str(input_file), str(output_file))
