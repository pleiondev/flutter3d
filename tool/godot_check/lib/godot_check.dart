/// `qa-19n`: every GLB this repository ships, opened in Godot, and the
/// numbers a second engine reads out of it compared with our own.
///
///     dart run godot_check:godot_check
///     dart run godot_check:godot_check --godot=/path/to/Godot a.glb b.glb
///
/// **Why an engine and not another validator.** `tool/validate_gltf.dart`
/// already runs the real Khronos validator over fresh exports, and
/// `compareModelDocuments` already asks whether a document survives being
/// written and read again — by *our* reader. Both are checks a file can pass
/// while still being unopenable by the program somebody actually wants to open
/// it in. The design plan's line is "the exported file opens in Godot and
/// Unity"; K2 closed on 2026-09-09 with headless Godot in CI and a manual
/// Unity/Blender checklist before release, because there is no headless Unity
/// licence to put in a workflow.
///
/// **What is compared, and what deliberately is not.** The row asks for mesh
/// and triangle counts against `compareModelDocuments`, and that is the right
/// line: those are the counts that comparison makes, and the ones two
/// independent readers can be held to. Measured against Godot 4.3 on the seven
/// committed fixtures:
///
///   * **surfaces, triangles and material names agree exactly**, on all seven;
///   * **vertex counts do not, in either direction.** Godot's importer merges
///     vertices on one file and splits them on another — `table.glb`'s legs go
///     78 → 76, `case1.glb`'s teapot goes 6768 → 7567 — so a vertex-count
///     comparison would go red on a file that is perfectly fine. Not made;
///   * **node counts do not either.** Godot folds a skin's joints into one
///     `Skeleton3D`: `case4.glb`'s 96 nodes arrive as 82, `hero.glb`'s 45 as 9.
///     Also not made;
///   * **the bounds do**, and they are the one geometric check here. Godot's
///     mesh AABB contains ours on every surface of every fixture (worst
///     violation 1.9e-9, a float32 rounding down), and on an *unskinned*
///     surface the two agree to 2.4e-7. A skinned one gets containment only:
///     Godot pads a skinned mesh's AABB to cover where the skeleton can take
///     it, which on `hero.glb`'s twenty-triangle eye patch is 2.6× the real
///     box — too loose to assert anything tighter with.
///
/// **What the first run of it found.** `case3.glb` — a file this repository
/// commits and a tutorial page asks a reader to open — carried a 33-byte
/// "PNG": a signature, an IHDR with the width and height in it, and a checksum
/// field left at zero. Its own fixture said nothing downstream decoded a pixel
/// and that "this case never exports", and the second half was not true.
/// Godot said `IHDR: CRC error`, then `Couldn't load image index '0' with its
/// given mimetype: image/png`, and dropped the texture. Nothing here had ever
/// said so, because nothing here had ever handed one of these files to a
/// decoder that was not ours.
library;

import 'package:flutter3d_core/flutter3d_core.dart';

import 'src/ask_godot.dart';
import 'src/compare.dart';
import 'src/reading.dart';

export 'src/ask_godot.dart' show GodotRefused, askGodot, flatName, godotVersion;
export 'src/compare.dart'
    show boundsTolerance, compareReadings, containmentSlack;
export 'src/reading.dart' show FileReading, SurfaceReading;

/// Every GLB this repository commits and asks somebody to open: `doc-21`'s
/// table and the tutorial's exported cases, plus the rigged sample the
/// engine's own tests load, which is the only fixture here with a skin deep
/// enough to be worth asking a second engine about.
const List<String> committedFixtures = <String>[
  'packages/flutter3d_model_mcp/test/fixtures/table.glb',
  'packages/flutter3d_model_mcp/test/fixtures/tutorial/case1.glb',
  'packages/flutter3d_model_mcp/test/fixtures/tutorial/case3.glb',
  'packages/flutter3d_model_mcp/test/fixtures/tutorial/case4.glb',
  'packages/flutter3d_model_mcp/test/fixtures/tutorial/case5.glb',
  'packages/flutter3d_model_mcp/test/fixtures/tutorial/case6.glb',
  'packages/flutter3d/test/fixtures/hero.glb',
];

/// Everything Godot and this repository's own loader disagree about across
/// [fixtures]. Empty means they agree.
///
/// Throws [GodotRefused] when Godot would not run or would not import, which
/// is a different answer from "they disagree" and is reported as one.
Future<List<String>> checkWithGodot({
  required String godot,
  List<String> fixtures = committedFixtures,
}) async {
  final theirs = await askGodot(godot, fixtures);
  final problems = <String>[];
  for (final path in fixtures) {
    final read = theirs[flatName(path)];
    if (read == null) {
      problems.add('$path: Godot never reported on it');
      continue;
    }
    problems.addAll(
      compareReadings(path.split('/').last, await readDocument(path), read),
    );
  }
  return problems;
}

/// This repository's own reading of [path] — `decodeModel`, the same entry
/// point every loader test and the modeller itself go through.
Future<FileReading> readDocument(String path) async {
  final document = await decodeModel(
    ModelLoadRequest(source: FileAssetSource(path)),
  );
  return FileReading(
    surfaces: <SurfaceReading>[
      for (final surface in document.surfaces)
        () {
          final box = surface.mesh.computeBounds();
          return SurfaceReading(
            material: surface.materialIndex == null
                ? ''
                : document.materials[surface.materialIndex!].name ?? '',
            triangles: surface.mesh.indexCount ~/ 3,
            skinned: surface.skinIndex != null,
            min: <double>[box.min.x, box.min.y, box.min.z],
            max: <double>[box.max.x, box.max.y, box.max.z],
          );
        }(),
    ],
  );
}
