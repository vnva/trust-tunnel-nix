{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          trusttunnel = pkgs.callPackage ./pkgs/trusttunnel.nix { };
          default = self.packages.${system}.trusttunnel;
        }
      );

      overlays = {
        default = final: prev: {
          trusttunnel = final.callPackage ./pkgs/trusttunnel.nix { };
        };
      };

      nixosModules = {
        server = import ./modules/server.nix;
        client = import ./modules/client.nix;
      };
    };
}
