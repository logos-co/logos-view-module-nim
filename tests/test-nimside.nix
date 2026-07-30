# Run nimside's own suite against the patched tree, so our patch series stays
# honest about not breaking upstream.
{ pkgs, nimside, nimSeaqt, unittest2, common }:

pkgs.stdenv.mkDerivation {
  pname = "nimside-tests";
  version = "0.1.0";

  src = nimside;

  nativeBuildInputs = common.commonNativeBuildInputs pkgs;
  buildInputs = common.commonBuildInputs pkgs;

  dontConfigure = true;
  dontWrapQtApps = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home && mkdir -p "$HOME"
    export PKG_CONFIG_PATH="${common.pkgConfigPath pkgs}"

    nim r --hints:off --warnings:off \
      --nimcache:$TMPDIR/nc \
      --path:$PWD/src --path:${nimSeaqt} --path:${unittest2} \
      ${pkgs.lib.escapeShellArgs (common.nimQtFlags pkgs)} \
      tests/test_all.nim

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out
    echo "nimside tests passed" > $out/result.txt
  '';
}
