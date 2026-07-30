# Shared bits for the Nim plugin backend.
{ lib }:

rec {
  # Nim's own naming would give us `lib<name>.dylib`; both hosts pick a view
  # module's backend as the alphabetically first shared library in the install
  # directory, so the name is not cosmetic and we always pass --out: explicitly.
  getLibExtension = pkgs: if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";

  getPluginFilename = pkgs: name: "${name}_plugin.${getLibExtension pkgs}";

  # nim-seaqt finds Qt purely through pkg-config (`gorge("pkg-config --cflags
  # Qt6Core")` at Nim compile time). On nixpkgs the .pc files live in the MAIN
  # output, not -dev, so the usual pkg-config setup hook does not find them.
  pkgConfigPath = pkgs:
    lib.concatStringsSep ":" [
      "${pkgs.qt6.qtbase}/lib/pkgconfig"
      "${pkgs.qt6.qtbase.dev}/lib/pkgconfig"
    ];

  # Two flags nim-seaqt needs on Darwin that its own docs do not mention:
  #
  #  -F<qtbase>/lib   nixpkgs builds Qt as frameworks, and `pkg-config --cflags`
  #                   emits only -I, so <QtCore/qglobal.h> does not resolve when
  #                   Nim compiles the generated C++ shims.
  #  -lc++            Nim drives the link with `clang`, not `clang++`, even
  #                   though the shims are C++, so the C++ runtime is missing.
  #
  # The -F is harmless elsewhere; -lc++ is Darwin-only (Linux gets libstdc++
  # through the usual wrapper).
  nimQtFlags = pkgs:
    [ "--passC:-F${pkgs.qt6.qtbase}/lib" ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin "--passL:-lc++";

  commonNativeBuildInputs = pkgs: [
    pkgs.nim
    pkgs.pkg-config
  ];

  commonBuildInputs = pkgs: [
    pkgs.qt6.qtbase
  ];
}
