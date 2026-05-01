#!/usr/bin/env python3
"""Generate regex-derived reflective block mappings for Complementary shaders.

The script rewrites only the marked generated section in shaders/block.properties.
Edit scripts/reflective_block_rules.json to change the rules, then rerun this
script with a block registry dump/list.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Iterable


BEGIN_MARKER = "# BEGIN GENERATED REFLECTIVE BLOCKS"
END_MARKER = "# END GENERATED REFLECTIVE BLOCKS"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate reflective block.properties entries from regex rules."
    )
    parser.add_argument(
        "blocks",
        nargs="+",
        type=Path,
        help=(
            "Text file(s) containing one block id per line. Lines may include extra "
            "columns; the first namespaced id is used when present."
        ),
    )
    parser.add_argument(
        "--rules",
        type=Path,
        default=Path("scripts/reflective_block_rules.json"),
        help="JSON rule config. Default: scripts/reflective_block_rules.json",
    )
    parser.add_argument(
        "--block-properties",
        type=Path,
        default=Path("shaders/block.properties"),
        help="Target block.properties file. Default: shaders/block.properties",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the generated section without changing block.properties.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit with 1 if block.properties is not up to date.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"Missing rules file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc


def extract_block_id(line: str) -> str | None:
    line = line.strip()
    if not line or line.startswith("#"):
        return None

    line = line.split("#", 1)[0].strip()
    if not line:
        return None

    namespaced = re.search(r"[A-Za-z0-9_.-]+:[A-Za-z0-9_./-]+(?:\[[^\]\s]+\])?", line)
    if namespaced:
        return namespaced.group(0)

    token = re.split(r"[\s,;]+", line, maxsplit=1)[0].strip()
    if not token or "=" in token:
        return None
    return token


def load_blocks(paths: Iterable[Path]) -> list[str]:
    seen: set[str] = set()
    blocks: list[str] = []
    for path in paths:
        try:
            raw_lines = path.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            raise SystemExit(f"Missing block list: {path}")

        for line in raw_lines:
            block_id = extract_block_id(line)
            if block_id and block_id not in seen:
                seen.add(block_id)
                blocks.append(block_id)
    return blocks


def compile_rules(config: dict) -> tuple[list[dict], re.Pattern[str] | None, str]:
    rules = config.get("rules")
    if not isinstance(rules, list):
        raise SystemExit("Rule config must contain a 'rules' array.")

    compiled_rules: list[dict] = []
    for index, rule in enumerate(rules):
        try:
            name = str(rule["name"])
            target = str(rule["target"])
            pattern = str(rule["regex"])
        except KeyError as exc:
            raise SystemExit(f"Rule #{index + 1} is missing {exc}.") from exc

        if not re.fullmatch(r"\d+", target):
            raise SystemExit(f"Rule '{name}' has invalid target '{target}'.")

        try:
            compiled = re.compile(pattern)
        except re.error as exc:
            raise SystemExit(f"Rule '{name}' has invalid regex: {exc}") from exc

        compiled_rules.append(
            {
                "name": name,
                "target": target,
                "pattern": compiled,
            }
        )

    exclude_pattern = config.get("exclude_regex")
    exclude = None
    if exclude_pattern:
        try:
            exclude = re.compile(str(exclude_pattern))
        except re.error as exc:
            raise SystemExit(f"Invalid exclude_regex: {exc}") from exc

    insert_before = str(config.get("insert_before", "block.20000="))
    return compiled_rules, exclude, insert_before


def match_blocks(
    blocks: Iterable[str], rules: list[dict], exclude: re.Pattern[str] | None
) -> OrderedDict[str, list[tuple[str, str]]]:
    grouped: OrderedDict[str, list[tuple[str, str]]] = OrderedDict()
    for rule in rules:
        grouped.setdefault(rule["target"], [])

    assigned: set[str] = set()
    for block_id in blocks:
        if exclude and exclude.search(block_id):
            continue
        for rule in rules:
            if rule["pattern"].search(block_id):
                if block_id not in assigned:
                    grouped[rule["target"]].append((block_id, rule["name"]))
                    assigned.add(block_id)
                break

    return grouped


def build_section(grouped: OrderedDict[str, list[tuple[str, str]]], sources: Iterable[Path], rules: Path) -> str:
    source_text = ", ".join(str(source) for source in sources)
    lines = [
        BEGIN_MARKER,
        "# Generated by scripts/generate_reflective_blocks.py.",
        f"# Source blocks: {source_text}",
        f"# Rules: {rules}",
        "# Edit the rules/input and rerun the script; do not hand-edit this section.",
    ]

    total = 0
    for target, matches in grouped.items():
        blocks = [block_id for block_id, _rule_name in matches]
        if not blocks:
            continue
        total += len(blocks)
        lines.append(f"# {len(blocks)} generated block(s) mapped to material {target}")
        lines.append(f"block.{target}=" + " ".join(blocks))

    if total == 0:
        lines.append("# No blocks matched the current rules.")

    lines.append(END_MARKER)
    return "\n".join(lines) + "\n"


def replace_section(original: str, section: str, insert_before: str) -> str:
    pattern = re.compile(
        rf"(?ms)^({re.escape(BEGIN_MARKER)}\n.*?^{re.escape(END_MARKER)}\n?)"
    )
    if pattern.search(original):
        return pattern.sub(section, original, count=1)

    marker_index = original.find(insert_before)
    if marker_index >= 0:
        prefix = original[:marker_index].rstrip() + "\n\n"
        suffix = original[marker_index:].lstrip("\n")
        return prefix + section + "\n" + suffix

    return original.rstrip() + "\n\n" + section


def main() -> int:
    args = parse_args()
    config = load_json(args.rules)
    rules, exclude, insert_before = compile_rules(config)
    blocks = load_blocks(args.blocks)
    grouped = match_blocks(blocks, rules, exclude)
    section = build_section(grouped, args.blocks, args.rules)

    if args.dry_run:
        sys.stdout.write(section)
        return 0

    try:
        original_bytes = args.block_properties.read_bytes()
    except FileNotFoundError:
        raise SystemExit(f"Missing block.properties: {args.block_properties}")

    original = original_bytes.decode("utf-8")
    newline = "\r\n" if "\r\n" in original else "\n"
    normalized_original = original.replace("\r\n", "\n")
    updated = replace_section(normalized_original, section, insert_before)
    if newline == "\r\n":
        updated = updated.replace("\n", "\r\n")

    if args.check:
        if updated != original:
            print(f"{args.block_properties} is not up to date", file=sys.stderr)
            return 1
        return 0

    if updated != original:
        args.block_properties.write_bytes(updated.encode("utf-8"))

    generated_count = sum(len(matches) for matches in grouped.values())
    print(f"Generated {generated_count} reflective block mapping(s).")
    print(f"Updated {args.block_properties}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
