/// Glass that shows the scene behind it — `M3`, `transmission-glass`.
///
///     dart test test/transmission_glass_test.dart
///
/// A frame that holds a transmissive draw splits the scene around a copy of
/// itself: the opaque half, `scene colour copy`, then `transparent` with the
/// glass reading the copy. Read off the scene target and the copy on the
/// software rasteriser, whose textures keep the floats a shader wrote, by a
/// node of the test's own that reads them after the composite.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _size = 48;

/// The wall's two halves, unlit, so the scene target holds them exactly —
/// authored in sRGB, as a base colour is.
final Vector4 _red = Vector4(0.8, 0.1, 0.1, 1.0);
final Vector4 _blue = Vector4(0.1, 0.2, 0.9, 1.0);

/// [srgb] as the scene target holds it: linear light.
Vector4 _linear(Vector4 srgb) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return Vector4(channel(srgb.x), channel(srgb.y), channel(srgb.z), srgb.w);
}

/// Copies [id] out as floats each frame it runs, after the composite.
final class _Probe extends RenderNode {
  _Probe(this._device, this.id);

  final CpuDevice _device;
  final ResourceId id;
  Float32List? last;
  int width = 0;

  @override
  String get name => 'probe ${id.name}';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  List<ResourceId> get reads => <ResourceId>[FrameResourceIds.frame, id];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    final texture = frame.resources.texture(id);
    last = _device.readHdrPixels(texture);
    width = texture.width;
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

/// A pane of the layered model, facing the camera unless [yaw] turns it.
MeshNode _glass(
  DeviceMesh quad, {
  double transmission = 1.0,
  double roughness = 0.0,
  double thickness = 0.0,
  double yaw = 0.0,
  double clearcoat = 0.0,
}) =>
    MeshNode(
        quad,
        Material(
          lighting: LightingModel.pbrLayered,
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          roughness: roughness,
          extensions: MaterialExtensions(
            transmission: transmission,
            thickness: thickness,
            clearcoat: clearcoat,
          ),
          doubleSided: true,
        ),
      )
      ..setPosition(0.0, 0.0, -2.0)
      ..setRotationYawPitchRoll(yaw, math.pi / 2, 0.0);

typedef _Frame = ({Float32List hdr, FrameResult result, Float32List? copy});

/// The wall — red left of [seam], blue right of it — two metres behind a
/// pane, drawn with [settings] and read back.
_Frame _render({
  MeshNode Function(DeviceMesh quad)? pane,
  RenderSettings settings = const RenderSettings(
    bloom: BloomSettings(enabled: false),
  ),
  int size = _size,
  double seam = 0.0,
  bool readCopy = false,
  List<MeshNode Function(DeviceMesh quad)> extra =
      const <MeshNode Function(DeviceMesh)>[],
}) {
  final device = CpuDevice(
    width: size,
    height: size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final quad = DeviceMesh.upload(
    device,
    const PlaneShape(width: 1.2, depth: 1.2).build(),
  );
  final half = DeviceMesh.upload(
    device,
    const PlaneShape(width: 3.0, depth: 6.0).build(),
  );
  MeshNode wall(double x, Vector4 colour) =>
      MeshNode(half, Material(lighting: LightingModel.unlit, baseColor: colour))
        ..setPosition(x, 0.0, -4.0)
        ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0);
  final camera = CameraNode();
  final scene = Scene()
    ..add(camera)
    ..add(wall(seam - 1.5, _red))
    ..add(wall(seam + 1.5, _blue));
  if (pane != null) scene.add(pane(quad));
  for (final node in extra) {
    scene.add(node(quad));
  }
  final hdr = _Probe(device, FrameResourceIds.hdrColour);
  final copy = _Probe(device, FrameResourceIds.sceneColour);
  final renderer = Renderer.create(device: device)..addNode(hdr);
  if (readCopy) renderer.addNode(copy);
  final result = renderer.render(
    width: size,
    height: size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings,
  );
  return (hdr: hdr.last!, result: result, copy: copy.last);
}

Vector4 _at(Float32List hdr, int x, int y, {int width = _size}) {
  final i = (y * width + x) * 4;
  return Vector4(hdr[i], hdr[i + 1], hdr[i + 2], hdr[i + 3]);
}

/// Pixels in the pane's middle, well inside it: left over the red half and
/// right over the blue.
const ({int x, int y}) _left = (x: 17, y: 24);
const ({int x, int y}) _right = (x: 31, y: 24);

void main() {
  test('transmission-glass: the pane shows the wall behind it', () {
    // Mutation: bind black in the copy's place in `_encodeNode`. Both
    // halves of the pane read nothing and come out black.
    final frame = _render(pane: _glass);
    // Head-on through clear glass: all of the wall, less the four and a
    // half per cent the dielectric reflects at this angle.
    for (final (pixel, wall) in <((int, int), Vector4)>[
      ((_left.x, _left.y), _linear(_red)),
      ((_right.x, _right.y), _linear(_blue)),
    ]) {
      final seen = _at(frame.hdr, pixel.$1, pixel.$2);
      for (var c = 0; c < 3; c++) {
        expect(
          seen[c],
          closeTo(wall[c] * 0.955, 0.01),
          reason: 'pixel $pixel channel $c',
        );
      }
    }
  });

  test('the frame is split around the copy only when it holds glass', () {
    List<String> ran(FrameResult result) =>
        result.passes.map((p) => p.name).toList();
    final glass = _render(pane: _glass).result;
    expect(
      ran(glass).where(
        (n) =>
            <String>{'scene', 'scene colour copy', 'transparent'}.contains(n),
      ),
      <String>['scene', 'scene colour copy', 'transparent'],
    );

    // A layered pane with no transmission: the two nodes are registered,
    // culled, and the scene is drawn in one pass.
    final plain = _render(
      pane: (q) => _glass(q, transmission: 0.0, clearcoat: 1),
    );
    expect(ran(plain.result), isNot(contains('scene colour copy')));
    expect(ran(plain.result), isNot(contains('transparent')));
    expect(
      plain.result.skipped.map((s) => s.name),
      containsAll(<String>['scene colour copy', 'transparent']),
    );
  });

  test('a frame without glass draws the bytes it drew before', () {
    // The default path: the same frame with the two nodes switched off by
    // name is the frame as it was before they existed.
    MeshNode coated(DeviceMesh q) =>
        _glass(q, transmission: 0.0, clearcoat: 1.0);
    final now = _render(pane: coated).hdr;
    final before = _render(
      pane: coated,
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        disabledPasses: <String>{'scene colour copy', 'transparent'},
      ),
    ).hdr;
    expect(now, before);
  });

  test('switched off, the glass reads the environment as it did', () {
    // Mutation: ignore `'transparent'` being disabled in `_SceneNode` (split
    // on `transparent.active`). The frame throws or shows the wall.
    final frame = _render(
      pane: _glass,
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        disabledPasses: <String>{'transparent'},
      ),
    );
    // No environment and no copy: both halves see the same flat ambient.
    final left = _at(frame.hdr, _left.x, _left.y);
    final right = _at(frame.hdr, _right.x, _right.y);
    for (var c = 0; c < 3; c++) {
      expect(left[c], closeTo(right[c], 1e-6));
    }
    expect(left.x, lessThan(_linear(_red).x * 0.5));
  });

  test('each level of the copy is the mean of the scene under it', () {
    // Mutation: halve the columns' offsets in `SceneColourCopyShader`. A
    // block then averages the wrong texels, and the one on the seam shows.
    const size = 64;
    // The seam off every level's block boundaries, so a block that averages
    // the wrong texels straddles it and shows.
    final frame = _render(pane: _glass, size: size, seam: 0.37, readCopy: true);
    final copy = frame.copy!;
    final width = size + size ~/ 2;
    // The base: the scene as the opaque half left it, glass not yet drawn.
    final base = List<Vector4>.generate(
      size * size,
      (i) => _at(copy, i % size, i ~/ size, width: width),
    );
    expect(base[24 * size + 16].x, closeTo(_linear(_red).x, 1e-6));
    var top = 0;
    for (var level = 1; level <= 5; level++) {
      final side = size >> level;
      final scale = 1 << level;
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final mean = Vector4.zero();
          for (var j = 0; j < scale; j++) {
            for (var i = 0; i < scale; i++) {
              mean.add(base[(y * scale + j) * size + x * scale + i]);
            }
          }
          mean.scale(1.0 / (scale * scale));
          final texel = _at(copy, size + x, top + y, width: width);
          for (var c = 0; c < 3; c++) {
            expect(
              texel[c],
              closeTo(mean[c], 1e-4),
              reason: 'level $level texel ($x, $y) channel $c',
            );
          }
        }
      }
      top += side;
    }
  });

  test('rough glass reads a blurred level of the copy', () {
    // Mutation: drop the roughness from the level `SceneBehind` chooses.
    // Rough glass reads the sharp base and keeps the seam.
    double contrast(Float32List hdr) =>
        (_at(hdr, _left.x, _left.y).x - _at(hdr, _right.x, _right.y).x).abs();
    final clear = _render(pane: _glass).hdr;
    final frosted = _render(pane: (q) => _glass(q, roughness: 1.0)).hdr;
    expect(contrast(clear), greaterThan(0.4));
    expect(contrast(frosted), lessThan(contrast(clear) * 0.5));
  });

  test('a thick pane bends what is behind it and a thin one does not', () {
    // Mutation: leave the thickness out of the exit point in
    // `sceneBehind`. The turned pane reads straight through either way.
    MeshNode turned(DeviceMesh q, double thickness) =>
        _glass(q, thickness: thickness, yaw: 0.6);
    final thin = _render(pane: (q) => turned(q, 0.0)).hdr;
    final thick = _render(pane: (q) => turned(q, 1.5)).hdr;
    var moved = 0;
    for (var i = 0; i < thin.length; i += 4) {
      if ((thin[i] - thick[i]).abs() > 0.05) moved++;
    }
    expect(moved, greaterThan(10));
    // Outside the pane nothing changes: the wall's corners are the wall.
    expect(_at(thick, 1, 1).x, closeTo(_linear(_red).x, 1e-6));
    expect(_at(thick, _size - 2, 1).z, closeTo(_linear(_blue).z, 1e-6));
  });

  test('a transparent pane in front still lands over the glass', () {
    // The transparent half moves to the second pass with the glass, sorted
    // and under weighted blended transparency both.
    MeshNode veil(DeviceMesh q) =>
        MeshNode(
            q,
            Material(
              lighting: LightingModel.unlit,
              baseColor: Vector4(0.0, 1.0, 0.0, 0.5),
              alphaMode: MaterialAlphaMode.blend,
              doubleSided: true,
            ),
          )
          ..setPosition(0.0, 0.0, -1.5)
          ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0);
    for (final mode in TransparencyMode.values) {
      final settings = RenderSettings(
        bloom: const BloomSettings(enabled: false),
        transparency: mode,
      );
      final frame = _render(
        pane: _glass,
        extra: <MeshNode Function(DeviceMesh)>[veil],
        settings: settings,
      );
      final seen = _at(frame.hdr, _left.x, _left.y);
      // Half the veil's green over half the glass's red.
      expect(seen.y, greaterThan(0.4), reason: '$mode');
      expect(
        seen.x,
        closeTo(_linear(_red).x * 0.955 * 0.5, 0.02),
        reason: '$mode',
      );
    }
  });

  test('every declared slot is bound on a split frame', () {
    // `scene_colour_texture` is the layered stage's sixteenth sampler; a
    // draw that left it unbound is a crash on Metal.
    final device = FakeBackend(stageBindings: stageBindings);
    final quad = DeviceMesh.upload(
      device,
      const PlaneShape(width: 1.2, depth: 1.2).build(),
    );
    final camera = CameraNode();
    final scene = Scene()
      ..add(camera)
      ..add(_glass(quad));
    final result = Renderer.create(device: device).render(
      width: 32,
      height: 32,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );
    expect(device.bindingViolations, isEmpty);
    expect(result.passes.map((p) => p.name), contains('transparent'));
    // Multisampled targets are tile memory, and the second pass cannot load
    // them: the frame says why it drew with one sample.
    expect(result.antiAliasing.msaaDeclined, contains('transmissive'));
  });
}
