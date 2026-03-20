{
  description = "SCIP-based code intelligence for Nix files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "cog-nix";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/bin $out/lib
            cp -r lib/* $out/lib/
            cp bin/cog-nix $out/bin/cog-nix
            chmod +x $out/bin/cog-nix
          '';

          postFixup = ''
            wrapProgram $out/bin/cog-nix \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nix ]}
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.nix ];
        };
      }
    );
}
