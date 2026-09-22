/// `anim-33d`'s own MCP half: `autoRig`'s new `spineCount`/`fingers`/`toes`/
/// `faceBones`/`ikChains`/`controllers` flags, from `ModelSession.autoRig`
/// straight through to `RigBuildOptions` and the `autoRig` tool's own
/// schema — screen 16's rig-composition switches, given a backend.
///
///     dart test test/auto_rig_options_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

ModelTool _toolNamed(String name) =>
    modelTools.firstWhere((ModelTool it) => it.name == name);

Future<Answer> _call(
  ModelSession session,
  String name,
  Map<String, Object?> arguments,
) async => _toolNamed(name).run(session, arguments);

const _humanoidMarkers = <String, List<double>>{
  'hips': <double>[0, 1.0, 0],
  'spine': <double>[0, 1.2, 0],
  'chest': <double>[0, 1.4, 0],
  'neck': <double>[0, 1.6, 0],
  'head': <double>[0, 1.75, 0],
  'leftShoulder': <double>[0.2, 1.4, 0],
  'leftElbow': <double>[0.5, 1.4, 0],
  'leftWrist': <double>[0.8, 1.4, 0],
  'leftHip': <double>[0.1, 1.0, 0],
  'leftKnee': <double>[0.1, 0.5, 0],
  'leftAnkle': <double>[0.1, 0.05, 0],
};

ModelSession _freshSession() =>
    ModelSession(ModelHistory(const ModelProject()));

void main() {
  group('ModelSession.autoRig — RigBuildOptions pass-through', () {
    test('spineCount adds spine segments', () {
      final session = _freshSession();
      final answer = session.autoRig(
        template: 'humanoid',
        markers: _humanoidMarkers,
        spineCount: 3,
      );
      expect(answer.did, isTrue, reason: answer.says);
      expect(session.history.project.skeletons.single.jointCount, 19);
    });

    test('fingers, toes and faceBones together match the acceptance table', () {
      final session = _freshSession();
      final answer = session.autoRig(
        template: 'humanoid',
        markers: _humanoidMarkers,
        fingers: true,
        spineCount: 3,
        toes: true,
        faceBones: true,
      );
      expect(answer.did, isTrue, reason: answer.says);
      expect(session.history.project.skeletons.single.jointCount, 54);
    });

    test('controllers adds one non-joint socket parent above hips', () {
      final session = _freshSession();
      final before = session.history.project.objects.length;
      final answer = session.autoRig(
        template: 'humanoid',
        markers: _humanoidMarkers,
        controllers: true,
      );
      expect(answer.did, isTrue, reason: answer.says);
      final project = session.history.project;
      expect(project.objects.length, before + 18); // 17 joints + 1 controller
      expect(project.skeletons.single.jointCount, 17);

      final hips = project.objects.firstWhere((o) => o.name == 'hips');
      final controller = project[hips.parent!]!;
      expect(controller.name, 'hipsControl');
      expect(project.skeletons.single.joints, isNot(contains(controller.id)));
    });

    test('ikChains adds four constraints to the built skeleton', () {
      final session = _freshSession();
      final answer = session.autoRig(
        template: 'humanoid',
        markers: _humanoidMarkers,
        ikChains: true,
      );
      expect(answer.did, isTrue, reason: answer.says);
      expect(
        session.history.project.skeletons.single.constraints,
        hasLength(4),
      );
    });

    test('an unreasonable spineCount is refused, not silently built', () {
      final session = _freshSession();
      final answer = session.autoRig(
        template: 'humanoid',
        markers: _humanoidMarkers,
        spineCount: 50,
      );
      expect(answer.did, isFalse);
      expect(session.history.project.skeletons, isEmpty);
    });
  });

  group('the autoRig tool schema carries the same flags', () {
    test('a controllers:true call through the MCP tool layer builds a '
        'controller object', () async {
      final session = _freshSession();
      final result = await _call(session, 'autoRig', <String, Object?>{
        'template': 'humanoid',
        'markers': _humanoidMarkers,
        'controllers': true,
        'fingers': true,
      });
      expect(result.did, isTrue, reason: result.says);
      expect(session.history.project.skeletons.single.jointCount, 47);
      expect(
        session.history.project.objects.any(
          (ModelObject o) => o.name == 'hipsControl',
        ),
        isTrue,
      );
    });
  });
}
