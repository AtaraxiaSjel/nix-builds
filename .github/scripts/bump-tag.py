#!/usr/bin/env python3
"""Bump the `?ref=<tag>` release pin of a flake input in flake.nix.

Used by the weekly CI workflow. Updating flake.lock alone cannot move
inputs pinned to a tag: the `?ref=` value lives in flake.nix, so it has to
be rewritten by hand (or by this script).

Usage: bump-tag.py <flake.nix> <input-name> <new-tag>

Both input styles are supported:

    freesmlauncher.url = "github:owner/repo?ref=1.2.3";

    freesmlauncher = {
      url = "github:owner/repo?ref=1.2.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

Exit codes:
  0 - pin bumped, or already at the requested tag
  2 - input not found, or it has no `?ref=` pin (broken entry -> hard error)
"""
import re
import sys


def find_input_url(text: str, name: str) -> str | None:
    """Return the `url = "..."` value of the given input, or None."""
    # Style 1: <name>.url = "..."
    one_line = re.search(
        rf'(?m)^\s*{re.escape(name)}\.url\s*=\s*"(?P<url>[^"]+)"', text
    )
    if one_line:
        return one_line.group("url")

    # Style 2: <name> = { ... url = "..."; ... }
    block = re.search(rf'(?m)^\s*{re.escape(name)}\s*=\s*\{{', text)
    if not block:
        return None
    # Walk the block, tracking brace depth and skipping string literals.
    depth = 0
    i = block.end() - 1
    in_string = False
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = text[block.end() : i]
    url = re.search(r'(?m)^\s*url\s*=\s*"(?P<url>[^"]+)"', body)
    return url.group("url") if url else None


def main() -> int:
    path, name, tag = sys.argv[1:4]
    with open(path, encoding="utf-8") as f:
        text = f.read()

    url = find_input_url(text, name)
    if url is None:
        print(f"ERROR: input '{name}' not found in {path}", file=sys.stderr)
        return 2
    if "?ref=" not in url:
        print(
            f"ERROR: input '{name}' has no '?ref=' pin (url: {url}) - it is not "
            "release-pinned",
            file=sys.stderr,
        )
        return 2

    old = url.split("?ref=", 1)[1]
    if old == tag:
        print(f"{name}: already at ref {tag}")
        return 0

    new_url = url.replace(f"?ref={old}", f"?ref={tag}", 1)
    # Replace only the url occurrence that belongs to this input.
    pattern = re.compile(r'(?m)^(\s*url\s*=\s*)"' + re.escape(url) + r'"')
    text, n = pattern.subn(lambda m: f'{m.group(1)}"{new_url}"', text, count=1)
    if n != 1:
        # Style 1 (`name.url = "..."`) - replace the whole assignment.
        pattern = re.compile(
            r'(?m)^(\s*' + re.escape(name) + r'\.url\s*=\s*)"' + re.escape(url) + r'"'
        )
        text, n = pattern.subn(lambda m: f'{m.group(1)}"{new_url}"', text, count=1)
    if n != 1:
        print(f"ERROR: could not rewrite url of '{name}'", file=sys.stderr)
        return 2

    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"{name}: bumped ref {old} -> {tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
