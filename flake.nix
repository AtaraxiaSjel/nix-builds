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
  };
  outputs =
    {
      self,
      nixpkgs,
      nix-cachyos-kernel,
      freesmlauncher,
      determinate-nix,
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

          # FreesmLauncher, built from its latest release tag.
          freesmlauncher = freesmlauncher.packages.${system}.freesmlauncher;

          # Determinate's nix, built from its latest release tag.
          determinate-nix = determinate-nix.packages.${system}.nix;

          # OBS without browser support to save some space.
          obs-studio = pkgs.obs-studio.override { browserSupport = false; };
        };
      in
      {
        packages = {
          # Do NOT expose the full kernelPackages set here: nix-fast-build
          # traverses attrsets and would try to evaluate/build every
          # out-of-tree module in nixpkgs.
          inherit (built)
            cachyos-kernel-x86_64-v3
            cachyos-kernel-zen4
            determinate-nix
            freesmlauncher
            obs-studio
            ;
        };

        # Everything the overlay exposes, per system.
        legacyPackages = {
          # Kernel and its module set. The attribute names follow
          # xddxdd/nix-cachyos-kernel, so `pkgs.cachyosKernels.*` works the
          # same way for both overlays.
          cachyosKernels = {
            linux-cachyos-latest-lto-x86_64-v3 = built.cachyos-kernel-x86_64-v3;
            linux-cachyos-latest-lto-zen4 = built.cachyos-kernel-zen4;
            linuxPackages-cachyos-latest-lto-x86_64-v3 = built.kernelPackages-x86_64-v3;
            linuxPackages-cachyos-latest-lto-zen4 = built.kernelPackages-zen4;
          };

          inherit (built) determinate-nix freesmlauncher obs-studio;
        };

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
        default =
          final: prev:
          let
            system = final.stdenv.hostPlatform.system;
          in
          {
            inherit (self.legacyPackages.${system})
              cachyosKernels
              freesmlauncher
              determinate-nix
              obs-studio
              ;
          };
      };
    };
}
