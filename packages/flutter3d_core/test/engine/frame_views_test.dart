/// Every view of a frame, the view-projection each drew through the frame
/// before, and the velocity as a step a plugin's node can ask for on its
/// own (D20).
///
///     dart test test/engine/frame_views_test.dart
///
/// Mutation: drop `|| asked` from `_velocityOn` and the first test finds no
/// velocity pass; stop recording `_previousViewProjections` at the end of a
/// frame and the second sees this frame's matrix as last frame's.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A plugin's post effect that reads the velocity and remembers what its
/// frame told it.
final class _Smear extends RenderNode {
  _Smear({this.optional = false});

  final bool optional;
  final List<FrameContext> seen = <FrameContext>[];

  @override
  String get name => 'acme.smear';

  @override
  List<ResourceId> get reads => <ResourceId>[
    FrameResourceIds.hdrColor,
    if (!optional) FrameResourceIds.velocity,
  ];

  @override
  List<ResourceId> get optionalReads => <ResourceId>[
    if (optional) FrameResourceIds.velocity,
  ];

  @override
  List<ResourceId> get writes => <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {
    seen.add(frame);
    frame.resources.provide(
      FrameResourceIds.hdrColor,
      frame.resources.texture(FrameResourceIds.hdrColor),
    );
  }
}

({Renderer renderer, Scene scene, CameraNode camera}) _stage() {
  final device = FakeBackend();
  final mesh = DeviceMesh.upload(device, CuboidShape().build());
  final camera = CameraNode();
  final scene = Scene()
    ..add(MeshNode(mesh, RenderMaterial())..setPosition(0.0, 0.0, -5.0))
    ..add(camera);
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

/// Neither of the engine's readers of the velocity on.
RenderSettings get _plain => const RenderSettings().copyWith(
  antiAlias: const RenderSettings().antiAlias.copyWith(
    temporal: const RenderSettings().antiAlias.temporal.copyWith(
      enabled: false,
    ),
  ),
  motionBlur: const RenderSettings().motionBlur.copyWith(enabled: false),
);

FrameResult _draw(
  ({Renderer renderer, Scene scene, CameraNode camera}) it,
  RenderSettings settings,
) => it.renderer.render(
  width: 64,
  height: 48,
  scene: it.scene,
  settings: settings,
  views: <RenderView>[RenderView(camera: it.camera)],
);

void main() {
  test('a plugin node that reads the velocity gets it without TAA or blur', () {
    final it = _stage();
    final smear = _Smear();
    it.renderer.renderSteps.addNode(smear, at: RenderAnchor.afterVelocity);
    final result = _draw(it, _plain);
    final ran = <String>{for (final pass in result.passes) pass.name};
    expect(ran, containsAll(<String>['camera velocity', 'acme.smear']));
    expect(smear.seen, hasLength(1));
  });

  test('without the plugin, the frame draws no velocity it never used', () {
    final it = _stage();
    final result = _draw(it, _plain);
    final ran = <String>{for (final pass in result.passes) pass.name};
    expect(ran, isNot(contains('camera velocity')));
  });

  test('the velocity switched off takes its readers with it', () {
    final settings = const RenderSettings().without(<RenderStep>{
      RenderStep.velocity,
    });
    expect(RenderStep.velocity.isOn(settings), isFalse);
    expect(settings.antiAlias.temporal.enabled, isFalse);
    expect(settings.motionBlur.enabled, isFalse);
  });

  test('a node reads last frame\'s view-projection of its view', () {
    final it = _stage();
    final smear = _Smear(optional: true);
    it.renderer.renderSteps.addNode(smear, at: RenderAnchor.afterScene);

    _draw(it, _plain);
    final first = smear.seen.single;
    expect(first.views, hasLength(1));
    expect(first.frameView!.hasHistory, isFalse);
    expect(first.previousViewProjection, first.unjitteredViewProjection);

    it.camera.setPosition(1.0, 0.0, 0.0);
    _draw(it, _plain);
    final second = smear.seen.last;
    expect(second.frameView!.hasHistory, isTrue);
    expect(second.previousViewProjection, first.unjitteredViewProjection);
    expect(
      second.previousViewProjection,
      isNot(second.unjitteredViewProjection),
    );
  });

  test('a view from a runtime carries its own pose and asymmetric frustum', () {
    final eye = FrameView.posed(
      position: vm.Vector3(0.032, 1.6, 0.0),
      orientation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.1),
      projection: OffAxisProjection.fromAngles(
        left: -0.9,
        right: 0.7,
        down: -0.8,
        up: 0.75,
      ),
      index: 1,
      viewport: const ViewportRect(0.5, 0.0, 0.5, 1.0),
    );
    // The eye maps to the origin of its own space.
    final at = eye.viewMatrix.transformed3(vm.Vector3(0.032, 1.6, 0.0));
    expect(at.length, closeTo(0.0, 1e-6));
    // Off-axis: the frustum's axis is sheared, which a symmetric one is not.
    expect(eye.projectionMatrix.entry(0, 2), isNot(closeTo(0.0, 1e-6)));
    expect(eye.hasHistory, isFalse);
    expect(eye.previousViewProjection, eye.viewProjection);

    const history = ResourceId('acme.history');
    expect(eye.resource(history).name, 'acme.history#1');
    expect(FrameView.resourceFor(history, 0), history);
    expect(math.max(eye.index, 0), 1);
  });
}
