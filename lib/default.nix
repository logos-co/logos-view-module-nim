{ nixpkgs, lib, backendRoot }:

let
  common = import ./common.nix { inherit lib; };
  mkNimPlugin = import ./mkNimPlugin.nix { inherit lib common; };
  mkNimUiPlugin = import ./mkNimUiPlugin.nix { inherit lib common mkNimPlugin; };
in
{
  inherit common mkNimPlugin mkNimUiPlugin;

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
