#!/usr/bin/env python3
"""Create or verify TermLoom's canonical public symbol-graph baseline."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any


def canonical_symbol(symbol: dict[str, Any]) -> dict[str, Any]:
    names = symbol.get("names", {})
    return {
        "id": symbol["identifier"]["precise"],
        "kind": symbol["kind"]["identifier"],
        "path": symbol.get("pathComponents", []),
        "title": names.get("title", ""),
        "declaration": "".join(
            fragment.get("spelling", "")
            for fragment in symbol.get("declarationFragments", [])
        ),
        "accessLevel": symbol.get("accessLevel", "public"),
        "availability": symbol.get("availability", []),
    }


def canonical_relationship(relationship: dict[str, Any]) -> dict[str, Any]:
    result = {
        "kind": relationship["kind"],
        "source": relationship["source"],
        "target": relationship["target"],
    }
    if "targetFallback" in relationship:
        result["targetFallback"] = relationship["targetFallback"]
    return result


def load_graphs(graph_directory: pathlib.Path) -> dict[str, Any]:
    paths = sorted(graph_directory.glob("TermLoom.symbols.json"))
    paths += sorted(graph_directory.glob("TermLoom@*.symbols.json"))
    if not paths:
        raise RuntimeError(f"no TermLoom symbol graphs found in {graph_directory}")

    symbols: dict[str, dict[str, Any]] = {}
    relationships: dict[str, dict[str, Any]] = {}
    for path in paths:
        graph = json.loads(path.read_text())
        if graph.get("module", {}).get("name") != "TermLoom":
            continue
        for raw_symbol in graph.get("symbols", []):
            symbol = canonical_symbol(raw_symbol)
            symbols[symbol["id"]] = symbol
        for raw_relationship in graph.get("relationships", []):
            relationship = canonical_relationship(raw_relationship)
            key = json.dumps(relationship, sort_keys=True, separators=(",", ":"))
            relationships[key] = relationship

    return {
        "schemaVersion": 1,
        "module": "TermLoom",
        "symbols": sorted(symbols.values(), key=lambda value: value["id"]),
        "relationships": sorted(
            relationships.values(),
            key=lambda value: (value["kind"], value["source"], value["target"]),
        ),
    }


def keyed_symbols(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {symbol["id"]: symbol for symbol in snapshot["symbols"]}


def keyed_relationships(snapshot: dict[str, Any]) -> set[str]:
    return {
        json.dumps(value, sort_keys=True, separators=(",", ":"))
        for value in snapshot["relationships"]
    }


def describe(symbol: dict[str, Any]) -> str:
    declaration = symbol.get("declaration") or symbol.get("title") or symbol["id"]
    return declaration.replace("\n", " ")


def check(baseline: dict[str, Any], current: dict[str, Any]) -> int:
    baseline_symbols = keyed_symbols(baseline)
    current_symbols = keyed_symbols(current)
    failures: list[str] = []

    for identifier in sorted(baseline_symbols.keys() - current_symbols.keys()):
        failures.append(f"removed symbol: {describe(baseline_symbols[identifier])}")
    for identifier in sorted(baseline_symbols.keys() & current_symbols.keys()):
        if baseline_symbols[identifier] != current_symbols[identifier]:
            failures.append(f"changed symbol: {describe(baseline_symbols[identifier])}")

    removed_relationships = keyed_relationships(baseline) - keyed_relationships(current)
    for encoded in sorted(removed_relationships):
        relationship = json.loads(encoded)
        failures.append(
            "removed relationship: "
            f"{relationship['kind']} {relationship['source']} -> {relationship['target']}"
        )

    if failures:
        print("TermLoom public API baseline changed:", file=sys.stderr)
        for failure in failures[:100]:
            print(f"  - {failure}", file=sys.stderr)
        if len(failures) > 100:
            print(f"  - …and {len(failures) - 100} more", file=sys.stderr)
        print(
            "Review the change against Documentation/APIStability.md. "
            "For an intentional reviewed change, record it in Documentation/APIChanges.md "
            "and run Scripts/check-api.sh --update.",
            file=sys.stderr,
        )
        return 1

    additions = len(current_symbols.keys() - baseline_symbols.keys())
    print(
        f"TermLoom API baseline passed ({len(baseline_symbols)} protected symbols; "
        f"{additions} additive symbols)."
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("check", "update"))
    parser.add_argument("graph_directory", type=pathlib.Path)
    parser.add_argument("baseline", type=pathlib.Path)
    arguments = parser.parse_args()

    current = load_graphs(arguments.graph_directory)
    if arguments.mode == "update":
        arguments.baseline.parent.mkdir(parents=True, exist_ok=True)
        arguments.baseline.write_text(json.dumps(current, indent=2, sort_keys=False) + "\n")
        print(
            f"Updated {arguments.baseline} with {len(current['symbols'])} public symbols."
        )
        return 0

    if not arguments.baseline.exists():
        print(
            f"Missing API baseline at {arguments.baseline}; run Scripts/check-api.sh --update.",
            file=sys.stderr,
        )
        return 1
    baseline = json.loads(arguments.baseline.read_text())
    return check(baseline, current)


if __name__ == "__main__":
    raise SystemExit(main())
