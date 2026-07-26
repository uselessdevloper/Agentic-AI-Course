#!/usr/bin/env python3
"""
jsonl_validator.py
Validates JSONL training dataset files for LLM fine-tuning quality and correctness.

Checks performed:
  - Valid JSON on every line
  - Required keys present: 'messages'
  - Message roles: exactly [system, user, assistant] in correct order
  - Minimum content length per message
  - No empty string content
  - Token count estimation (rough, based on word split / 0.75)
  - Max token limit warning per example (default: 4096)
  - Duplicate detection (via content hash)
  - Statistics summary report

Usage:
    python scripts/jsonl_validator.py data/datasets/combined.jsonl
    python scripts/jsonl_validator.py data/datasets/train.jsonl --max-tokens 8192
    python scripts/jsonl_validator.py data/datasets/  # validates all .jsonl in directory
"""

import argparse
import hashlib
import json
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


@dataclass
class ValidationStats:
    file: str
    total: int = 0
    valid: int = 0
    invalid: int = 0
    warnings: int = 0
    duplicates: int = 0
    token_counts: list[int] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def avg_tokens(self) -> float:
        return sum(self.token_counts) / max(len(self.token_counts), 1)

    @property
    def max_tokens(self) -> int:
        return max(self.token_counts) if self.token_counts else 0

    @property
    def min_tokens(self) -> int:
        return min(self.token_counts) if self.token_counts else 0


def estimate_tokens(text: str) -> int:
    """Rough token count estimate: words / 0.75 ≈ BPE tokens."""
    return int(len(text.split()) / 0.75)


def validate_record(
    record: dict,
    line_num: int,
    max_tokens: int,
    seen_hashes: set[str],
    stats: ValidationStats,
) -> bool:
    """Validate a single JSONL record. Returns True if valid."""
    errors: list[str] = []
    warnings: list[str] = []

    # ── Check 'messages' key ──────────────────────────────────────────────────
    if "messages" not in record:
        errors.append(f"Line {line_num}: Missing required key 'messages'")
        stats.errors.extend(errors)
        stats.invalid += 1
        return False

    messages = record["messages"]

    # ── Check it's a list ─────────────────────────────────────────────────────
    if not isinstance(messages, list):
        errors.append(f"Line {line_num}: 'messages' must be a list, got {type(messages).__name__}")
        stats.errors.extend(errors)
        stats.invalid += 1
        return False

    # ── Check role structure ──────────────────────────────────────────────────
    roles = [m.get("role", "") for m in messages]
    expected_roles = ["system", "user", "assistant"]

    if roles != expected_roles:
        errors.append(
            f"Line {line_num}: Expected roles {expected_roles}, got {roles}"
        )
        stats.errors.extend(errors)
        stats.invalid += 1
        return False

    # ── Check content fields ──────────────────────────────────────────────────
    full_text = ""
    for msg in messages:
        content = msg.get("content", "")
        if not isinstance(content, str):
            errors.append(f"Line {line_num}: message content must be a string")
            break
        if len(content.strip()) < 10:
            warnings.append(
                f"Line {line_num}: Very short content ({len(content)} chars) "
                f"in role='{msg['role']}'"
            )
        full_text += content + " "

    if errors:
        stats.errors.extend(errors)
        stats.invalid += 1
        return False

    # ── Token count check ─────────────────────────────────────────────────────
    token_est = estimate_tokens(full_text)
    stats.token_counts.append(token_est)

    if token_est > max_tokens:
        warnings.append(
            f"Line {line_num}: Estimated tokens ({token_est:,}) exceeds limit ({max_tokens:,})"
        )

    # ── Duplicate detection ───────────────────────────────────────────────────
    content_hash = hashlib.md5(full_text.encode("utf-8")).hexdigest()
    if content_hash in seen_hashes:
        warnings.append(f"Line {line_num}: Duplicate record detected")
        stats.duplicates += 1
    else:
        seen_hashes.add(content_hash)

    if warnings:
        for w in warnings:
            logger.warning(f"  ⚠️  {w}")
        stats.warnings += len(warnings)

    stats.valid += 1
    return True


def validate_file(jsonl_path: Path, max_tokens: int) -> ValidationStats:
    """Validate all records in a JSONL file."""
    stats = ValidationStats(file=jsonl_path.name)
    seen_hashes: set[str] = set()

    logger.info(f"\n📋 Validating: {jsonl_path}")

    with jsonl_path.open("r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue

            stats.total += 1

            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                stats.errors.append(f"Line {line_num}: Invalid JSON — {e}")
                stats.invalid += 1
                continue

            validate_record(record, line_num, max_tokens, seen_hashes, stats)

    return stats


def print_report(stats: ValidationStats) -> None:
    """Print a human-readable validation summary."""
    sep = "─" * 56
    logger.info(f"\n{sep}")
    logger.info(f"  Validation Report: {stats.file}")
    logger.info(sep)
    logger.info(f"  Total records   : {stats.total:>8,}")
    logger.info(f"  ✅ Valid         : {stats.valid:>8,}")
    logger.info(f"  ❌ Invalid       : {stats.invalid:>8,}")
    logger.info(f"  ⚠️  Warnings      : {stats.warnings:>8,}")
    logger.info(f"  🔁 Duplicates    : {stats.duplicates:>8,}")
    if stats.token_counts:
        logger.info(f"  Avg tokens/ex   : {stats.avg_tokens:>8,.0f}")
        logger.info(f"  Min tokens/ex   : {stats.min_tokens:>8,}")
        logger.info(f"  Max tokens/ex   : {stats.max_tokens:>8,}")
    if stats.errors:
        logger.info(f"\n  First 10 errors:")
        for err in stats.errors[:10]:
            logger.error(f"    {err}")
    logger.info(sep)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate JSONL training dataset files for LLM fine-tuning"
    )
    parser.add_argument(
        "path",
        type=Path,
        help="Path to a JSONL file or directory containing .jsonl files",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=4096,
        help="Maximum estimated tokens per training example (default: 4096)",
    )
    args = parser.parse_args()

    if not args.path.exists():
        logger.error(f"Path does not exist: {args.path}")
        sys.exit(1)

    # Gather files to validate
    if args.path.is_dir():
        files = sorted(args.path.glob("*.jsonl"))
        if not files:
            logger.error(f"No .jsonl files found in directory: {args.path}")
            sys.exit(1)
    else:
        files = [args.path]

    all_stats: list[ValidationStats] = []
    any_invalid = False

    for jsonl_file in files:
        stats = validate_file(jsonl_file, max_tokens=args.max_tokens)
        print_report(stats)
        all_stats.append(stats)
        if stats.invalid > 0:
            any_invalid = True

    # Aggregate summary if multiple files
    if len(all_stats) > 1:
        total_records = sum(s.total for s in all_stats)
        total_valid = sum(s.valid for s in all_stats)
        total_invalid = sum(s.invalid for s in all_stats)
        logger.info(f"\n{'═'*56}")
        logger.info(f"  AGGREGATE SUMMARY ({len(all_stats)} files)")
        logger.info(f"  Total records: {total_records:,}")
        logger.info(f"  Valid: {total_valid:,}  |  Invalid: {total_invalid:,}")
        logger.info(f"{'═'*56}")

    sys.exit(1 if any_invalid else 0)


if __name__ == "__main__":
    main()
