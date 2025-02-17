{
  description = "Smoke";

  inputs = {
    flake-compat.url = github:edolstra/flake-compat;
    flake-compat.flake = false;
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/master;
    haskellTar.url = github:haskell/tar/dbf8c995153c8a80450724d9f94cf33403740c80;
    haskellTar.flake = false;
  };

  outputs =
    { self
    , flake-compat
    , flake-utils
    , nixpkgs
    , haskellTar
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      ghcVersion = lib.strings.fileContents ./ghc.version;
      ghcName = "ghc" + lib.strings.stringAsChars (c: if c == "." then "" else c) ghcVersion;
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (self: super: {
            haskell = super.haskell // {
              packages = super.haskell.packages // {
                # haskell package set from the version of GHC specified by `./ghc.version`
                ${ghcName} = super.haskell.packages.${ghcName}.override {
                  overrides = hself: hsuper: {
                    # Override tar with the patched version; see stack.yaml for details.
                    # The tests don't work.
                    tar = hsuper.callCabal2nixWithOptions "tar" haskellTar "--no-check" { };
                  } // (if super.stdenv.targetPlatform.isDarwin
                  then
                  # macOS-specific overrides:
                    {
                      # On aarch64-darwin, this creates a cycle.
                      # see https://github.com/NixOS/nixpkgs/issues/140774
                      ormolu = super.haskell.lib.overrideCabal hsuper.ormolu (drv: { enableSeparateBinOutput = false; });
                    }
                  else
                  # We don't need to override anything on Linux:
                    { });
                };
              };
            };
          })
        ];
      };

      inherit (pkgs) lib haskell;
      inherit (haskell.lib) overrideCabal justStaticExecutables doStrip;
      hsPkgs = haskell.packages.${ghcName};

      # required libraries with static linking enabled
      staticLibs = with pkgs; [
        (gmp6.override { withStatic = true; })
        (libffi.overrideAttrs (old: { dontDisableStatic = true; }))
        (libiconv.overrideAttrs (old: { enableStatic = true; enableShared = false; }))
        (openssl.override { static = true; })
        zlib.static
      ];

      smoke =
        let
          drv = hsPkgs.callCabal2nix "smoke" (pkgs.nix-gitignore.gitignoreSource [ ] ./.) { };
        in
        haskell.lib.addExtraLibraries drv staticLibs;
    in
    {
      packages.default = smoke;

      apps.default = flake-utils.lib.mkApp {
        drv = overrideCabal (justStaticExecutables (doStrip smoke)) {
          enableSharedExecutables = false;
          enableSharedLibraries = false;
        };
      };

      formatter = pkgs.nixpkgs-fmt;

      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          coreutils
          dos2unix
          findutils
          gnumake
          gnused
          nixpkgs-fmt
          yq

          # Haskell development
          hsPkgs.haskell-language-server
          hsPkgs.hlint
          hsPkgs.hpack
          hsPkgs.hspec-discover
          hsPkgs.ormolu
          stack

          # ICU
          icu
          pkg-config

          # testing
          git
          ruby
        ];
        STACK_IN_NIX_SHELL = true;
      };

      devShells.lint = pkgs.mkShell {
        buildInputs = with pkgs; [
          hsPkgs.hlint
          hsPkgs.hpack
          hsPkgs.ormolu
        ];
        STACK_IN_NIX_SHELL = true;
      };
    });
}
