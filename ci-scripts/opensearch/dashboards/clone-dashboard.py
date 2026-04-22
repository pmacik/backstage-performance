#!/usr/bin/env python3

"""
Clone an OpenSearch Dashboards exported NDJSON for a different index pattern.

Reads a template dashboard export, replaces the variant identifier in titles
and the index-pattern name, generates fresh UUIDs for every saved object, and
rewires all internal references so the result can be imported alongside the
original without conflicts.

Usage:
    ./clone-dashboard.py <template.ndjson> <variant> [--index-pattern <pattern>]

Examples:
    # Variant name is used in titles; index-pattern defaults to
    # rhdh-performance.<variant>*
    ./clone-dashboard.py rhdh-dashboard.mvp-cpt.ndjson baseline-cpt

    # Explicit index-pattern override
    ./clone-dashboard.py rhdh-dashboard.mvp-cpt.ndjson scale-cpt \
        --index-pattern 'rhdh-performance.scale-cpt*'

The output file is written next to the template as
    rhdh-dashboard.<variant>.ndjson
"""

import argparse
import json
import re
import uuid
from pathlib import Path


def read_ndjson(path: Path) -> list[dict]:
    """Read NDJSON — supports both strict (one object per line) and pretty-printed formats."""
    text = path.read_text()
    try:
        wrapped = "[" + re.sub(r"\}\n\{", "},\n{", text) + "]"
        return json.loads(wrapped)
    except json.JSONDecodeError:
        return [json.loads(line) for line in text.splitlines() if line.strip()]


def write_ndjson(path: Path, objects: list[dict]):
    """Write strict NDJSON — one compact JSON object per line."""
    lines = [json.dumps(obj, separators=(",", ":")) for obj in objects]
    path.write_text("\n".join(lines) + "\n")


def detect_variant(objects: list[dict]) -> str:
    """Auto-detect the variant slug from the dashboard title, e.g. 'mvp-cpt'."""
    for obj in objects:
        if obj.get("type") == "dashboard":
            title = obj["attributes"]["title"]
            m = re.search(r"\(([^)]+)\)\s*$", title)
            if m:
                return m.group(1)
    raise SystemExit("Cannot auto-detect variant from dashboard title")


def clone(objects: list[dict], old_variant: str, new_variant: str,
          new_index_pattern: str | None) -> list[dict]:
    # Index-pattern title in the export may not match rhdh-performance.{old_variant}*
    # (e.g. template uses "mvp-cpt-template" while the dashboard title says "mvp-cpt-legacy").
    new_ip = new_index_pattern or f"rhdh-performance.{new_variant}*"

    id_map: dict[str, str] = {}
    for obj in objects:
        old_id = obj.get("id")
        if old_id:
            id_map[old_id] = str(uuid.uuid4())

    cloned: list[dict] = []
    for obj in objects:
        obj = json.loads(json.dumps(obj))

        if "type" not in obj:
            cloned.append(obj)
            continue

        obj["id"] = id_map.get(obj["id"], obj["id"])
        obj.pop("version", None)
        obj.pop("updated_at", None)

        for ref in obj.get("references", []):
            if ref["id"] in id_map:
                ref["id"] = id_map[ref["id"]]

        attrs = obj.get("attributes", {})

        if obj["type"] == "index-pattern":
            attrs["title"] = new_ip
        elif "title" in attrs:
            attrs["title"] = attrs["title"].replace(old_variant, new_variant)

        if "visState" in attrs:
            vs = json.loads(attrs["visState"])
            if "title" in vs:
                vs["title"] = vs["title"].replace(old_variant, new_variant)
            attrs["visState"] = json.dumps(vs)

        cloned.append(obj)

    return cloned


def main():
    parser = argparse.ArgumentParser(
        description="Clone an OpenSearch dashboard export for a different index pattern.")
    parser.add_argument("template", type=Path,
                        help="Path to the template NDJSON export")
    parser.add_argument(
        "variant", help="New variant slug (e.g. 'baseline-cpt')")
    parser.add_argument("--index-pattern",
                        help="Override the generated index-pattern name "
                             "(default: rhdh-performance.<variant>*)")
    parser.add_argument("-o", "--output", type=Path,
                        help="Output file path (default: rhdh-dashboard.<variant>.ndjson "
                             "next to the template)")
    args = parser.parse_args()

    if not args.template.exists():
        raise SystemExit(f"Template not found: {args.template}")

    objects = read_ndjson(args.template)
    old_variant = detect_variant(objects)
    old_index_title = next(
        (o["attributes"]["title"] for o in objects if o.get("type") == "index-pattern"),
        None,
    )
    new_index_title = args.index_pattern or f"rhdh-performance.{args.variant}*"
    cloned = clone(objects, old_variant, args.variant, args.index_pattern)

    out = args.output or args.template.parent / \
        f"rhdh-dashboard.{args.variant}.ndjson"
    write_ndjson(out, cloned)

    n_viz = sum(1 for o in cloned if o.get("type") == "visualization")
    print(f"Cloned dashboard: {old_variant} -> {args.variant}")
    print(f"  Index pattern : {old_index_title or '?'} -> {new_index_title}")
    print(
        f"  Objects       : 1 index-pattern, {n_viz} visualizations, 1 dashboard")
    print(f"  Output        : {out}")


if __name__ == "__main__":
    main()
