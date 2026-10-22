#!/usr/bin/env python3
"""List the flake inputs that are pinned to an explicit ref.

Reads the JSON produced by `nix flake metadata --json` and prints one line
per *direct* input of the root flake that carries an explicit ref:

    <input-name>\t<owner>/<repo>\t<ref>

Only github inputs are reported. The caller decides which of those refs are
release pins (i.e. exist as a git tag) - branch refs like `release` or
`main` must be left alone.

Usage: find-tag-pins.py <flake-metadata.json>
"""
import json
import sys


def main() -> int:
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)

    locks = meta.get("locks") or meta
    nodes = locks.get("nodes", {})
    root = nodes.get(locks.get("root", "root"), {})

    # Direct inputs of the root flake only (nested inputs are not ours to bump).
    for name, node_name in sorted(root.get("inputs", {}).items()):
        node = nodes.get(node_name, {})
        original = node.get("original", {})
        if original.get("type") != "github":
            continue
        ref = original.get("ref")
        if not ref:
            continue
        owner, repo = original.get("owner"), original.get("repo")
        if not owner or not repo:
            continue
        print(f"{name}\t{owner}/{repo}\t{ref}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
