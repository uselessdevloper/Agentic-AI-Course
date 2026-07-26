#!/usr/bin/env python3
"""
pdf_to_md.py
Stage 1 of the data pipeline.

Handles THREE input formats found across the raw/ subdirectories:
  1. PDF  → Markdown   (via pymupdf4llm)
  2. DOCX → Markdown   (via python-docx + markdownify)
  3. .md / .mdx        → Copied as-is into data/markdown/
  4. .rst              → Converted to Markdown (via rst-to-myst or pandoc fallback)

Usage:
    python scripts/pdf_to_md.py
    python scripts/pdf_to_md.py --input data/raw --output data/markdown
    python scripts/pdf_to_md.py --input data/raw/fastapi --output data/markdown/fastapi
    python scripts/pdf_to_md.py --dry-run   # Preview without writing files
"""

import argparse
import logging
import shutil
import subprocess
import sys
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

SUPPORTED_EXTENSIONS = {".pdf", ".docx", ".md", ".mdx", ".rst"}


# ── Converters ────────────────────────────────────────────────────────────────

def convert_pdf(src: Path, out_dir: Path) -> Path:
    try:
        import pymupdf4llm  # type: ignore
    except ImportError:
        logger.error("Run: pip install pymupdf4llm pymupdf")
        sys.exit(1)

    text: str = pymupdf4llm.to_markdown(str(src))
    out = out_dir / (src.stem + ".md")
    out.write_text(text, encoding="utf-8")
    return out


def convert_docx(src: Path, out_dir: Path) -> Path:
    try:
        from docx import Document  # type: ignore
        from markdownify import markdownify as md_convert  # type: ignore
    except ImportError:
        logger.error("Run: pip install python-docx markdownify")
        sys.exit(1)

    doc = Document(str(src))
    html_parts: list[str] = []
    for para in doc.paragraphs:
        style = para.style.name.lower()
        text = para.text.strip()
        if not text:
            html_parts.append("")
            continue
        if "heading 1" in style:
            html_parts.append(f"<h1>{text}</h1>")
        elif "heading 2" in style:
            html_parts.append(f"<h2>{text}</h2>")
        elif "heading 3" in style:
            html_parts.append(f"<h3>{text}</h3>")
        else:
            html_parts.append(f"<p>{text}</p>")

    md_text: str = md_convert("\n".join(html_parts), heading_style="ATX")
    out = out_dir / (src.stem + ".md")
    out.write_text(md_text, encoding="utf-8")
    return out


def copy_markdown(src: Path, out_dir: Path) -> Path:
    """Copy .md/.mdx files directly — no conversion needed."""
    out = out_dir / (src.stem + ".md")  # Normalize .mdx → .md
    shutil.copy2(src, out)
    return out


def convert_rst(src: Path, out_dir: Path) -> Path:
    """Convert .rst to Markdown via pandoc (if available)."""
    out = out_dir / (src.stem + ".md")

    if shutil.which("pandoc"):
        result = subprocess.run(
            ["pandoc", str(src), "-f", "rst", "-t", "markdown", "-o", str(out)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            logger.warning(f"  pandoc error for {src.name}: {result.stderr.strip()}")
            # Fallback: copy raw RST content into markdown file
            out.write_text(src.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    else:
        # No pandoc — just copy raw RST content (clean_markdown.py will normalize it)
        logger.warning(f"  pandoc not found — copying raw RST: {src.name}")
        out.write_text(src.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")

    return out


# ── Core processing ───────────────────────────────────────────────────────────

def process_file(src: Path, out_dir: Path, dry_run: bool = False) -> bool:
    suffix = src.suffix.lower()

    if suffix not in SUPPORTED_EXTENSIONS:
        return False

    # Compute relative output path mirroring source subdirectory structure
    logger.info(f"  [{suffix}] {src.name}")

    if dry_run:
        return True

    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        if suffix == ".pdf":
            out = convert_pdf(src, out_dir)
        elif suffix == ".docx":
            out = convert_docx(src, out_dir)
        elif suffix in (".md", ".mdx"):
            out = copy_markdown(src, out_dir)
        elif suffix == ".rst":
            out = convert_rst(src, out_dir)
        else:
            return False

        size_kb = out.stat().st_size / 1024
        logger.info(f"     → {out.name} ({size_kb:.1f} KB)")
        return True

    except Exception as e:
        logger.error(f"  [FAILED] {src.name}: {e}")
        return False


def process_directory(input_dir: Path, output_dir: Path, dry_run: bool = False) -> tuple[int, int]:
    """Process all supported files in input_dir, mirroring subdirectory structure."""
    total = 0
    success = 0

    # Find all matching files recursively
    files: list[Path] = []
    for ext in SUPPORTED_EXTENSIONS:
        files.extend(input_dir.rglob(f"*{ext}"))

    # Exclude hidden dirs and .git
    files = [
        f for f in files
        if ".git" not in f.parts
        and not any(part.startswith(".") for part in f.parts)
    ]
    files.sort()

    if not files:
        logger.warning(f"No supported files found in: {input_dir}")
        return 0, 0

    logger.info(f"\nFound {len(files)} file(s) to process in {input_dir}")

    for src in files:
        # Mirror subdirectory path under output_dir
        relative_parent = src.parent.relative_to(input_dir)
        target_dir = output_dir / relative_parent
        total += 1
        if process_file(src, target_dir, dry_run=dry_run):
            success += 1

    return total, success


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stage 1: Convert/copy raw documents from data/raw/ → data/markdown/"
    )
    parser.add_argument(
        "--input", "-i",
        type=Path,
        default=Path(__file__).parent.parent / "data" / "raw",
        help="Input directory (default: data/raw/)",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path(__file__).parent.parent / "data" / "markdown",
        help="Output directory (default: data/markdown/)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview files to be processed without writing anything",
    )
    args = parser.parse_args()

    if not args.input.exists():
        logger.error(f"Input directory does not exist: {args.input}")
        sys.exit(1)

    if args.dry_run:
        logger.info("[DRY RUN] No files will be written.")

    total, success = process_directory(args.input, args.output, dry_run=args.dry_run)

    emoji = "✅" if success == total else "⚠️ "
    logger.info(f"\n{emoji} Processed {success}/{total} files → {args.output}")


if __name__ == "__main__":
    main()
