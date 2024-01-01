{
  description = "akkoma service package override";

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in rec {
      formatter = pkgs.alejandra;

      nixosModules.default = {
        config,
        lib,
        pkgs,
        ...
      }: {
        config.services.akkoma.package = pkgs.akkoma.overrideAttrs {
          src = self;
        };
      };
    });
}
