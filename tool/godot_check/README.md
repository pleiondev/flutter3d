# godot_check

Opens every GLB this repository commits in Godot and compares what a second
engine reads out of it with what our own loader put in (`qa-19n`).

```
dart run godot_check:godot_check
dart run godot_check:godot_check --godot=/path/to/Godot a.glb b.glb
```

Godot is found by `--godot=`, then `$GODOT`, then the PATH. `.github/workflows/ci.yml`
downloads a pinned 4.3 release into the `godot` job and caches it on the
version, the same way `glslang` and the Khronos validator are fetched.

The doc comment on `lib/godot_check.dart` explains why this uses an engine
rather than another validator, what is compared, what deliberately is not, and
the numbers behind each of those decisions. In short, a file can pass both
`tool/validate_gltf.dart` and `compareModelDocuments` and still fail to open in
the program somebody wants to open it in. The first run of this tool found
such a case: a committed tutorial GLB carrying a 33-byte "PNG" with a zeroed
checksum.

## The manual half: Unity and Blender before a release

K2 closed on 2026-09-09 with headless Godot in CI and a manual checklist for
the other two programs. There is no headless Unity licence to put in a
workflow, and Blender's importer is a Python add-on rather than a command. This
section is that checklist. It is a release step, not a CI step: run it once
before a phase-1 release, against the same files this command checks.

For each of `table.glb` and the tutorial's `case1`, `case3`, `case4`, `case5`
and `case6` GLBs:

1. Unity: drag the file into a project's `Assets/`. The import must raise
   no error in the console. Open the imported prefab: the mesh count and the
   material names must match what `dart run godot_check:godot_check` prints
   for that file, and `case4`/`case5` must arrive with an `Animator` and their
   clips. A skinned mesh that arrives unbound, or a material that arrives
   magenta, is a finding.
2. Blender: `File ▸ Import ▸ glTF 2.0`. Check the same three things: no error
   in the status bar, the object and material counts agree, and the animation
   shows up in the Dope Sheet for the two files that have one. Blender is also
   the only one of the three that reports a texture problem: an image that
   fails to decode arrives as a pink checkerboard instead of silently as white.
3. Write what you saw into the release notes, with the versions of both
   programs next to it. Without the versions, nobody can repeat the check.

If any of the three disagrees with what this command prints, treat the file as
the problem, not the importer. When three readers agree with each other and
disagree with us, that is not a coincidence.
