{
  description = "The Nim view-module backend — builds Logos modules as Qt 6 plugins written in Nim";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    nixpkgs.follows = "logos-nix/nixpkgs";

    # The Qt plugin backend. We use its logos_replica_factory() for the
    # host-side half of a view module; the backend half is ours.
    logos-plugin-qt.url = "github:logos-co/logos-plugin-qt";

    # nimside: the meta object compiler. Pinned upstream plus the patch series
    # in patches/nimside -- see lib/nimside.nix.
    nimside = {
      url = "github:seaqt/nimside/38406061afd5d24a57d8f6cb8cdcc5930bb67bc8";
      flake = false;
    };

    # nim-seaqt: the Qt bindings. The qt-6.4 branch is what nimside itself is
    # developed against, and seaqt bindings are forward-compatible within a
    # major version, so it is correct for the workspace's Qt 6.9.
    nim-seaqt = {
      url = "github:seaqt/nim-seaqt/e27f4568e7c5b77e500fda6cb99e58b3af82a17c";
      flake = false;
    };

    # Only needed to run nimside's own test suite.
    nim-unittest2 = {
      url = "github:status-im/nim-unittest2";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, logos-plugin-qt, nimside, nim-seaqt, nim-unittest2, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });

      rawLib = import ./lib {
        inherit nixpkgs;
        inherit (nixpkgs) lib;
        backendRoot = ./.;
      };

      # Pre-fill the sources so callers only supply their own module.
      wrappedLib = rawLib // {
        # Backend entry point with nimside/nim-seaqt already resolved, so
        # logos-module-builder passes only the module.
        buildPlugin = args:
          let pkgs = args.pkgs; in
          rawLib.buildPlugin (args // {
            nimside = rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; };
            nimSeaqt = nim-seaqt;
          });

        mkNimUiPlugin = args:
          let pkgs = args.pkgs; in
          rawLib.mkNimUiPlugin.build (args // {
            nimside = rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; };
            nimSeaqt = nim-seaqt;
            logosPluginQt = logos-plugin-qt.packages.${pkgs.system}.cmake-module;
          });

        mkNimPlugin = args:
          let pkgs = args.pkgs; in
          rawLib.mkNimPlugin.build (args // {
            nimside = rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; };
            nimSeaqt = nim-seaqt;
          });
      };

      # The sources this backend is pinned to, so logos-module-builder can
      # resolve them once and inject them, the way it injects the SDK into
      # logos-plugin-qt rather than letting the backend fetch its own.
      backendSources = { pkgs }: {
        nimside = rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; };
        nimSeaqt = nim-seaqt;
      };
    in
    {
      lib = wrappedLib;
      rawLib = rawLib;
      inherit backendSources;

      packages = forAllSystems ({ pkgs, ... }: {
        # nimside's .rep -> Nim generator, exposed so it can be run by hand.
        rep2nim = (wrappedLib.mkNimPlugin {
          inherit pkgs;
          src = ./tests/vanilla-nim-plugin;
          name = "vanilla_nim";
        }).rep2nim;

        nimside-patched = rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; };

        default = self.packages.${pkgs.system}.rep2nim;
      });

      checks = forAllSystems ({ pkgs, ... }: {
        # A Nim Qt plugin with no Logos dependencies at all, loaded through
        # QPluginLoader by a plain C++ host.
        vanilla-nim-plugin = import ./tests/test-vanilla-nim-plugin.nix {
          inherit pkgs;
          nimPlugin = wrappedLib.mkNimPlugin {
            inherit pkgs;
            src = ./tests/vanilla-nim-plugin;
            name = "vanilla_nim";
          };
        };

        # nimside's own suite, with our patches applied.
        nimside-tests = import ./tests/test-nimside.nix {
          inherit pkgs;
          nimside = rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; };
          nimSeaqt = nim-seaqt;
          unittest2 = nim-unittest2;
          common = rawLib.common;
        };
      });

      devShells = forAllSystems ({ pkgs, ... }:
        let shell = wrappedLib.devShellInputs pkgs;
        in {
          default = pkgs.mkShell {
            inherit (shell) nativeBuildInputs buildInputs;
            shellHook = ''
              ${shell.shellHook}
              echo "Logos Nim plugin backend"
              echo "  nimside  (patched): ${rawLib.patchedNimside { inherit pkgs; nimsideSrc = nimside; }}"
              echo "  nim-seaqt         : ${nim-seaqt}"
            '';
          };
        }
      );
    };
}
