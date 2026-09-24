/// Transparency composited without a sort — `R8`, weighted blended
/// order-independent transparency.
///
///     dart test test/weighted_blended_test.dart
///
/// The test is order independence itself: the same glass drawn in three
/// orders comes out the same bytes, where the sorted blend it stands beside
/// does not. The rest pin what the mode must leave alone.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _size = 40;

/// A pane of glass, upright and facing the camera unless [yaw] turns it.
({double x, double z, double yaw, Vector4 colour}) _pane(
  double x,
  double z,
  Vector4 colour, {
  double yaw = 0.0,
}) => (x: x, z: z, yaw: yaw, colour: colour);

/// `glass-stack-oit`: three overlapping panes at three depths and two more
/// crossing through each other, in front of a grey wall.
final List<({double x, double z, double yaw, Vector4 colour})> _glassStack =
    <({double x, double z, double yaw, Vector4 colour})>[
      _pane(-0.3, -1.0, Vector4(0.9, 0.1, 0.1, 0.5)),
      _pane(0.0, -1.6, Vector4(0.1, 0.9, 0.1, 0.45)),
      _pane(0.3, -2.2, Vector4(0.1, 0.2, 0.9, 0.6)),
      // Through each other, so no order of the two is right everywhere.
      _pane(0.1, -1.3, Vector4(0.9, 0.8, 0.1, 0.4), yaw: 0.6),
      _pane(0.1, -1.3, Vector4(0.8, 0.1, 0.9, 0.35), yaw: -0.6),
    ];

/// Renders [panes], added to the scene in the order [order] names, and
/// returns the finished frame's pixels.
///
/// With [sort] at [SortMode.none] the draws go in that order; with
/// [SortMode.backToFront] the list sorts them, whatever order they came in.
Float32List _render({
  required TransparencyMode mode,
  List<({double x, double z, double yaw, Vector4 colour})>? panes,
  List<int>? order,
  SortMode sort = SortMode.none,
  bool independentBlend = true,
  bool? paneDepthWrite,
}) {
  final glass = panes ?? _glassStack;
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    supportsIndependentBlend: independentBlend,
  );
  final quad = DeviceMesh.upload(
    device,
    const PlaneShape(width: 1.2, depth: 1.2).build(),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 1.0);
  final wall =
      MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(0.45, 0.45, 0.45, 1.0),
            doubleSided: true,
          ),
        )
        ..setPosition(0.0, 0.0, -3.0)
        ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0);
  final scene = Scene()
    ..add(camera)
    ..add(wall);
  for (final index
      in order ?? <int>[for (var i = 0; i < glass.length; i++) i]) {
    final pane = glass[index];
    scene.add(
      MeshNode(
          quad,
          Material(
            lighting: LightingModel.unlit,
            baseColor: pane.colour,
            alphaMode: MaterialAlphaMode.blend,
            depthWrite: paneDepthWrite,
            doubleSided: true,
          ),
        )
        ..setPosition(pane.x, 0.0, pane.z)
        ..setRotationYawPitchRoll(pane.yaw, math.pi / 2, 0.0),
    );
  }
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera, transparentSort: sort)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      transparency: mode,
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// How many pixels of [a] and [b] differ in any channel by more than [by].
int _differing(Float32List a, Float32List b, {double by = 0.0}) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var k = 0; k < 4; k++) {
      if ((a[i + k] - b[i + k]).abs() > by) {
        count++;
        break;
      }
    }
  }
  return count;
}

/// [frame] as the eight bits a channel it is presented in, rounded as
/// `CpuDevice.readback` rounds.
///
/// Bytes rather than the floats behind them, because a sum in a different
/// order is a different float in its last place — addition is commutative
/// and floating-point addition is not associative — and the difference is a
/// ten-millionth of a channel, far under the step the frame is stored in.
List<int> _bytes(Float32List frame) => <int>[
  for (final channel in frame) (channel.clamp(0.0, 1.0) * 255.0).round(),
];

void main() {
  const forward = <int>[0, 1, 2, 3, 4];
  const backward = <int>[4, 3, 2, 1, 0];
  const shuffled = <int>[2, 4, 0, 3, 1];

  test('glass-stack-oit: the stack drawn in any order is the same bytes', () {
    final a = _render(mode: TransparencyMode.weightedBlended, order: forward);
    final b = _render(mode: TransparencyMode.weightedBlended, order: backward);
    final c = _render(mode: TransparencyMode.weightedBlended, order: shuffled);
    expect(_bytes(a), orderedEquals(_bytes(b)));
    expect(_bytes(a), orderedEquals(_bytes(c)));
    // And the floats themselves within rounding of each other everywhere.
    expect(_differing(a, b, by: 1e-5), 0);
    expect(_differing(a, c, by: 1e-5), 0);
  });

  test('glass whose material asks to write depth writes none either', () {
    // A blended material writes no depth unless it says so, so the default
    // panes above cannot tell whether the mode forbids it. These say so.
    // Mutation: drop the `orderIndependent == null &&` in `_encodeNode`. A
    // pane drawn first then hides the ones behind it, and the orders part.
    final a = _render(
      mode: TransparencyMode.weightedBlended,
      order: forward,
      paneDepthWrite: true,
    );
    final b = _render(
      mode: TransparencyMode.weightedBlended,
      order: backward,
      paneDepthWrite: true,
    );
    expect(_bytes(a), orderedEquals(_bytes(b)));
    expect(
      _bytes(a),
      orderedEquals(
        _bytes(_render(mode: TransparencyMode.weightedBlended, order: forward)),
      ),
    );
  });

  test('sorted, the same draws in two orders are different pictures', () {
    // What the test above would be vacuous without: at these alphas and
    // colours the order of the draws shows, so its equality is the mode's.
    final a = _render(mode: TransparencyMode.sorted, order: forward);
    final b = _render(mode: TransparencyMode.sorted, order: backward);
    expect(_differing(a, b), greaterThan(50));
  });

  test('the glass is there, and differs from the sorted blend', () {
    final oit = _render(mode: TransparencyMode.weightedBlended);
    final sorted = _render(
      mode: TransparencyMode.sorted,
      sort: SortMode.backToFront,
    );
    final bare = _render(
      mode: TransparencyMode.weightedBlended,
      panes: const <({double x, double z, double yaw, Vector4 colour})>[],
    );
    // Mutation: return `Vector4.zero()` from `WboitResolveShader`. The
    // resolve then covers nothing and the frame is the bare wall.
    expect(_differing(oit, bare), greaterThan(_size * _size ~/ 3));
    // An approximation of the sorted picture, not a copy of it.
    expect(_differing(oit, sorted), greaterThan(0));
  });

  test('one pane over the wall composites as the sorted blend does', () {
    final one = <({double x, double z, double yaw, Vector4 colour})>[
      _pane(0.0, -1.5, Vector4(0.2, 0.6, 0.9, 0.5)),
    ];
    final oit = _render(mode: TransparencyMode.weightedBlended, panes: one);
    final sorted = _render(mode: TransparencyMode.sorted, panes: one);
    // The weight divides back out of a single layer: its colour over one
    // minus its alpha of the wall, which is what the sorted blend writes.
    // Mutation: resolve without `* coverage` on the colour, and the pane
    // comes out twice as bright as the sorted one.
    expect(_differing(oit, sorted, by: 1.5 / 255.0), 0);
    expect(
      _differing(
        oit,
        _render(
          mode: TransparencyMode.weightedBlended,
          panes: const <({double x, double z, double yaw, Vector4 colour})>[],
        ),
      ),
      greaterThan(0),
    );
  });

  test('without transparent draws it is the sorted frame, byte for byte', () {
    const none = <({double x, double z, double yaw, Vector4 colour})>[];
    // Revealage one everywhere, so the resolve lays a coverage of nought
    // over the scene and the source-over leaves every pixel as it was.
    expect(
      _render(mode: TransparencyMode.weightedBlended, panes: none),
      orderedEquals(_render(mode: TransparencyMode.sorted, panes: none)),
    );
  });

  test('a device without independent blending draws the same picture', () {
    // Twice through the list, once per target, against once with both
    // attached: the same sums and products either way.
    // Mutation: make `CpuEncoder.setBlend` ignore attachment one on the
    // independent device, so the revealage target takes the additive blend.
    expect(
      _render(mode: TransparencyMode.weightedBlended, independentBlend: false),
      orderedEquals(_render(mode: TransparencyMode.weightedBlended)),
    );
  });

  test('sorting stays the default', () {
    expect(const RenderSettings().transparency, TransparencyMode.sorted);
    expect(
      const RenderSettings()
          .copyWith(transparency: TransparencyMode.weightedBlended)
          .transparency,
      TransparencyMode.weightedBlended,
    );
  });
}
