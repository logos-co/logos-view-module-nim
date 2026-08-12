# logos-view-module-nim

The Nim backend for Logos modules: builds a module's Qt plugin from Nim instead
of C++, as a sibling to [`logos-plugin-qt`](https://github.com/logos-co/logos-plugin-qt).

The output is an ordinary Qt plugin. `ui-host` loads it with `QPluginLoader` and
drives it through the meta-object system, with no idea it is not C++ —
[`nimside`](https://github.com/seaqt/nimside) supplies the meta object that
`moc` would otherwise generate, and [`nim-seaqt`](https://github.com/seaqt/nim-seaqt)
the Qt bindings underneath.

## What a module looks like

```
metadata.json
nim_counter.rep              the interface, and its single definition
nim/nim_counter_impl.nim     plain Nim procs: the whole hand-written backend
nim/nim_counter_plugin.nim   entry point; Q_PLUGIN_METADATA and nothing else
qml/Main.qml
```

`rep2nim` (shipped in nimside) generates the `qobject:` block from the `.rep`,
and `logos_replica_factory()` (in logos-plugin-qt) builds the typed replica QML
talks to from the *same* `.rep` — so the two sides cannot drift.

See `repos/logos-nim-ui-example` for a complete one.

## Two shapes

**With a `.rep`** you get the stock typed replica: from QML the module is
indistinguishable from a C++ one. This is the recommended shape.

**Without one**, `ui-host` dynamic-remotes the plugin and `LogosQmlBridge`
acquires a dynamic replica. No C++ is involved anywhere, at the cost of QML
seeing a runtime-built meta object.

## Why the patches

`patches/nimside/` is a `git format-patch` series against the pinned nimside
revision, applied in `lib/nimside.nix`. Keeping it as patches rather than a
vendored fork means the delta stays reviewable and upstreamable. It currently
carries three changes:

1. property accessors are no longer published as slots, matching `moc` — they
   were showing up on QtRemoteObjects replicas and in QML's property cache;
2. `qproperty(write = true, notify = true)` no longer reads as `false` — the
   pragma is parsed untyped, so `true` arrives as an identifier and `boolVal`
   quietly returned false for it, silently dropping the setter and the notify
   signal;
3. `rep2nim` itself.

## Platform notes

nim-seaqt locates Qt through `pkg-config`, and on nixpkgs the `.pc` files live
in the **main** output rather than `-dev`. Two flags are also needed that
nim-seaqt's own docs do not mention, both set by `lib/common.nix`:

* `--passC:-F<qtbase>/lib` — nixpkgs builds Qt as frameworks and
  `pkg-config --cflags` emits only `-I`, so `<QtCore/qglobal.h>` does not
  resolve when Nim compiles the generated C++ shims;
* `--passL:-lc++` — Nim drives the link with `clang`, not `clang++`, even though
  those shims are C++.
