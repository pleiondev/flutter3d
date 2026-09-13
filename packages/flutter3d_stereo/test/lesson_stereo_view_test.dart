/// `edu-06`: the button on [LessonStereoView] actually drives the rig — not
/// just wired to a callback that compiles, but proven to move the stage and
/// flip visibility through a real (headless) render pass, the same
/// [CpuDevice] `wg-01`'s own tests already use to avoid a GPU.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

List<EntityDef> _steps() => <EntityDef>[
  EntityDef(
    type: 'edu_step',
    name: 'step-1',
    position: Vector3(0.0, 1.6, 3.0),
    properties: <String, Object?>{
      'visible': <String>['part'],
    },
  ),
  EntityDef(
    type: 'edu_step',
    name: 'step-2',
    position: Vector3(1.0, 1.6, 3.0),
    properties: <String, Object?>{
      'hidden': <String>['part'],
    },
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping Next moves the stage and hides the part step-2 hides', (
    tester,
  ) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final scene = Scene();
    final rig = StereoRig();
    scene.add(rig.stage);
    final part = SceneNode(name: 'part');
    scene.add(part);
    final player = LessonPlayer(_steps());

    await tester.pumpWidget(
      MaterialApp(
        home: LessonStereoView(
          renderer: renderer,
          scene: scene,
          rig: rig,
          player: player,
          nodes: <String, SceneNode>{'part': part},
        ),
      ),
    );
    await tester.pump();

    expect(part.visible, isTrue, reason: 'step-1 shows it');
    final beforeX = rig.stage.readWorldPosition().x;

    await tester.tap(find.byTooltip('Next step'));
    await tester.pump();

    expect(part.visible, isFalse, reason: 'step-2 hides it');
    final afterX = rig.stage.readWorldPosition().x;
    expect(afterX - beforeX, closeTo(1.0, 1e-6));
  });

  testWidgets('the Previous button is disabled on the first step', (
    tester,
  ) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final scene = Scene();
    final rig = StereoRig();
    scene.add(rig.stage);
    final player = LessonPlayer(_steps());

    await tester.pumpWidget(
      MaterialApp(
        home: LessonStereoView(
          renderer: renderer,
          scene: scene,
          rig: rig,
          player: player,
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back),
    );
    expect(button.onPressed, isNull);
  });
}
