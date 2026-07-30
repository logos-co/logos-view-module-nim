# The nimside source tree, with our patches applied.
#
# nimside is consumed as a pinned upstream checkout plus a patch series rather
# than a vendored copy, so the delta stays a reviewable, upstreamable set of
# commits rather than a fork that quietly drifts. `patches/nimside/` is the
# output of `git format-patch` against the pinned revision; regenerate it the
# same way if the series changes.
{ pkgs, nimsideSrc, patchDir }:

pkgs.applyPatches {
  name = "nimside-patched";
  src = nimsideSrc;
  patches = builtins.map (f: "${patchDir}/${f}") (
    builtins.filter (f: pkgs.lib.hasSuffix ".patch" f) (
      builtins.attrNames (builtins.readDir patchDir)
    )
  );
}
