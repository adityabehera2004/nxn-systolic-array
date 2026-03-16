{
  description = "NxN Systolic Array";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python3
            python3Packages.numpy
            python3Packages.matplotlib
            iverilog
            yosys
            gnumake
          ];

          shellHook = ''
            export PS1="[nix] $PS1"
            echo "$(python3 --version)"
            echo "NumPy $(python3 -c 'import numpy; print(numpy.__version__)')"
            echo "Matplotlib $(python3 -c 'import matplotlib; print(matplotlib.__version__)')"
            echo "$(iverilog -V 2>&1 | head -1)"
            echo "$(yosys --version | head -1)"
            echo "$(make --version | head -1)"
          '';
        };
      }
    );
}
