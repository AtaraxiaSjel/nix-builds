{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    freesmlauncher = {
      url = "github:FreesmTeam/FreesmLauncher?ref=2.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate-nix = {
      url = "github:DeterminateSystems/nix-src?ref=v3.23.3";
      inputs.nixpkgs-regression.url = "github:nix-systems/empty";
      inputs.nixpkgs-23-11.url = "github:nix-systems/empty";
      inputs.flake-parts.url = "github:nix-systems/empty";
      inputs.git-hooks-nix.url = "github:nix-systems/empty";
    };
    # Personal packages
    arkivist = {
      url = "git+https://git.ataraxiadev.com/ataraxiadev/arkivist?ref=refs/tags/v0.5.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cadence = {
      url = "git+https://git.ataraxiadev.com/ataraxiadev/cadence?ref=refs/tags/v0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quadpin = {
      url = "git+https://git.ataraxiadev.com/ataraxiadev/quadpin?ref=refs/tags/v1.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      arkivist,
      cadence,
      determinate-nix,
      freesmlauncher,
      nix-cachyos-kernel,
      quadpin,
      ...
    }:
    let
      forAllSystems =
        f:
        builtins.foldl'
          (
            acc: system:
            acc // (nixpkgs.lib.mapAttrs (key: value: (acc.${key} or { }) // { ${system} = value; }) (f system))
          )
          { }
          [
            "x86_64-linux"
            "aarch64-linux"
          ];
    in
    forAllSystems (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        kernelPackages =
          kernel:
          let
            helpers = pkgs.callPackage "${nix-cachyos-kernel.outPath}/helpers.nix" { };
          in
          helpers.kernelModuleLLVMOverride (pkgs.linuxKernel.packagesFor kernel);

        built = {
          cachyos-kernel-x86_64-v3 =
            nix-cachyos-kernel.packages.${system}.linux-cachyos-latest-lto-x86_64-v3.override
              {
                bbr3 = true;
              };
          cachyos-kernel-zen4 = nix-cachyos-kernel.packages.${system}.linux-cachyos-latest-lto-zen4.override {
            bbr3 = true;
            postPatch = ''
              substituteInPlace arch/x86/kernel/umip.c --replace-fail \
                "u16 dummy_limit = 0;" "u16 dummy_limit = 0x7F;"
            '';
          };

          # The kernel together with its out-of-tree module set.
          # `kernelModuleLLVMOverride` fixes the compilation of some
          # out-of-tree modules with Clang+LTO kernels.
          kernelPackages-x86_64-v3 = kernelPackages built.cachyos-kernel-x86_64-v3;
          kernelPackages-zen4 = kernelPackages built.cachyos-kernel-zen4;

          inherit (arkivist.packages.${system}) arkivist;
          inherit (cadence.packages.${system}) cadence;
          inherit (freesmlauncher.packages.${system}) freesmlauncher;
          inherit (quadpin.packages.${system}) quadpin;
          # The package attribute name differs from the input name here.
          determinate-nix = determinate-nix.packages.${system}.nix;

          # OBS without browser support to save some space.
          obs-studio = pkgs.obs-studio.override { browserSupport = false; };
        };

        # The package set exposed as flake `packages`. The raw kernelPackages
        # sets stay out of it: nix-fast-build traverses attrsets and would
        # try to evaluate/build every out-of-tree module in nixpkgs.
        packages = {
          inherit (built)
            arkivist
            cachyos-kernel-x86_64-v3
            cachyos-kernel-zen4
            cadence
            determinate-nix
            freesmlauncher
            obs-studio
            quadpin
            ;
        };

        # Everything the overlay exposes, per system: the packages plus the
        # kernel/module set.
        legacyPackages = packages // {
          cachyosKernels = {
            linux-cachyos-latest-lto-x86_64-v3 = built.cachyos-kernel-x86_64-v3;
            linux-cachyos-latest-lto-zen4 = built.cachyos-kernel-zen4;
            linuxPackages-cachyos-latest-lto-x86_64-v3 = built.kernelPackages-x86_64-v3;
            linuxPackages-cachyos-latest-lto-zen4 = built.kernelPackages-zen4;
          };
        };
      in
      {
        inherit packages legacyPackages;

        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            jq
            niks3
            nix-fast-build
          ];
        };
      }
    )
    // {
      overlays = {
        # All packages are fixed derivations built by this repository, so
        # they are *not* re-derived against the consumer's nixpkgs.
        #
        # NOTE: the attributes are inherited explicitly on purpose. Simply
        # returning `self.legacyPackages.<system>` wholesale (or shuffling
        # it via mapAttrs/removeAttrs) makes the consumer's stdenv booter
        # recurse infinitely.
        default = final: prev: {
          inherit (self.legacyPackages.${final.stdenv.hostPlatform.system})
            arkivist
            cachyosKernels
            cadence
            determinate-nix
            freesmlauncher
            obs-studio
            quadpin
            ;
        };
      };
    };
}
