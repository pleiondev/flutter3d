/// `RenderSettings.telemetry` — how much of a frame the renderer measures,
/// on the software device.
///
///     dart test test/telemetry_test.dart
///
/// Off keeps the frame's totals and nothing per node or per resource;
/// counters keep a record per node and per resource without reading a
/// clock; timings add each node's time.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

typedef _Stage = ({Renderer renderer, Scene scene});

_Stage _stage() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 3.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
        RenderMaterial(baseColor: LinearColor.fromSrgb(0.7, 0.5, 0.3, 1.0)),
      ),
    )
    ..add(LightNode()..setPosition(1.0, 2.0, 2.0))
    ..add(camera);
  return (renderer: Renderer.create(device: device), scene: scene);
}

FrameResult _render(_Stage it, TelemetryLevel telemetry) => it.renderer.render(
  width: _size,
  height: _size,
  scene: it.scene,
  views: <RenderView>[RenderView(camera: it.scene.cameras.single)],
  settings: RenderSettings(telemetry: telemetry),
);

void main() {
  test('timings are the default', () {
    expect(const RenderSettings().telemetry, TelemetryLevel.timings);
  });

  test('timings keep every node, timed, and every resource', () {
    final frame = _render(_stage(), TelemetryLevel.timings);
    final scene = frame.passes.singleWhere((FramePass p) => p.name == 'scene');
    expect(scene.drawCalls, greaterThan(0));
    // A frame of a dozen nodes on the software device takes a measurable
    // time between them, whatever one node took.
    expect(
      frame.passes.fold(0, (int sum, FramePass p) => sum + p.micros),
      greaterThan(0),
    );
    final color = frame.resources.singleWhere(
      (FrameResourceUse r) => r.id == FrameResourceIds.hdrColor,
    );
    expect(color.width, _size);
    expect(color.height, _size);
    expect(color.versions, greaterThanOrEqualTo(1));
    expect(color.bytes, greaterThan(0));
  });

  test('counters keep every node and resource and read no clock', () {
    // Mutation: time the nodes whatever the level, and a pass's micros is
    // no longer nought here.
    final frame = _render(_stage(), TelemetryLevel.counters);
    expect(frame.passes, isNotEmpty);
    for (final pass in frame.passes) {
      expect(pass.micros, 0, reason: pass.name);
      expect(pass.gpuMicros, isNull, reason: pass.name);
    }
    expect(
      frame.passes.singleWhere((FramePass p) => p.name == 'scene').drawCalls,
      greaterThan(0),
    );
    expect(frame.resources, isNotEmpty);
  });

  test('off keeps the totals and nothing per node or resource', () {
    // Mutation: record the nodes whatever the level, and `passes` is not
    // empty.
    final it = _stage();
    // The first frame also draws what later frames keep (the static
    // shadows), so the two compared are both past it.
    _render(it, TelemetryLevel.timings);
    final timed = _render(it, TelemetryLevel.timings);
    final off = _render(it, TelemetryLevel.off);
    expect(off.passes, isEmpty);
    expect(off.resources, isEmpty);
    expect(off.drawCalls, timed.drawCalls);
    expect(off.triangles, timed.triangles);
    // What smoothed the edges is the frame's, not the telemetry's.
    expect(off.antiAliasing.fxaa, timed.antiAliasing.fxaa);
    expect(off.antiAliasing.temporal, timed.antiAliasing.temporal);
  });

  test('the levels are an open set with wire names', () {
    expect(TelemetryLevel.values.map((TelemetryLevel l) => l.name), <String>[
      'off',
      'counters',
      'timings',
    ]);
    expect(TelemetryLevel.off.recordsNodes, isFalse);
    expect(TelemetryLevel.counters.recordsNodes, isTrue);
    expect(TelemetryLevel.counters.recordsTimes, isFalse);
    expect(TelemetryLevel.timings.recordsTimes, isTrue);
  });
}
