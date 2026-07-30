{ nixpkgs, lib, backendRoot }:

let
  common = import ./common.nix { inherit lib; };
  mkNimPlugin = import ./mkNimPlugin.nix { inherit lib common; };
  mkNimUiPlugin = import ./mkNimUiPlugin.nix { inherit lib common mkNimPlugin; };
in
{
  inherit common mkNimPlugin mkNimUiPlugin;

  # The entry point logos-module-builder calls. Produces only the plugin
  # library: the builder owns everything downstream -- the replica factory, the
  # installed layout, lgx, the standalone app, tests -- exactly as it does for a
  # C++ backend.
  #
  #   config   parsed metadata.json; codegen.nim carries this backend's settings
  #   nimside  patched nimside tree, nimSeaqt the bindings
  #
  # Returns: derivation with lib/<name>_plugin.{so,dylib}
  buildPlugin = { pkgs, src, config, nimside, nimSeaqt, extraNimFlags ? [ ] }:
    let
      cfg = (config.codegen or {}).nim or {};
    in
    mkNimPlugin.build {
      inherit pkgs src nimside nimSeaqt extraNimFlags;
      name = config.name;
      entryPoint = cfg.entry or "nim/${config.name}_plugin.nim";
      repFile = cfg.rep or null;
      implModule = cfg.impl or null;
      generatedModule = cfg.generated or null;
    };

  patchedNimside = { pkgs, nimsideSrc }:
    import ./nimside.nix {
      inherit pkgs nimsideSrc;
      patchDir = backendRoot + "/patches/nimside";
    };

  devShellInputs = pkgs: {
    nativeBuildInputs = common.commonNativeBuildInputs pkgs;
    buildInputs = common.commonBuildInputs pkgs;
    shellHook = ''
      export PKG_CONFIG_PATH="${common.pkgConfigPath pkgs}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    '';
  };
}
