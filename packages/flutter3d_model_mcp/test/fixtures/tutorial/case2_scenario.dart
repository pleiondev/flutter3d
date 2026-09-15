/// Case 2 — "A vase from a profile": what both `tool/make_case2_fixtures.dart`
/// (which writes the fixtures beside this file) and
/// `tutorial_scenarios_test.dart` (which drives it against a live
/// [ModelSession]) need to agree on.
///
/// **Journal-replayable from a cold project now, closing `tut-05`.**
/// [Extrude], [LoopCut] and [TransformElements] all act on "whatever is
/// currently selected", and selecting mesh elements is [ModelSession.select]
/// — which used to assign [ModelHistory.selection] directly, not something
/// [CommandJournal] could replay, and this was the first case whose edits
/// actually depended on that missing half at *mesh*-element level (`tut-05`,
/// see `doc/modeler-tutorial-gaps.md`). `select` now runs a real,
/// non-mutating `SelectElements` command through [ModelHistory.run], so a
/// cold `CommandJournal.replay` of this case's own `.jsonl` rebuilds it the
/// same way case 1's own journal rebuilds that case — [runCase2Scenario]
/// still drives a live [session] exactly the way a person clicking through
/// the app, or an agent calling `select` then `run` over MCP, actually
/// would; a crash-recovery replay of the file it writes now reaches the same
/// place.
///
///     dart test test/tutorial_scenarios_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show ArrayModifier, MirrorModifier;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:vector_math/vector_math.dart';

/// A profile in the (radius, height) half-plane, bottom to top: starts on
/// the axis, flares into a belly, waists in, flares again at the shoulder
/// and narrows to an open neck — the same "glass" shape
/// `commands_test.dart`'s own `glass()` fixture uses, stretched into
/// something that reads as a vase rather than a tumbler.
List<Vector2> vaseProfile() => <Vector2>[
  Vector2(0.0, 0.0),
  Vector2(0.32, 0.0),
  Vector2(0.38, 0.12),
  Vector2(0.34, 0.32),
  Vector2(0.22, 0.5),
  Vector2(0.30, 0.72),
  Vector2(0.24, 0.92),
  Vector2(0.26, 1.0),
];

/// A 64×64 truecolour PNG header the way `image_dimensions_test.dart`'s own
/// `_png` helper builds one — the fewest bytes a real PNG needs, not a real
/// encoder's output, since nothing downstream of [AddImage] in this case
/// decodes a pixel (`imageDimensions` only reads the header, and this case
/// never exports, so no GLB writer ever reaches for the pixels either).
Uint8List stubGlazeTexture() {
  final bytes = Uint8List(33);
  bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void be32(int offset, int value) {
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }

  be32(8, 13);
  bytes.setAll(12, <int>[0x49, 0x48, 0x44, 0x52]);
  be32(16, 64);
  be32(20, 64);
  bytes.setAll(24, <int>[8, 6, 0, 0, 0]);
  return bytes;
}

/// Every step case 2's own page (`cloud/server/content/learn/modeler/
/// 02-vase-from-a-profile.md`) walks through, run against [session].
///
/// **The two `session.select` calls are the exact steps `tut-05` used to
/// name as unrecoverable from a `.jsonl` alone** — a person or an agent
/// driving the session live always makes them anyway, and now a cold
/// `CommandJournal.replay` of this case's own journal reaches the same
/// place too, the fix `tutorial_scenarios_test.dart`'s own first case-2
/// test now checks for directly.
///
/// **No `bevel` here, and that is `tut-04`.** The plan's own case list asks
/// for "extrude/loop cut/bevel"; `flutter3d_mesh` has real `bevelEdges`/
/// `bevelVertices` functions, but no `ModelCommand` wraps either one —
/// `apps/flutter3d_modeler/lib/src/ui/tools.dart`'s own comment already
/// says so ("Inset, bevel and merge are" not tools) — so this scenario
/// exercises extrude and loop cut only, honestly, rather than reaching past
/// the mesh package into test-only scaffolding to fake a "bevel" command
/// that does not exist at this layer.
void runCase2Scenario(ModelSession session) {
  void must(Answer answer, String step) {
    if (!answer.did) throw StateError('$step refused: ${answer.says}');
  }

  must(
    session.run(
      AddLathe(profile: vaseProfile(), segments: 12, shapeName: 'vase'),
    ),
    'addLathe',
  );
  must(session.run(const BakeToMesh(1)), 'bakeToMesh');

  // The rim: the topmost ring of side faces (61..72 on this exact profile
  // and segment count — see `tool/make_case2_fixtures.dart`'s own
  // exploration notes if this ever needs re-deriving). Pulled out along
  // its own normal to flare the lip.
  must(
    session.select(
      object: 1,
      level: 'face',
      elements: <int>[for (var i = 0; i < 12; i++) 61 + i],
    ),
    'select the rim',
  );
  must(session.run(const Extrude(0.04)), 'extrude the rim');

  // A modal move, snapped: the person drags the just-extruded lip up by
  // hand — 0.23 m, say — with the grid-snap modifier held.
  // `TransformModal._snap` (`apps/flutter3d_modeler/lib/src/
  // transform_modal.dart`) rounds that to the nearest `moveStep` (0.1 m):
  // `(0.23 / 0.1).round() * 0.1 == 0.2`. `TransformElements` acts on
  // whatever `Extrude` just left selected — the newly flared lip — so no
  // second `select` is needed here.
  must(
    session.run(TransformElements(Matrix4.translation(Vector3(0, 0.2, 0)))),
    'move the lip up, snapped to 0.2 m',
  );

  // A loop cut through the belly: half-edge 108 is the vertical edge of
  // face 25 running from vertex 24 to vertex 36 — the boundary between the
  // third and fourth rings up from the base — untouched by the rim's own
  // extrude above.
  must(
    session.select(object: 1, level: 'edge', elements: <int>[108]),
    'select the belly edge',
  );
  must(
    session.run(const LoopCut(cuts: 1, factor: 0.5)),
    'cut a loop through the belly',
  );

  must(
    session.run(
      AddModifier(
        id: 1,
        modifier: MirrorModifier(
          normal: Vector3(1, 0, 0),
          mergeDistance: 0.0005,
        ),
      ),
    ),
    'add the mirror modifier',
  );
  must(
    session.run(
      AddModifier(
        id: 1,
        modifier: ArrayModifier(count: 3, offset: Vector3(0.9, 0, 0)),
      ),
    ),
    'add the array modifier',
  );

  must(
    session.run(const AddMaterial(materialName: 'glazed clay')),
    'addMaterial',
  );
  must(
    session.run(
      const SetMaterialField(
        index: 0,
        field: 'baseColor',
        value: <double>[0.55, 0.35, 0.25, 1.0],
      ),
    ),
    'setMaterialField(baseColor)',
  );
  must(
    session.run(
      const SetMaterialField(index: 0, field: 'metallic', value: 0.0),
    ),
    'setMaterialField(metallic)',
  );
  must(
    session.run(
      const SetMaterialField(index: 0, field: 'roughness', value: 0.55),
    ),
    'setMaterialField(roughness)',
  );
  must(session.run(const AssignMaterial(id: 1, to: 0)), 'assignMaterial');

  must(
    session.run(
      AddImage(
        bytes: stubGlazeTexture(),
        imageName: 'clay-glaze',
        mimeType: 'image/png',
      ),
    ),
    'addImage',
  );
  must(
    session.run(
      const SetTexture(materialIndex: 0, slot: 'albedo', imageIndex: 0),
    ),
    'setTexture(albedo)',
  );
}
