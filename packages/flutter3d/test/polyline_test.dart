/// A polyline of constant screen width, with joins — `gfx-86n`.
///
///     flutter test test/polyline_test.dart
///
/// One test per clause of the row's acceptance, each measured in rendered
/// pixels rather than read off the vertices that went in — the same rule
/// `overlay_ribbon_width_test.dart` holds `MeshOverlay.ribbon` to, and for the
/// same reason: the vertices say what was asked for, and the picture is what
/// the vertex stage made of it.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 96;

/// What a frame came back as, with a way to ask about one pixel.
final class _Frame {
  _Frame(this.bytes, this.width);

  final Uint8List bytes;
  final int width;

  (int, int, int) at(int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i], bytes[i + 1], bytes[i + 2]);
  }

  /// Anything the line or the scene put there, against a black clear the
  /// composite lifts only a little off zero.
  bool covered(int x, int y) {
    final (r, g, b) = at(x, y);
    return r > 64 || g > 64 || b > 64;
  }
}

/// Renders [nodes] from a camera at [eye] looking at the origin.
Future<_Frame> _render(
  CpuDevice device,
  List<SceneNode> nodes, {
  Vector3? eye,
  int size = _size,
}) async {
  final renderer = Renderer.create(device: device);
  final scene = Scene();
  for (final node in nodes) {
    scene.add(node);
  }
  final camera = CameraNode()
    ..setPosition(
      (eye ?? Vector3(0, 0, 4)).x,
      (eye ?? Vector3(0, 0, 4)).y,
      (eye ?? Vector3(0, 0, 4)).z,
    )
    ..lookAt(Vector3.zero());
  scene.add(camera);

  final frame = renderer.render(
    width: size,
    height: size,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0, 0, 0, 1)),
    ],
    settings: const RenderSettings(),
  );
  final bytes = await device.readPixels(frame.frame);
  return _Frame(bytes!.buffer.asUint8List(), size);
}

CpuDevice _device([int size = _size]) => CpuDevice(
  width: size,
  height: size,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

MeshNode _line(
  CpuDevice device,
  List<Vector3> points, {
  double width = 16,
  List<Vector4>? colours,
  int viewport = _size,
}) => MeshNode(
  DeviceMesh.upload(
    device,
    buildPolyline(points, width: width, colours: colours),
  ),
  Material.polyline(
    viewportWidth: viewport.toDouble(),
    viewportHeight: viewport.toDouble(),
  ),
);

/// How many pixels of column [x] the band covers.
int _thickness(_Frame frame, int x) {
  var count = 0;
  for (var y = 0; y < frame.width; y++) {
    if (frame.covered(x, y)) count++;
  }
  return count;
}

void main() {
  test('a 90 degree elbow is one band, with the corner filled', () async {
    // The line comes in from the left along the horizontal and leaves upwards,
    // turning at the centre of the frame. Two independent quads — what
    // `MeshOverlay.ribbon` draws — cover the horizontal and the vertical bands
    // and leave the square on the outside of the turn empty: below and to the
    // right of the centre, a half width each way. That square is what a mitre
    // fills, so a pixel in it is the whole question.
    const inside = _size ~/ 2 + 4; // half width is 8 pixels
    final elbow = <Vector3>[
      Vector3(-1, 0, 0),
      Vector3.zero(),
      Vector3(0, 1, 0),
    ];

    final device = _device();
    final joined = await _render(device, <SceneNode>[_line(device, elbow)]);

    final separate = _device();
    final apart = await _render(separate, <SceneNode>[
      _line(separate, elbow.sublist(0, 2)),
      _line(separate, elbow.sublist(1)),
    ]);

    expect(
      apart.covered(inside, inside),
      isFalse,
      reason:
          'two separate segments already cover the outer corner, so this '
          'test would pass without a join',
    );
    expect(
      joined.covered(inside, inside),
      isTrue,
      reason: 'the outer corner of the elbow is a gap',
    );
    // And the mitre stops where the two outer edges meet rather than running
    // on: well past the corner is still background.
    expect(joined.covered(_size ~/ 2 + 14, _size ~/ 2 + 14), isFalse);
  });

  test('the colour is read per point', () async {
    // Red at the left end, blue at the right, and a gradient between — the
    // shape a slope or a speed is drawn with, and the one a colour per segment
    // could not produce.
    final device = _device();
    final frame = await _render(device, <SceneNode>[
      _line(
        device,
        <Vector3>[Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0)],
        colours: <Vector4>[Vector4(1, 0, 0, 1), Vector4(0, 0, 1, 1)],
      ),
    ]);

    const row = _size ~/ 2;
    final (leftR, _, leftB) = frame.at(20, row);
    final (middleR, _, middleB) = frame.at(_size ~/ 2, row);
    final (rightR, _, rightB) = frame.at(_size - 21, row);

    expect(leftR, greaterThan(leftB), reason: 'the left end is not red');
    expect(rightB, greaterThan(rightR), reason: 'the right end is not blue');
    // Between the two, and both halves of it present.
    expect(middleR, inExclusiveRange(rightR, leftR));
    expect(middleB, inExclusiveRange(leftB, rightB));
  });

  test('a line behind a hill is hidden by it', () async {
    // No bias toward the eye: a box between the camera and the middle of the
    // line hides that part of it, and the ends that stick out either side are
    // still drawn. `MeshOverlay`'s twelve pixels of bias would draw the line
    // straight through.
    final line = <Vector3>[Vector3(-1.5, 0, -0.5), Vector3(1.5, 0, -0.5)];
    Future<_Frame> draw({required bool hill}) async {
      final device = _device();
      return _render(device, <SceneNode>[
        _line(
          device,
          line,
          colours: <Vector4>[Vector4(1, 1, 0, 1), Vector4(1, 1, 0, 1)],
        ),
        if (hill)
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(0.8, 0.8, 0.4)).build(),
            ),
            Material(
              lighting: LightingModel.unlit,
              baseColor: Vector4(0, 0.6, 0, 1),
            ),
          ),
      ]);
    }

    final open = await draw(hill: false);
    final hidden = await draw(hill: true);
    const middle = _size ~/ 2;

    // Channels against each other rather than against fixed numbers: the
    // composite lifts every channel off zero, so yellow comes back with some
    // blue in it and green with some red.
    final (r, _, b) = open.at(middle, middle);
    expect(r, greaterThan(128), reason: 'the line is not there to hide');
    expect(r, greaterThan(b));
    final (hr, hg, hb) = hidden.at(middle, middle);
    expect(hg, greaterThan(hr), reason: 'the line drew over the hill');
    expect(hg, greaterThan(hb));

    // The ends stick out past the box on both sides and are still yellow. Found
    // in the open frame rather than guessed, so the test says where the line
    // is instead of assuming a field of view.
    var end = 0;
    while (!open.covered(end, middle)) {
      end++;
    }
    final (er, eg, _) = hidden.at(end + 2, middle);
    expect(er, greaterThan(128), reason: 'the end of the line is hidden too');
    expect(eg, greaterThan(128));
  });

  test('a camera move redraws without rebuilding, at the same width', () async {
    // One mesh, uploaded once, drawn from two distances. The line's width is a
    // number of pixels, so it is the same number at both — which is only true
    // if the widening happened in the vertex stage against the new camera, since
    // the vertices themselves did not change.
    final device = _device();
    final node = _line(device, <Vector3>[
      Vector3(-3, 0, 0),
      Vector3(3, 0, 0),
    ], width: 10);
    final buffer = (node.mesh as DeviceMesh).vertices;

    final near = await _render(device, <SceneNode>[node]);
    final far = await _render(device, <SceneNode>[node], eye: Vector3(0, 0, 9));

    expect(
      identical((node.mesh as DeviceMesh).vertices, buffer),
      isTrue,
      reason: 'the mesh was replaced between frames',
    );
    final nearWidth = _thickness(near, _size ~/ 2);
    final farWidth = _thickness(far, _size ~/ 2);
    expect(nearWidth, inInclusiveRange(9, 11));
    expect(farWidth, nearWidth, reason: 'near $nearWidth, far $farWidth');
  });

  test('a resize is one parameter written, and the width follows', () async {
    // The viewport is the one number the vertex stage needs that no engine
    // block carries, so it travels on the material. Writing a new size into
    // that list is the whole of a resize: the mesh is the same one.
    final small = _device(64);
    final node = _line(
      small,
      <Vector3>[Vector3(-3, 0, 0), Vector3(3, 0, 0)],
      width: 10,
      viewport: 64,
    );
    final at64 = await _render(small, <SceneNode>[node], size: 64);
    expect(_thickness(at64, 32), inInclusiveRange(9, 11));

    // The same node, on a larger target, with its viewport written and not its
    // vertices.
    final large = _device(128);
    final moved = MeshNode(
      DeviceMesh.upload(
        large,
        buildPolyline(<Vector3>[
          Vector3(-3, 0, 0),
          Vector3(3, 0, 0),
        ], width: 10),
      ),
      node.material,
    );
    node.material.polylineViewport!
      ..[0] = 128
      ..[1] = 128;
    final at128 = await _render(large, <SceneNode>[moved], size: 128);
    expect(_thickness(at128, 64), inInclusiveRange(9, 11));
  });

  test('fewer than two points is refused by name', () {
    expect(
      () => buildPolyline(<Vector3>[Vector3.zero()], width: 4),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('at least two points'),
        ),
      ),
    );
  });
}
