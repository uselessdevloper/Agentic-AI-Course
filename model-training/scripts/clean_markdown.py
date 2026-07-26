#!/usr/bin/env python3
"""
clean_markdown.py
Cleans raw Markdown files from data/markdown/ and writes cleaned versions to data/cleaned/.

Cleaning operations:
  - Remove excessive blank lines (>2 consecutive)
  - Strip boilerplate headers/footers (page numbers, copyright lines)
  - Normalize whitespace and Unicode characters
  - Remove HTML tags accidentally included by converters
  - Fix broken markdown heading levels
  - Strip embedded binary artifacts / base64 image data

Usage:
    python scripts/clean_markdown.py
    python scripts/clean_markdown.py --input data/markdown --output data/cleaned
"""

import argparse
import logging
import re
import sys
import unicodedata
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


# ── Patterns ─────────────────────────────────────────────────────────────────

# Matches leftover HTML tags (e.g. <span>, <div>, <br/>)
HTML_TAG_RE = re.compile(r"<[^>]+>", re.IGNORECASE)

# Matches base64-encoded image data URIs
BASE64_IMG_RE = re.compile(
    r"!\[.*?\]\(data:image/[a-zA-Z]+;base64,[A-Za-z0-9+/=\s]+\)", re.DOTALL
)

# Matches lone page-number lines like "— 42 —" or "Page 42"
PAGE_NUMBER_RE = re.compile(r"^\s*(—\s*\d+\s*—|Page\s+\d+)\s*$", re.IGNORECASE | re.MULTILINE)

# Matches copyright/disclaimer boilerplate lines
COPYRIGHT_RE = re.compile(
    r"^.*(copyright|all rights reserved|©|\(c\)|proprietary|confidential).*$",
    re.IGNORECASE | re.MULTILINE,
)

# Matches runs of 3+ consecutive blank lines → collapse to 2
EXCESS_BLANK_LINES_RE = re.compile(r"\n{3,}")

# Matches heading lines that have no space after # characters (broken heading)
BROKEN_HEADING_RE = re.compile(r"^(#{1,6})([^#\s])", re.MULTILINE)

# Matches non-breaking spaces and other whitespace Unicode variants
NBSP_RE = re.compile(r"[\u00a0\u2009\u200a\u202f\u2007\u2002\u2003\u2004\u2005\u2006]")


def clean_text(text: str) -> str:
    """Apply all cleaning transformations to raw markdown text."""

    # 1. Strip base64 embedded images (massive, useless for text training)
    text = BASE64_IMG_RE.sub("", text)

    # 2. Remove leftover HTML tags
    text = HTML_TAG_RE.sub("", text)

    # 3. Normalize Unicode: decompose, then re-encode to ASCII-compatible NFC
    text = unicodedata.normalize("NFC", text)

    # 4. Replace non-breaking spaces and whitespace variants
    text = NBSP_RE.sub(" ", text)

    # 5. Remove page-number lines
    text = PAGE_NUMBER_RE.sub("", text)

    # 6. Remove copyright/disclaimer boilerplate lines
    text = COPYRIGHT_RE.sub("", text)

    # 7. Fix broken headings: "##Introduction" → "## Introduction"
    text = BROKEN_HEADING_RE.sub(r"\1 \2", text)

    # 8. Collapse 3+ consecutive blank lines into exactly 2
    text = EXCESS_BLANK_LINES_RE.sub("\n\n", text)

    # 9. Strip leading/trailing whitespace per line
    lines = [line.rstrip() for line in text.splitlines()]
    text = "\n".join(lines)

    # 10. Final strip
    text = text.strip() + "\n"

    return text


def clean_file(input_path: Path, output_dir: Path) -> Path:
    """Clean a single Markdown file and write to output directory."""
    raw_text = input_path.read_text(encoding="utf-8", errors="replace")
    cleaned_text = clean_text(raw_text)

    out_path = output_dir / input_path.name
    out_path.write_text(cleaned_text, encoding="utf-8")

    reduction_pct = 100 * (1 - len(cleaned_text) / max(len(raw_text), 1))
    logger.info(
        f"  {input_path.name}: {len(raw_text):,} → {len(cleaned_text):,} chars "
        f"(-{reduction_pct:.1f}%)"
    )
    return out_path


def clean_all(input_dir: Path, output_dir: Path) -> int:
    """Clean all .md files found in input_dir."""
    output_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(input_dir.rglob("*.md"))

    if not files:
        logger.warning(f"No .md files found in: {input_dir}")
        return 0

    logger.info(f"Found {len(files)} markdown file(s) to clean in {input_dir}")
    cleaned = 0

    for file_path in files:
        try:
            clean_file(file_path, output_dir)
            cleaned += 1
        except Exception as e:
            logger.error(f"  [FAILED] {file_path.name}: {e}")

    logger.info(f"\n✅ Cleaned {cleaned}/{len(files)} files → {output_dir}")
    return cleaned


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Clean Markdown files from data/markdown/ → data/cleaned/"
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=Path(__file__).parent.parent / "data" / "markdown",
        help="Input directory with raw Markdown files (default: data/markdown/)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parent.parent / "data" / "cleaned",
        help="Output directory for cleaned Markdown files (default: data/cleaned/)",
    )
    args = parser.parse_args()

    if not args.input.exists():
        logger.error(f"Input directory does not exist: {args.input}")
        sys.exit(1)

    clean_all(args.input, args.output)


if __name__ == "__main__":
    main()
