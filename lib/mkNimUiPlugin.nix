# Assemble a Logos `ui_qml` view module whose backend is a Nim Qt plugin.
#
# An installed view module is a directory:
#
#   metadata.json
#   <name>_plugin.<ext>            backend, loaded by ui-host in its own process
#   <name>_replica_factory.<ext>   host-side half, loaded by LogosQmlBridge
#   qml/…                          the view
#
# The backend comes from mkNimPlugin. The factory is the stock one from
# logos-plugin-qt, built straight from the .rep -- it has to be C++ because
# LogosViewReplicaFactory is a Q_DECLARE_INTERFACE and nimside has no multiple
# inheritance, but nothing about it is Nim-specific.
#
# When no .rep is given the factory is omitted entirely: ui-host dynamic-remotes
# a plugin that implements no LogosViewPlugin, and LogosQmlBridge acquires a
# dynamic replica when it finds no factory. That path needs no C++ at all.
{ lib, common, mkNimPlugin }:

{
  build = {
    pkgs,
    src,
    config,          # parsed metadata.json
    configFile,
    nimside,
    nimSeaqt,
    logosPluginQt,   # cmake/ dir providing logos_replica_factory()
    entryPoint ? null,
    repFile ? null,
    generatedModule ? null,
    implModule ? null,
    viewDir ? "qml",
    extraNimFlags ? [ ],
  }:
  let
    libExt = common.getLibExtension pkgs;
    name = config.name;

    backend = mkNimPlugin.build {
      inherit pkgs src nimside nimSeaqt repFile generatedModule implModule extraNimFlags;
      inherit name;
      entryPoint = if entryPoint != null then entryPoint else "nim/${name}.nim";
    };

    # The stock typed replica factory, straight from the .rep.
    factory = pkgs.stdenv.mkDerivation {
      pname = "${name}-replica-factory";
      version = config.version or "0.1.0";
      inherit src;
      nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.qt6.wrapQtAppsNoGuiHook ];
      buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtremoteobjects pkgs.qt6.qtdeclarative ];
      dontWrapQtApps = true;
      dontUseCmakeConfigure = true;

      buildPhase = ''
        runHook preBuild

        # A CMakeLists that does nothing but ask logos-plugin-qt for the
        # factory -- there is no C++ plugin here to hang it off.
        cat > CMakeLists.txt <<'EOF'
        cmake_minimum_required(VERSION 3.14)
        project(${name}ReplicaFactory LANGUAGES CXX)
        set(CMAKE_CXX_STANDARD 17)
        set(CMAKE_CXX_STANDARD_REQUIRED ON)
        include("${logosPluginQt}/share/cmake/LogosModule/LogosModule.cmake")
        logos_replica_factory(NAME ${name} REP_FILE ${repFile})
        EOF

        cmake -S . -B build -GNinja
        cmake --build build

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 build/modules/${name}_replica_factory.${libExt} \
          $out/lib/${name}_replica_factory.${libExt}
        runHook postInstall
      '';
    };

    iconInstall = lib.optionalString (config ? icon && config.icon != null) ''
      install -Dm644 ${src}/${config.icon} $out/lib/${config.icon}
    '';
  in
  pkgs.runCommand "logos-${name}-module" { } ''
    mkdir -p $out/lib

    cp ${backend}/lib/${name}_plugin.${libExt} $out/lib/
    ${lib.optionalString (repFile != null) ''
      cp ${factory}/lib/${name}_replica_factory.${libExt} $out/lib/
    ''}
    cp ${configFile} $out/lib/metadata.json
    ${iconInstall}

    if [ -d "${src}/${viewDir}" ]; then
      mkdir -p "$out/lib/${viewDir}"
      cp -r "${src}/${viewDir}/." "$out/lib/${viewDir}/"
    else
      echo "error: no view directory at ${viewDir}" >&2
      exit 1
    fi

    # Qt caches composite QML types process-globally, keyed by (name, uri), so
    # two modules shipping a same-named .qml cross-match without a per-module
    # uri. logos-module-builder generates this for its own modules; do the same.
    if [ ! -f "$out/lib/${viewDir}/qmldir" ]; then
      echo "module com.logos.module.${name}" > "$out/lib/${viewDir}/qmldir"
    fi

    # Both hosts pick the backend as the alphabetically first shared library in
    # the directory, so "<name>_plugin" must sort before
    # "<name>_replica_factory". Assert it rather than trusting the alphabet.
    first=$(cd $out/lib && ls *.${libExt} | sort | head -1)
    if [ "$first" != "${name}_plugin.${libExt}" ]; then
      echo "error: backend is not the first shared library: $first" >&2
      exit 1
    fi
  '' // { inherit backend factory; };
}
