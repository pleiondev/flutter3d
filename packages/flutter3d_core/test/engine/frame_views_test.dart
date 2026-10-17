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

/// A pass over the whole picture: run once, whatever the views.
final class _Whole extends RenderNode {
  final List<int> seen = <int>[];

  @override
  String get name => 'acme.whole';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  ViewRuns get viewRuns => ViewRuns.once;

  @override
  void execute(RenderFrame frame) {
    seen.add(frame.viewIndex);
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
  views: <CameraView>[CameraView(camera: it.camera)],
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
    expect(
      RenderStep.velocity.isOn(RenderStepContext(settings: settings)),
      isFalse,
    );
    expect(settings.antiAlias.temporal.enabled, isFalse);
    expect(settings.motionBlur.enabled, isFalse);
  });

  test('a plan asks a step\'s switch about the views it plans', () {
    // Mutation: compile the plan without `frameViews`. A step on only for
    // a stereo pair is then off in every plan, and the plan disagrees with
    // the frame it was asked about.
    final it = _stage();
    final right = CameraNode()..setPosition(0.064, 0.0, 0.0);
    it.scene.add(right);
    final pair = RenderStep(
      'acme.pair',
      isOn: (RenderStepContext context) => context.views.length == 2,
      switchOff: (RenderStepContext context) => context.settings,
    );
    it.renderer.renderSteps
      ..addStep(pair)
      ..addNode(_Smear(), at: RenderAnchor.afterScene, step: pair);
    List<String> planned(List<CameraNode> cameras) => <String>[
      for (final node
          in it.renderer
              .planFrame(
                scene: it.scene,
                views: <CameraView>[
                  for (final camera in cameras) CameraView(camera: camera),
                ],
                settings: _plain,
              )
              .order)
        node.name,
    ];
    expect(planned(<CameraNode>[it.camera]), isNot(contains('acme.smear')));
    expect(planned(<CameraNode>[it.camera, right]), contains('acme.smear'));
  });

  test('a node runs once per view with that view\'s index, unless it runs '
      'once', () {
    // Mutation: run every placed node once, and the second eye's node sees
    // view 0 — the promise `FrameContext.viewIndex` makes, broken.
    final it = _stage();
    final right = CameraNode()..setPosition(0.064, 0.0, 0.0);
    it.scene.add(right);
    final each = _Smear(optional: true);
    final whole = _Whole();
    it.renderer.renderSteps
      ..addNode(each, at: RenderAnchor.afterScene)
      ..addNode(whole, at: RenderAnchor.afterScene);
    it.renderer.render(
      width: 64,
      height: 48,
      scene: it.scene,
      settings: _plain,
      views: <CameraView>[
        CameraView(
          camera: it.camera,
          viewportFraction: const ViewportRect(0.0, 0.0, 0.5, 1.0),
        ),
        CameraView(
          camera: right,
          viewportFraction: const ViewportRect(0.5, 0.0, 0.5, 1.0),
        ),
      ],
    );
    expect(<int>[for (final f in each.seen) f.viewIndex], <int>[0, 1]);
    expect(<int>[for (final f in each.seen) f.frameView!.index], <int>[0, 1]);
    expect(identical(each.seen[1].view!.camera, right), isTrue);
    expect(whole.seen, <int>[0]);

    // One view, one run, as before.
    final single = _stage();
    final alone = _Smear(optional: true);
    single.renderer.renderSteps.addNode(alone, at: RenderAnchor.afterScene);
    _draw(single, _plain);
    expect(alone.seen.single.viewIndex, 0);
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
