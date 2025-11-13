{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils?ref=main";
    tuwunel = {
      url = "github:matrix-construct/tuwunel?ref=main";
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system: {
      packages.default = inputs.tuwunel.packages.${system}.default.override {
        features = [ "ldap" ];
      };
    });
}
