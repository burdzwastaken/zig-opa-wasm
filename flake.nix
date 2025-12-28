{
  description = "zig-opa-wasm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # nixpkgs wasmer is broken :<
        wasmer = pkgs.stdenv.mkDerivation rec {
          pname = "wasmer";
          version = "6.1.0";

          src = pkgs.fetchurl {
            url = "https://github.com/wasmerio/wasmer/releases/download/v${version}/wasmer-linux-amd64.tar.gz";
            sha256 = "1hg30nlhv37bj5y7pmnjlqd1jgimfsrrn2lz6d4c8migy02d5q2j";
          };

          sourceRoot = ".";

          installPhase = ''
            mkdir -p $out/bin $out/lib $out/include
            cp -r bin/* $out/bin/ || true
            cp -r lib/* $out/lib/ || true
            cp -r include/* $out/include/ || true
          '';

          meta = {
            description = "Universal WebAssembly Runtime";
            homepage = "https://wasmer.io";
          };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.go
            pkgs.open-policy-agent
            pkgs.zig
            pkgs.zls
            wasmer
          ];

          WASMER_DIR = "${wasmer}";

          shellHook = ''
            echo "zig-opa-wasm development environment"
            echo ""
            echo "  go:     $(go version)"
            echo "  opa:    $(opa version | grep '^Version:' | cut -d' ' -f2)"
            echo "  wasmer: $(wasmer --version 2>/dev/null | cut -d' ' -f2 || echo 'binary')"
            echo "  zig:    $(zig version)"
            echo "  zls:    $(zls --version)"
            echo ""
          '';
        };
      }
    );
}
