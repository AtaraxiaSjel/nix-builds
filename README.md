# nix-builds

A repository for building custom NixOS derivations and caching them to Cachix and personal niks3 caches for use in my home configuration.

This streamlines the process of maintaining pre-built packages that can be quickly deployed across systems without rebuilding from source.

## Branches

- `dev` (default): main development branch.
- `release`: updated only by CI, **if and only if all packages built successfully** for the pinned `flake.lock`. If a build fails, `release` retains the last known-good lock.

Pipeline (GitHub Actions):

1. `update-flake.yml` — once a week: bumps `flake.lock`, opens an auto-merge PR.
2. `build.yml` — on every push that changes `flake.*`: builds `packages.*`, pushes them to Cachix. On success it force-updates the `release` branch; on failure it sends a Telegram notification instead.

## Release-pinned inputs

Inputs that should track a published *release* instead of a moving branch are pinned with a `?ref=<tag>` URL:

```nix
freesmlauncher = {
  url = "github:FreesmTeam/FreesmLauncher?ref=2.3.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The weekly workflow discovers them automatically (`.github/scripts/bump-input-pins.py` reads `nix flake metadata`) and bumps each pin: `github:` inputs to the repo's latest GitHub release, `git+https` inputs to the repo's newest tag — `flake.lock` alone cannot do this, because the ref lives in `flake.nix`.

Only refs that exist as a git **tag** are treated as release pins; branch pins such as `nix-cachyos-kernel`'s `?ref=release` are left untouched.

All inputs follow this repo's `nixpkgs`, so the whole repository is built against a single nixpkgs revision.

## Overlay

Everything this repo builds is exposed through a nixpkgs overlay:

```nix
# flake.nix of the consumer
inputs.nix-builds.url = "github:ataraxiasjel/nix-builds?ref=release";
```

```nix
# configuration.nix
{
  nixpkgs.overlays = [ inputs.nix-builds.overlays.default ];

  # CachyOS kernel (LTO, zen4) with its out-of-tree module set
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

  environment.systemPackages = [ pkgs.determinate-nix ];
  home.packages = [ pkgs.freesmlauncher ];
}
```

## nixpkgs pinning

`nixpkgs` points at `nixpkgs-unstable`. `determinate-nix` (nix-src) is the one exception: it keeps its own nixpkgs, because nix only builds against its own nixpkgs
