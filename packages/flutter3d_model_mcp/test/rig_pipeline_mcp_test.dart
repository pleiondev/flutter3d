/// `anim-30`'s own scenario: "RobotExpressive без скина → авториг → веса →
/// ключи → GLB" — driven the same way `tools_test.dart` drives every other
/// tool, by calling `ModelTool.run` directly rather than starting a real
/// stdio server, which is what `dart_mcp`'s own in-memory pair of channels
/// buys every other test in this suite too.
///
/// **"Without a skin" is what `import` already gives.** `RobotExpressive.glb`
/// carries a real skin and real joint-weight defects of its own (qa-09's own
/// finding) — but `import_into.dart` does not read glTF skins or animations
/// at all yet (that half of the reader is not built), so bringing the file
/// in through the ordinary `import` tool already yields plain, unskinned
/// mesh objects. Nothing here has to strip anything; there is nothing to
/// strip.
///
///     dart test test/rig_pipeline_mcp_test.dart
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show importMeshData;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelTool _toolNamed(String name) =>
    modelTools.firstWhere((ModelTool it) => it.name == name);

Future<Answer> _call(
  ModelSession session,
  String name,
  Map<String, Object?> arguments,
) async => _toolNamed(name).run(session, arguments);

/// The world-space AABB of every mesh object's own live geometry — used to
/// scale a plausible marker set to whatever this particular imported model's
/// own size and proportions turn out to be, rather than hard-coding
/// centimetres that would only work for one specific export of one specific
/// file.
Aabb3 _meshBounds(ModelProject project) {
  var min = Vector3(double.infinity, double.infinity, double.infinity);
  var max = Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final object in project.objects) {
    if (object.geometry case EditedGeometry(:final mesh)) {
      final world = worldTransformOf(project, object.id);
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        final p = world.transformed3(mesh.positionOf(v));
        min = Vector3(
          p.x < min.x ? p.x : min.x,
          p.y < min.y ? p.y : min.y,
          p.z < min.z ? p.z : min.z,
        );
        max = Vector3(
          p.x > max.x ? p.x : max.x,
          p.y > max.y ? p.y : max.y,
          p.z > max.z ? p.z : max.z,
        );
      }
    }
  }
  return Aabb3.minMax(min, max);
}

/// Builds real topology for every mesh `import` brought in.
///
/// **A gap this scenario has to bridge itself, not a tool this row adds.**
/// `import_into.dart`'s own doc comment says it plainly: "every mesh arrives
/// as `ImportedGeometry` and stays that way" — flat vertex buffers, no
/// half-edge structure yet, which is exactly what `bakeToMesh`'s own refusal
/// names ("building topology for it is an import option rather than a
/// conversion... `doc-11`'s import screen"). That screen is not built, and
/// no MCP tool wraps `flutter3d_mesh`'s own `importMeshData` either — `anim-30`'s
/// own nine tools do not include one, and adding a tenth, unlisted one is
/// not this row's call to make. So this scenario calls the real function
/// directly, the same way `flutter3d_modeler`'s own future import screen
/// eventually will, and folds the result back through `ReplaceDocument` —
/// one more undo step, using the same escape hatch `ModelSession.import`
/// itself already uses for a whole-document swap.
void _buildTopologyForImportedMeshes(ModelSession session) {
  var next = session.history.project;
  for (final object in next.objects) {
    if (object.geometry case ImportedGeometry(:final data)) {
      final (mesh, _, _) = importMeshData(data);
      next = next.withObject(object.copyWith(geometry: EditedGeometry(mesh)));
    }
  }
  final refused = session.history.run(
    ReplaceDocument(next, 'build topology for imported meshes'),
    author: StepAuthor.agent,
  );
  if (refused != null) {
    throw StateError('could not build topology: $refused');
  }
}

/// The object with the most live vertices — this scenario's stand-in for
/// "the body", the one mesh `autoRig`'s own `skinObjectId` binds and
/// `paintWeights` paints.
int _biggestMeshObject(ModelProject project) {
  var bestId = -1;
  var bestCount = -1;
  for (final object in project.objects) {
    if (object.geometry case EditedGeometry(:final mesh)) {
      if (mesh.vertexCount > bestCount) {
        bestCount = mesh.vertexCount;
        bestId = object.id;
      }
    }
  }
  return bestId;
}

void main() {
  test(
    'RobotExpressive, unskinned: autoRig, paintWeights, setKey, export to '
    'GLB with a real skeleton and a real clip',
    () async {
      final session = ModelSession(ModelHistory(const ModelProject()));

      // 1. Import — mesh and silhouette only; see the library comment for
      // why this file's own skin never enters the picture.
      final imported = await _call(session, 'import', <String, Object?>{
        'from': '../flutter3d_samples/assets/RobotExpressive.glb',
      });
      expect(imported.did, isTrue, reason: imported.says);
      expect(session.history.project.objects, isNotEmpty);
      expect(session.history.project.skeletons, isEmpty);

      // 1b. Real topology for every imported mesh — see the helper's own
      // doc comment for why this scenario does this itself.
      _buildTopologyForImportedMeshes(session);
      expect(
        session.history.project.objects.any(
          (ModelObject o) => o.geometry is EditedGeometry,
        ),
        isTrue,
      );

      // 2. A plausible humanoid marker set, scaled to this model's own
      // bounding box rather than to hard-coded centimetres.
      final bounds = _meshBounds(session.history.project);
      final size = bounds.max - bounds.min;
      final height = size.y;
      final cx = (bounds.min.x + bounds.max.x) / 2;
      final cz = (bounds.min.z + bounds.max.z) / 2;
      final baseY = bounds.min.y;
      final halfWidth = size.x / 2;

      List<double> at(double xFrac, double yFrac, {double zFrac = 0}) => <double>[
        cx + xFrac * halfWidth,
        baseY + yFrac * height,
        cz + zFrac * (size.z / 2),
      ];

      final markers = <String, List<double>>{
        'hips': at(0, 0.5),
        'spine': at(0, 0.6),
        'chest': at(0, 0.7),
        'neck': at(0, 0.85),
        'head': at(0, 0.95),
        'leftShoulder': at(0.3, 0.7),
        'leftElbow': at(0.5, 0.55),
        'leftWrist': at(0.6, 0.4),
        'leftHip': at(0.15, 0.48),
        'leftKnee': at(0.15, 0.25),
        'leftAnkle': at(0.15, 0.02),
      };

      final mainObjectId = _biggestMeshObject(session.history.project);
      expect(mainObjectId, greaterThan(0));

      // 3. Auto-rig: a skeleton built from the markers above, bound to the
      // biggest mesh in the same undo step.
      final rigged = await _call(session, 'autoRig', <String, Object?>{
        'template': 'humanoid',
        'markers': markers,
        'skinObjectId': mainObjectId,
        'skeletonName': 'auto',
      });
      expect(rigged.did, isTrue, reason: rigged.says);
      expect(session.history.project.skeletons, hasLength(1));
      final skeleton = session.history.project.skeletons.single;
      expect(skeleton.jointCount, lessThanOrEqualTo(64));
      expect(session.history.project[mainObjectId]!.skeletonIndex, 0);

      final hipsId = skeleton.joints.firstWhere(
        (int id) => session.history.project[id]!.name == 'hips',
      );

      // 4. Paint weights: assign every vertex of the skinned mesh fully to
      // the hips joint — a real call to the real brush, not the deepest
      // possible rig, but a genuine, checkable one (every weight ends up
      // summing to exactly one).
      final diagonal = size.length + 1.0;
      final painted = await _call(session, 'paintWeights', <String, Object?>{
        'objectId': mainObjectId,
        'skeletonIndex': 0,
        'joint': hipsId,
        'samples': <Map<String, Object?>>[
          <String, Object?>{
            'center': <double>[cx, baseY + height / 2, cz],
            'radius': diagonal,
          },
        ],
        'strength': 1.0,
        'mode': 'assign',
      });
      expect(painted.did, isTrue, reason: painted.says);

      // 5. A clip, a track (via poseJoint, which creates one on demand) and
      // a couple of explicit setKey calls on it.
      final clipAdded = await _call(session, 'addClip', <String, Object?>{
        'clipName': 'idle',
      });
      expect(clipAdded.did, isTrue, reason: clipAdded.says);
      const clipIndex = 0;

      final posed = await _call(session, 'poseJoint', <String, Object?>{
        'joint': hipsId,
        'path': 'translation',
        'clipIndex': clipIndex,
        'frame': 0,
      });
      expect(posed.did, isTrue, reason: posed.says);
      expect(
        session.history.project.clips[clipIndex].tracks,
        hasLength(1),
      );
      const trackIndex = 0;
      final hipsTranslation = session.history.project[hipsId]!.transform
          .getTranslation();

      final firstKey = await _call(session, 'setKey', <String, Object?>{
        'clipIndex': clipIndex,
        'trackIndex': trackIndex,
        'time': 0.5,
        'values': <double>[
          hipsTranslation.x,
          hipsTranslation.y + 0.1,
          hipsTranslation.z,
        ],
      });
      expect(firstKey.did, isTrue, reason: firstKey.says);

      final secondKey = await _call(session, 'setKey', <String, Object?>{
        'clipIndex': clipIndex,
        'trackIndex': trackIndex,
        'time': 1.0,
        'values': <double>[
          hipsTranslation.x,
          hipsTranslation.y,
          hipsTranslation.z,
        ],
      });
      expect(secondKey.did, isTrue, reason: secondKey.says);
      expect(
        session.history.project.clips[clipIndex].tracks[trackIndex].track
            .keyCount,
        3,
      );

      // 6. `validateRig` is read-only and must not refuse to run; it is not
      // asked to come back clean (a skeleton with sixteen joints and one
      // painted still has fifteen "no vertex weighs to me" warnings, which
      // is real and expected of this minimal a paint).
      final validated = await _call(session, 'validateRig', const <String, Object?>{});
      expect(validated.did, isTrue, reason: validated.says);
      expect(
        validated.says,
        isNot(contains('error:')),
        reason: 'no error-level rig issue was expected: ${validated.says}',
      );

      // 7. Export to GLB, and read it back through the real glTF loader —
      // the acceptance line itself: a skeleton and a clip, not just a
      // ModelProject that says it has them.
      final tempDir = Directory.systemTemp.createTempSync('anim30_rig_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final glbPath = '${tempDir.path}/robot.glb';

      final exported = await _call(session, 'export', <String, Object?>{
        'to': glbPath,
        'format': 'glb',
        'force': true,
      });
      expect(exported.did, isTrue, reason: exported.says);

      final bytes = File(glbPath).readAsBytesSync();
      final document = await GltfLoader().load(bytes);

      expect(
        document.skins,
        isNotEmpty,
        reason: 'the exported GLB has no skin — no skeleton made it across',
      );
      expect(
        document.animations,
        isNotEmpty,
        reason: 'the exported GLB has no animation — no clip made it across',
      );
      final hasRealKeys = document.animations.any(
        (AnimationClip clip) =>
            clip.tracks.any((AnimationTrack track) => track.times.length >= 2),
      );
      expect(
        hasRealKeys,
        isTrue,
        reason: 'no animation track in the exported GLB carries more than '
            'one key',
      );
    },
  );
}
