{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
    flake-utils.url = "github:numtide/flake-utils?ref=main";
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # tuwunel = {
    #   url = "github:matrix-construct/tuwunel?ref=main";
    #   inputs.flake-utils.follows = "flake-utils";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.attic.follows = "";
    #   inputs.cachix.follows = "";
    # };
    # elephant = {
    #   url = "github:abenz1267/elephant";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.systems.follows = "systems";
    # };
    # walker = {
    #   url = "github:abenz1267/walker";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.elephant.follows = "elephant";
    #   inputs.systems.follows = "systems";
    # };
  };
  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs { inherit system; };

        cachyosPkgs = inputs.nix-cachyos-kernel.packages.${system};
        cachyos-kernel-zen4 = cachyosPkgs.linux-cachyos-latest-lto-zen4.override {
          lto = "thin";
          processorOpt = "zen4";
          bbr3 = true;
          postPatch = ''
            substituteInPlace arch/x86/kernel/umip.c --replace-fail \
              "u16 dummy_limit = 0;" "u16 dummy_limit = 0x7F;"
          '';
        };
        cachyos-kernelPackages-zen4-patched =
          let
            helpers = pkgs.callPackage "${inputs.nix-cachyos-kernel.outPath}/helpers.nix" { };
          in
          helpers.kernelModuleLLVMOverride (pkgs.linuxKernel.packagesFor cachyos-kernel-zen4);
      in
      {
        packages = {
          inherit cachyos-kernelPackages-zen4-patched;
          # tuwunel = inputs.tuwunel.packages.${system}.default.override {
          #   features = [ "ldap" ];
          # };
          # elephant = inputs.elephant.packages.${system}.default;
          # walker = inputs.walker.packages.${system}.default;
          # obs-studio without browser support to save some space
          obs-studio = (pkgs.obs-studio.override { browserSupport = false; });
        };
        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            jq
            nix-fast-build
          ];
        };
      }
    )
    // {
      # homeManagerModules = {
      #   elephant = inputs.elephant.homeManagerModules.default;
      #   walker = inputs.walker.homeManagerModules.default;
      # };
      # nixosModules = {
      #   elephant = inputs.elephant.nixosModules.default;
      #   walker = inputs.walker.nixosModules.default;
      # };
    };
}
