#!/usr/bin/env python3
"""Bump release-tag pins in flake.nix.

Used by the weekly CI workflow. Updating flake.lock alone cannot move inputs
pinned to a tag: the `?ref=` value lives in flake.nix, so it has to be
rewritten by hand (or by this script).

Discovers the pinned inputs via `nix flake metadata --json` and bumps each:

* github inputs       url = "github:owner/repo?ref=1.2.3"
                      -> to the latest *published GitHub release* of owner/repo

* git inputs on Forgejo/Gitea
                      url = "git+https://forge/owner/repo?ref=refs/tags/v1.2.3"
                      -> to the repo's newest tag (Forgejo allows tag-only
                         "releases", so the tag list is the source of truth)

Pins that turn out to be branches (e.g. nix-cachyos-kernel's "?ref=release")
are left alone.

Every bumped input is reported on stdout as "<name>=<new-ref>", one per line;
informational messages go to stderr.

Usage: bump-input-pins.py <flake-metadata.json> [flake.nix]
"""
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request


def info(msg: str) -> None:
    print(msg, file=sys.stderr)


# ---------------------------------------------------------------------------
# Release/tag lookup per forge type.
# ---------------------------------------------------------------------------


def gh_api_tag_name(path: str) -> str | None:
    """Call `gh api` (authenticated via the GH_TOKEN env) and return the
    `.tag_name` it prints, or None on error (404 etc.)."""
    result = subprocess.run(
        ["gh", "api", path, "--jq", ".tag_name"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def github_ref_is_tag(owner: str, repo: str, ref: str) -> bool:
    """True if `ref` exists as a git tag on GitHub (not a branch)."""
    path = f"repos/{owner}/{repo}/git/ref/tags/{urllib.parse.quote(ref, safe='')}"
    return subprocess.run(["gh", "api", path], capture_output=True).returncode == 0


def forgejo_tags(origin: str, owner_repo: str) -> list[str]:
    """All tag names of a Forgejo/Gitea repository, via its public API."""
    url = f"{origin}/api/v1/repos/{owner_repo}/tags?limit=100"
    with urllib.request.urlopen(url, timeout=30) as response:
        return [tag["name"] for tag in json.load(response)]


def semver_key(tag: str) -> tuple[int, ...]:
    """Sort key for common version tags (v1.2.3, 0.2.0, ...). Tags that do
    not parse numerically sort *after* every versioned tag."""
    parts = tag.removeprefix("v").split(".")
    try:
        return tuple(int(part) for part in parts)
    except ValueError:
        return (0,)


# ---------------------------------------------------------------------------
# Per-input resolution.
# ---------------------------------------------------------------------------


def resolve_github(name: str, owner: str, repo: str, ref: str) -> str | None:
    """New ref for a github input, or None to skip."""
    if not github_ref_is_tag(owner, repo, ref):
        info(f"{name}: ref '{ref}' is not a tag (branch?), skipping")
        return None
    latest = gh_api_tag_name(f"repos/{owner}/{repo}/releases/latest")
    if latest is None:
        info(f"::warning::no published release for {owner}/{repo}, skipping {name}")
        return None
    return latest


def resolve_forgejo(name: str, url: str, ref: str) -> str | None:
    """New ref for a git (Forgejo) input, or None to skip."""
    parsed = urllib.parse.urlparse(url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    owner_repo = parsed.path.strip("/")

    tags = forgejo_tags(origin, owner_repo)
    if ref.removeprefix("refs/tags/") not in tags:
        # Either a branch ref or the tag vanished; both mean "not a pin".
        info(f"{name}: ref '{ref}' is not a tag (branch?), skipping")
        return None
    return "refs/tags/" + max(tags, key=semver_key)


# ---------------------------------------------------------------------------
# flake.nix rewriting.
# ---------------------------------------------------------------------------


def find_input_url(text: str, name: str) -> str | None:
    """Return the `url = "..."` value of the given input, or None."""
    # Style 1: <name>.url = "..."
    one_line = re.search(rf'(?m)^\s*{re.escape(name)}\.url\s*=\s*"([^"]+)"', text)
    if one_line:
        return one_line.group(1)

    # Style 2: <name> = { ... url = "..."; ... }
    block = re.search(rf"(?m)^\s*{re.escape(name)}\s*=\s*\{{", text)
    if not block:
        return None
    # Walk the block, tracking brace depth and skipping string literals.
    depth, i, in_string = 0, block.end() - 1, False
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
    url = re.search(r'(?m)^\s*url\s*=\s*"([^"]+)"', text[block.end() : i])
    return url.group(1) if url else None


def rewrite_pin(text: str, name: str, old_url: str, new_url: str) -> str:
    """Replace only the url occurrence that belongs to this input."""
    pattern = re.compile(r'(?m)^(\s*url\s*=\s*)"' + re.escape(old_url) + r'"')
    text, n = pattern.subn(lambda m: f'{m.group(1)}"{new_url}"', text, count=1)
    if n == 1:
        return text

    # Style 1 (`name.url = "..."`) - replace the whole assignment.
    pattern = re.compile(
        r'(?m)^(\s*' + re.escape(name) + r'\.url\s*=\s*)"' + re.escape(old_url) + r'"'
    )
    text, n = pattern.subn(lambda m: f'{m.group(1)}"{new_url}"', text, count=1)
    if n != 1:
        raise ValueError(f"could not rewrite url of '{name}'")
    return text


# ---------------------------------------------------------------------------
# Driver.
# ---------------------------------------------------------------------------


def load_direct_inputs(meta_path: str) -> dict[str, dict]:
    """Direct inputs of the root flake, keyed by name."""
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
    locks = meta["locks"]
    nodes = locks["nodes"]
    return {name: nodes[node] for name, node in nodes[locks["root"]]["inputs"].items()}


def main() -> int:
    meta_path = sys.argv[1]
    flake_nix_path = sys.argv[2] if len(sys.argv) > 2 else "flake.nix"
    with open(flake_nix_path, encoding="utf-8") as f:
        text = f.read()

    changed = []
    for name, node in sorted(load_direct_inputs(meta_path).items()):
        original = node.get("original", {})
        typ, ref = original.get("type"), original.get("ref")
        if not ref:
            continue  # no ?ref pin; flake.lock alone moves this input.

        if typ == "github":
            new_ref = resolve_github(name, original["owner"], original["repo"], ref)
        elif typ == "git" and original.get("url", "").startswith("https://"):
            new_ref = resolve_forgejo(name, original["url"], ref)
        else:
            continue

        if new_ref is None:
            continue
        # The url as written in flake.nix decides what to rewrite; nix may
        # normalize refs (e.g. "v1.2.3" -> "refs/tags/v1.2.3") so we never
        # assume the ref value matches the metadata one.
        url = find_input_url(text, name)
        old_ref = url.split("?ref=", 1)[1].split("&", 1)[0]
        if old_ref == new_ref:
            info(f"{name}: already at {old_ref}")
            continue
        text = rewrite_pin(text, name, url, url.replace(f"?ref={old_ref}", f"?ref={new_ref}", 1))
        changed.append(f"{name}={new_ref}")

    with open(flake_nix_path, "w", encoding="utf-8") as f:
        f.write(text)

    for line in changed:  # stdout carries only bumped pins, for CI to collect.
        print(line)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
