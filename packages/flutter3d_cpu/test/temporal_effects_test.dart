/// Half the samples, a new offset each frame and a history make the same
/// occlusion as all of them — `R3`.
///
///     dart test test/temporal_effects_test.dart
///
/// Read off the occlusion resource itself, after the history, by a node of
/// the test's own that runs after the composite.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _width = 64;
const int _height = 48;

final class _AoProbe extends RenderNode {
  _AoProbe(this._device);

  final CpuDevice _device;
  Float32List? last;

  @override
  String get name => 'ao probe';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.frame,
    FrameResourceIds.ao,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    last = _device.readHdrPixels(frame.resources.texture(FrameResourceIds.ao));
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

RenderSettings _settings({required bool temporal}) => RenderSettings(
  bloom: const BloomSettings(enabled: false),
  ambientOcclusion: const AmbientOcclusionSettings(enabled: true),
  antiAlias: AntiAliasSettings(temporal: TemporalSettings(enabled: temporal)),
);

/// A box standing in the corner of two walls and a floor: creases for the
/// occlusion to find.
({Renderer renderer, Scene scene, RenderView view, _AoProbe probe}) _staged() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  MeshNode slab(
    double x,
    double y,
    double z,
    double sx,
    double sy,
    double sz,
  ) => MeshNode(cube, Material())
    ..setPosition(x, y, z)
    ..setScale(sx, sy, sz);
  final camera = CameraNode()..setPosition(0.0, 1.0, 3.0);
  final scene = Scene()
    ..add(slab(0.0, -0.5, 0.0, 6.0, 0.1, 6.0))
    ..add(slab(0.0, 1.0, -2.0, 6.0, 3.0, 0.1))
    ..add(slab(0.0, 0.0, -1.2, 0.8, 0.8, 0.8))
    ..add(camera);
  final probe = _AoProbe(device);
  return (
    renderer: Renderer.create(device: device)..addNode(probe),
    scene: scene,
    view: RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    probe: probe,
  );
}

Float32List _ao(
  ({Renderer renderer, Scene scene, RenderView view, _AoProbe probe}) it,
  RenderSettings settings,
) {
  it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[it.view],
    settings: settings,
  );
  return it.probe.last!;
}

double _mean(Float32List ao) {
  var sum = 0.0;
  for (var i = 0; i < ao.length; i += 4) {
    sum += ao[i];
  }
  return sum / (ao.length / 4);
}

void main() {
  test('the accumulated occlusion is the full occlusion', () {
    final full = _mean(_ao(_staged(), _settings(temporal: false)));

    final it = _staged();
    late Float32List last;
    for (var i = 0; i < 24; i++) {
      last = _ao(it, _settings(temporal: true));
    }
    // Mutation: return `now` from the accumulate shader's mirror. Six taps
    // under one rotation darken or lighten the creases by their own luck, and
    // the mean drifts.
    expect(_mean(last), closeTo(full, 0.03));
    expect(full, lessThan(0.99), reason: 'the scene has creases to find');
  });

  test('and it holds still from frame to frame', () {
    final it = _staged();
    for (var i = 0; i < 24; i++) {
      _ao(it, _settings(temporal: true));
    }
    final a = _ao(it, _settings(temporal: true));
    final b = _ao(it, _settings(temporal: true));
    var worst = 0.0;
    for (var i = 0; i < a.length; i += 4) {
      final d = (a[i] - b[i]).abs();
      if (d > worst) worst = d;
    }
    expect(worst, lessThan(0.15));
  });

  test('without temporal on, the occlusion reads no noise and keeps no '
      'history', () {
    final it = _staged();
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
      settings: _settings(temporal: false),
    );
    expect(result.passes.map((p) => p.name), isNot(contains('ssao history')));
  });
}
