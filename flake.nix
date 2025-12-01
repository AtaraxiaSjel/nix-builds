{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
    flake-utils.url = "github:numtide/flake-utils?ref=main";
    tuwunel = {
      url = "github:matrix-construct/tuwunel?ref=main";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.attic.follows = "";
      inputs.cachix.follows = "";
    };
    elephant = {
      url = "github:abenz1267/elephant";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.elephant.follows = "elephant";
      inputs.systems.follows = "systems";
    };
  };
  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs { inherit system; };
      in
      {
        packages = {
          tuwunel = inputs.tuwunel.packages.${system}.default.override {
            features = [ "ldap" ];
          };
          elephant = inputs.elephant.packages.${system}.default;
          walker = inputs.walker.packages.${system}.default;
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
      homeManagerModules = {
        elephant = inputs.elephant.homeManagerModules.default;
        walker = inputs.walker.homeManagerModules.default;
      };
      nixosModules = {
        elephant = inputs.elephant.nixosModules.default;
        walker = inputs.walker.nixosModules.default;
      };
    };
}
