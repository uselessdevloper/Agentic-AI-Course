#!/usr/bin/env python3
"""
dataset_split.py
Reads JSONL training data from data/datasets/ and splits into train/validation/test sets.
Also supports converting cleaned Markdown files (data/cleaned/) into JSONL format
using an instruction-tuning template (system + user + assistant).

Usage:
    # Step 1: Convert cleaned markdown → JSONL
    python scripts/dataset_split.py --convert

    # Step 2: Split existing JSONL into train/val/test
    python scripts/dataset_split.py --split

    # Full pipeline (convert then split)
    python scripts/dataset_split.py --convert --split
"""

import argparse
import json
import logging
import random
import re
import sys
from pathlib import Path
from typing import Generator

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = (
    "You are an expert Enterprise Software Engineering & AI Assistant. "
    "You specialize in Python, FastAPI, React, TypeScript, System Design, "
    "Microservices, Docker, Kubernetes, PostgreSQL, Redis, AI Agents, RAG, "
    "LLM Engineering, Google Cloud, and Software Architecture. "
    "Answer all questions with technical precision, practical code examples, "
    "and best-practice recommendations."
)

# Heading extractor
HEADING_RE = re.compile(r"^#{1,3}\s+(.+)$", re.MULTILINE)


def md_to_qa_pairs(md_text: str, source_file: str) -> list[dict]:
    """
    Convert a cleaned Markdown document into instruction-tuning QA pairs.

    Strategy:
    - Extract all top-level headings.
    - For each section, generate a user question + assistant answer.
    - First section → general summary question about the full document.
    """
    pairs: list[dict] = []

    # Split into sections by heading
    sections = re.split(r"(?=^#{1,3}\s)", md_text, flags=re.MULTILINE)
    sections = [s.strip() for s in sections if s.strip()]

    # Full document summary pair
    title_match = HEADING_RE.search(md_text)
    doc_title = title_match.group(1).strip() if title_match else Path(source_file).stem

    full_context = md_text[:3000]  # Cap to avoid token overflow
    pairs.append(
        make_pair(
            user=f"Explain the key concepts covered in: {doc_title}",
            assistant=full_context,
            source=source_file,
        )
    )

    for section in sections[:20]:  # Limit to 20 sections per document
        heading_match = HEADING_RE.match(section)
        if not heading_match:
            continue

        heading = heading_match.group(1).strip()
        # Use text under heading as the assistant answer
        body = section[heading_match.end():].strip()
        if len(body) < 80:  # Skip trivially short sections
            continue

        pairs.append(
            make_pair(
                user=f"What is {heading}? Explain with examples.",
                assistant=body[:2000],
                source=source_file,
            )
        )

    return pairs


def make_pair(user: str, assistant: str, source: str) -> dict:
    """Create a single ChatML-format training example."""
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
            {"role": "assistant", "content": assistant},
        ],
        "metadata": {"source": source},
    }


def convert_cleaned_to_jsonl(cleaned_dir: Path, datasets_dir: Path) -> Path:
    """Convert all cleaned Markdown files into a single combined JSONL file."""
    datasets_dir.mkdir(parents=True, exist_ok=True)

    md_files = sorted(cleaned_dir.rglob("*.md"))
    if not md_files:
        logger.error(f"No cleaned .md files found in: {cleaned_dir}")
        sys.exit(1)

    all_pairs: list[dict] = []
    for md_path in md_files:
        text = md_path.read_text(encoding="utf-8", errors="replace")
        pairs = md_to_qa_pairs(text, source_file=md_path.name)
        all_pairs.extend(pairs)
        logger.info(f"  {md_path.name}: {len(pairs)} training pairs generated")

    output_path = datasets_dir / "combined.jsonl"
    with output_path.open("w", encoding="utf-8") as f:
        for pair in all_pairs:
            f.write(json.dumps(pair, ensure_ascii=False) + "\n")

    logger.info(f"\n✅ Generated {len(all_pairs)} total training examples → {output_path}")
    return output_path


def split_jsonl(
    input_path: Path,
    output_dir: Path,
    train_ratio: float = 0.85,
    val_ratio: float = 0.10,
    seed: int = 42,
) -> dict[str, Path]:
    """Split a JSONL file into train / validation / test subsets."""
    output_dir.mkdir(parents=True, exist_ok=True)

    records: list[dict] = []
    with input_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))

    if not records:
        logger.error(f"JSONL file is empty: {input_path}")
        sys.exit(1)

    random.seed(seed)
    random.shuffle(records)

    n = len(records)
    n_train = int(n * train_ratio)
    n_val = int(n * val_ratio)

    splits = {
        "train": records[:n_train],
        "val": records[n_train : n_train + n_val],
        "test": records[n_train + n_val :],
    }

    paths: dict[str, Path] = {}
    for split_name, split_data in splits.items():
        out_path = output_dir / f"{split_name}.jsonl"
        with out_path.open("w", encoding="utf-8") as f:
            for record in split_data:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        logger.info(f"  {split_name}.jsonl: {len(split_data):,} examples")
        paths[split_name] = out_path

    logger.info(
        f"\n✅ Split {n:,} examples → "
        f"train={len(splits['train'])}, "
        f"val={len(splits['val'])}, "
        f"test={len(splits['test'])}"
    )
    return paths


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert cleaned Markdown → JSONL and split into train/val/test"
    )
    base = Path(__file__).parent.parent / "data"

    parser.add_argument("--convert", action="store_true", help="Convert cleaned MD → JSONL")
    parser.add_argument("--split", action="store_true", help="Split JSONL into train/val/test")
    parser.add_argument(
        "--cleaned", type=Path, default=base / "cleaned",
        help="Cleaned Markdown input dir (default: data/cleaned/)"
    )
    parser.add_argument(
        "--datasets", type=Path, default=base / "datasets",
        help="JSONL output dir (default: data/datasets/)"
    )
    parser.add_argument(
        "--train-ratio", type=float, default=0.85, help="Train split ratio (default: 0.85)"
    )
    parser.add_argument(
        "--val-ratio", type=float, default=0.10, help="Validation split ratio (default: 0.10)"
    )
    parser.add_argument(
        "--seed", type=int, default=42, help="Random seed for shuffling (default: 42)"
    )
    args = parser.parse_args()

    if not args.convert and not args.split:
        logger.error("Specify at least one action: --convert and/or --split")
        parser.print_help()
        sys.exit(1)

    combined_path: Path = args.datasets / "combined.jsonl"

    if args.convert:
        combined_path = convert_cleaned_to_jsonl(args.cleaned, args.datasets)

    if args.split:
        if not combined_path.exists():
            logger.error(f"JSONL file not found: {combined_path}. Run --convert first.")
            sys.exit(1)
        split_jsonl(
            combined_path,
            args.datasets,
            train_ratio=args.train_ratio,
            val_ratio=args.val_ratio,
            seed=args.seed,
        )


if __name__ == "__main__":
    main()
