# Build a Qt plugin whose implementation is Nim.
#
# The output is an ordinary Qt plugin -- `qt_plugin_instance` plus the platform's
# plugin-metadata section -- so `QPluginLoader` loads it with no idea that it is
# not C++. nimside supplies the meta object that `moc` would otherwise generate,
# and nim-seaqt the Qt bindings underneath.
{ lib, common }:

{
  # Build the plugin from an already-written Nim entry point.
  #
  #   src         source tree
  #   name        module name; the output is <name>_plugin.<ext>
  #   entryPoint  path to the Nim file, relative to src
  #   nimside     patched nimside source tree
  #   nimSeaqt    nim-seaqt source tree (a `qt-6.x` branch)
  #   repFile     optional .rep; when given, rep2nim generates the qobject
  #               glue from it before compiling
  #   generatedModule  where that glue lands, as a module name next to the
  #               entry point. Kept separate from the entry point so the
  #               generated file can be overwritten on every build while the
  #               hand-written Q_PLUGIN_METADATA survives.
  #   implModule  module the generated glue includes for the slot bodies
  build = {
    pkgs,
    src,
    name,
    entryPoint ? "nim/${name}.nim",
    nimside,
    nimSeaqt,
    repFile ? null,
    generatedModule ? null,
    implModule ? null,
    extraNimFlags ? [ ],
  }:
  let
    libExt = common.getLibExtension pkgs;
    pluginFile = common.getPluginFilename pkgs name;
    implMod = if implModule != null then implModule else "${name}_impl";
    genMod = if generatedModule != null then generatedModule else "${name}_rep";
    nimDir = builtins.dirOf entryPoint;

    # rep2nim ships in nimside; build it once rather than per-module.
    rep2nim = pkgs.stdenv.mkDerivation {
      pname = "rep2nim";
      version = "0.1.0";
      src = nimside;
      nativeBuildInputs = [ pkgs.nim ];
      dontConfigure = true;
      buildPhase = ''
        runHook preBuild
        export HOME=$TMPDIR/home && mkdir -p "$HOME"
        nim c --hints:off --warnings:off -d:release \
          --nimcache:$TMPDIR/nc --path:$PWD/src \
          --out:$TMPDIR/rep2nim src/rep2nim.nim
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -Dm755 $TMPDIR/rep2nim $out/bin/rep2nim
        runHook postInstall
      '';
    };
  in
  pkgs.stdenv.mkDerivation {
    pname = "${name}-nim-plugin";
    version = "0.1.0";

    inherit src;

    nativeBuildInputs = common.commonNativeBuildInputs pkgs
      ++ lib.optional (repFile != null) rep2nim;
    buildInputs = common.commonBuildInputs pkgs;

    dontConfigure = true;

    # This is a plugin, not an application: nothing to wrap.
    dontWrapQtApps = true;

    # Qt finds a plugin's metadata through a dedicated section; stripping can
    # drop it on Mach-O, which turns into an unhelpful "not a plugin" at load.
    dontStrip = true;

    buildPhase = ''
      runHook preBuild

      # Nim wants somewhere to put its caches, and nimside's Q_PLUGIN_METADATA
      # macro *writes* a pluginRegistration.cpp into the nimcache directory at
      # compile time, so that path has to be writable too.
      export HOME=$TMPDIR/home && mkdir -p "$HOME"
      export PKG_CONFIG_PATH="${common.pkgConfigPath pkgs}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
      echo "Qt6Core $(pkg-config --modversion Qt6Core) via pkg-config"

      ${lib.optionalString (repFile != null) ''
        echo "rep2nim: ${repFile} -> ${nimDir}/${genMod}.nim"
        rep2nim ${repFile} --out:${nimDir}/${genMod}.nim --impl:${implMod}
      ''}

      nim c \
        --nimcache:$TMPDIR/nimcache \
        --path:${nimside}/src \
        --path:${nimSeaqt} \
        ${lib.escapeShellArgs (common.nimQtFlags pkgs)} \
        ${lib.escapeShellArgs extraNimFlags} \
        -d:release --hints:off \
        --out:$TMPDIR/${pluginFile} \
        ${entryPoint}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 $TMPDIR/${pluginFile} $out/lib/${pluginFile}
      ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
        ${pkgs.darwin.cctools}/bin/install_name_tool -id \
          "@rpath/${pluginFile}" "$out/lib/${pluginFile}"
      ''}
      runHook postInstall
    '';

    passthru = { inherit rep2nim libExt pluginFile; };

    meta = {
      description = "Qt plugin implemented in Nim (nimside meta object + nim-seaqt bindings)";
      platforms = lib.platforms.unix;
    };
  };
}
