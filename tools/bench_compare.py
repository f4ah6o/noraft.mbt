#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def load_file(path: Path):
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"{path} is not a JSON array")
    return data


def format_row(label, target, item):
    ns_per_iter = item.get("ns_per_iter", 0.0)
    total_secs = item.get("total_secs", 0.0)
    iters = item.get("iters", 0)
    return f"{label:<10} {target:<10} {ns_per_iter:>12.3f} {total_secs:>12.6f} {iters:>10}"


def main():
    paths = [Path(p) for p in sys.argv[1:]]
    if not paths:
        print("usage: bench_compare.py <json...>")
        return 2

    items = []
    for path in paths:
        items.extend(load_file(path))

    scenarios = sorted({item.get("scenario", "") for item in items})
    by_scenario = {scenario: [] for scenario in scenarios}
    for item in items:
        by_scenario[item.get("scenario", "")].append(item)

    order = [
        ("rust", "rust"),
        ("moonbit", "native"),
        ("moonbit", "wasm-gc"),
    ]

    for scenario in scenarios:
        print(f"== {scenario}")
        print(f"{'impl':<10} {'target':<10} {'ns/iter':>12} {'secs':>12} {'iters':>10}")
        entries = by_scenario.get(scenario, [])
        lookup = {(e.get("impl"), e.get("target")): e for e in entries}
        for impl_name, target in order:
            item = lookup.get((impl_name, target))
            if item:
                print(format_row(impl_name, target, item))

        rust_item = lookup.get(("rust", "rust"))
        if rust_item:
            rust_ns = rust_item.get("ns_per_iter", 0.0) or 0.0
            for impl_name, target in order:
                if impl_name == "rust":
                    continue
                item = lookup.get((impl_name, target))
                if item and rust_ns > 0.0:
                    ratio = item.get("ns_per_iter", 0.0) / rust_ns
                    print(f"ratio vs rust ({impl_name}/{target}): {ratio:.3f}x")
        print("")


if __name__ == "__main__":
    raise SystemExit(main())
