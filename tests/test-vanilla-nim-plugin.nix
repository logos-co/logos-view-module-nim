# Build a Nim Qt plugin and load it from a plain C++ Qt host.
#
# Covers the whole premise in one go: nimside's meta object survives
# QPluginLoader, its property carries a NOTIFY signal, its accessors stay out of
# the method table, and its slot dispatches through QMetaObject::invokeMethod --
# which is exactly how ui-host drives a view module.
{ pkgs, nimPlugin }:

let
  libExt = if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";
in
pkgs.stdenv.mkDerivation {
  pname = "logos-plugin-nim-vanilla-test";
  version = "0.0.1";

  src = ./host;

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.qt6.qtbase ];

  dontConfigure = true;
  dontWrapQtApps = true;

  buildPhase = ''
    runHook preBuild
    export PKG_CONFIG_PATH="${pkgs.qt6.qtbase}/lib/pkgconfig:${pkgs.qt6.qtbase.dev}/lib/pkgconfig"
    $CXX -std=c++17 -o host host.cpp \
      $(pkg-config --cflags --libs Qt6Core) \
      -F${pkgs.qt6.qtbase}/lib
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./host ${nimPlugin}/lib/vanilla_nim_plugin.${libExt}
    runHook postCheck
  '';

  installPhase = ''
    mkdir -p $out
    echo "vanilla nim plugin test passed" > $out/result.txt
  '';
}
