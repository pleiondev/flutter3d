/// The x-ray stage drawn through this backend, pixel by pixel.
///
/// The fake device pins the *sequence* the stage emits; this pins what the
/// sequence does to a picture when every call is honoured, on the one backend
/// where a picture can be drawn in a test. Four questions, one per case: a
/// cube nothing hides keeps its own colour everywhere, a cube a wall hides
/// comes back as the silhouette colour where the wall is, a hidden cube's
/// silhouette stops at a *second* marked cube standing in front of it, and a
/// glass wall hides nothing at all.
///
/// **The third case is the one the stencil exists for**, and it is the only
/// one here that fails without it. With a single marked node the mark
/// protects nothing a depth test would not: the node's back faces are culled,
/// and its own visible fragments fail `greater` against the depth they wrote.
/// Turning the silhouette's compare to `always` leaves the first two cases
/// green and takes this one down by 255 pixels.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;
const int _layer = 1 << 2;

/// The silhouette colour, chosen so no lit surface here can reach it: pure
/// green, against an unlit white cube and an unlit grey wall.
final Vector3 _silhouette = Vector3(0.0, 1.0, 0.0);

bool _isSilhouette(int r, int g, int b) => g > 200 && r < 60 && b < 60;
bool _isWhite(int r, int g, int b) => r > 200 && g > 200 && b > 200;
bool _isNear(int r, int g, int b) => b > 200 && r < 60 && g < 60;

/// One frame of a cube, optionally behind a wall, optionally with a second
/// cube standing in front of the wall and across part of the first.
///
/// [near] adds that second cube — pure blue, unlit, half the size and closer,
/// placed so its footprint covers the lower left of the far cube's. [markNear]
/// is whether it is on the x-ray layer, and it is the mutation the third case
/// is built on rather than a convenience: an unmarked node in front is exactly
/// what the far cube's silhouette is allowed to paint over.
///
/// [glass] makes the wall transparent, which is the fourth case's whole
/// fixture: a transparent surface writes no depth, and depth is the only
/// thing the paint's `greater` test can read.
Future<Uint8List> _frame({
  required bool wall,
  required bool xray,
  bool near = false,
  bool markNear = true,
  bool glass = false,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();
  scene.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build(),
        ),
        Material(
          name: 'cube',
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'cube',
      )
      ..layerMask = 1 | _layer
      ..setPosition(0.0, 0.0, -8.0),
  );
  if (wall) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(6.0, 6.0, 0.2)).build(),
        ),
        Material(
          name: 'wall',
          baseColor: Vector4(0.3, 0.3, 0.3, glass ? 0.6 : 1.0),
          lighting: LightingModel.unlit,
          alphaMode: glass ? MaterialAlphaMode.blend : MaterialAlphaMode.opaque,
        ),
        name: 'wall',
      )..setPosition(0.0, 0.0, -5.0),
    );
  }
  if (near) {
    scene.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
          ),
          Material(
            name: 'near',
            baseColor: Vector4(0.0, 0.0, 1.0, 1.0),
            lighting: LightingModel.unlit,
          ),
          name: 'near',
        )
        ..layerMask = markNear ? 1 | _layer : 1
        // Down and to the left of the far cube's centre and nearer than the
        // wall: a corner of it lands inside the far cube's footprint and the
        // rest hangs outside, so a silhouette that respects it is notched
        // rather than merely smaller.
        ..setPosition(-0.18, -0.27, -3.0),
    );
  }
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 50.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -8.0));
  scene.add(camera);

  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      shadows: const ShadowSettings(enabled: false),
      tonemap: false,
      exposure: 1.0,
      xray: XraySettings(color: _silhouette, layerMask: xray ? _layer : 0),
    ),
  );
  final bytes = await device.readPixels(result.frame);
  return bytes!.buffer.asUint8List();
}

int _count(Uint8List rgba, bool Function(int, int, int) wanted) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (wanted(rgba[i], rgba[i + 1], rgba[i + 2])) count++;
  }
  return count;
}

void main() {
  test('a cube nothing hides keeps its own colour everywhere', () async {
    // The mark has to land on every visible pixel of the cube, or the paint
    // that follows lands there instead: a visible surface painted flat is
    // the stage getting its two depth tests the wrong way round, or the
    // mark and the paint disagreeing about where the surface is.
    final plain = await _frame(wall: false, xray: false);
    final marked = await _frame(wall: false, xray: true);
    expect(_count(marked, _isSilhouette), 0);
    expect(
      _count(marked, _isWhite),
      _count(plain, _isWhite),
      reason: 'the cube is the same size with the stage on and off',
    );
  });

  test('a cube a wall hides comes back as the silhouette colour', () async {
    final hidden = await _frame(wall: true, xray: false);
    final seen = await _frame(wall: true, xray: true);
    expect(_count(hidden, _isSilhouette), 0, reason: 'off is off');
    expect(_count(hidden, _isWhite), 0, reason: 'the wall hides the cube');
    // Every pixel of the cube's footprint, since the wall hides all of it —
    // which is the same number of pixels the cube has without the wall.
    final footprint = _count(await _frame(wall: false, xray: false), _isWhite);
    expect(_count(seen, _isSilhouette), footprint);
  });

  test('a silhouette stops at a marked cube standing in front of it', () async {
    // The cross-node half of the stencil's job, which one marked node cannot
    // show. Both frames below hide the far cube behind the wall and put a
    // second cube in front; the only difference is whether that second cube
    // is on the x-ray layer, and therefore whether its visible pixels carry
    // a mark for the far cube's paint to be rejected by.
    final footprint = _count(await _frame(wall: false, xray: false), _isWhite);
    final face = _count(
      await _frame(wall: true, xray: false, near: true),
      _isNear,
    );

    // Unmarked: nothing holds the near cube, so the far cube's hidden
    // fragments paint straight across it. This is the picture the stencil
    // exists to prevent, asserted rather than described — without it the
    // case below could pass on a scene where the two never overlapped.
    final over = await _frame(
      wall: true,
      xray: true,
      near: true,
      markNear: false,
    );
    expect(
      _count(over, _isSilhouette),
      footprint,
      reason: 'an unmarked node in front is painted over, all of it',
    );
    expect(
      _count(over, _isNear),
      lessThan(face),
      reason:
          'the two footprints have to overlap for any of this to mean '
          'anything, and this is what says by how much',
    );

    // Marked: every mark is written before any paint, so the near cube's
    // face is held and the silhouette comes back notched.
    final held = await _frame(wall: true, xray: true, near: true);
    expect(
      _count(held, _isNear),
      face,
      reason: 'not one silhouette pixel lands on a marked node\'s lit face',
    );
    expect(
      _count(held, _isSilhouette),
      footprint - (face - _count(over, _isNear)),
      reason: 'the silhouette lost exactly the pixels the near cube kept',
    );
  });

  test('only opaque geometry hides anything', () async {
    // The paint tests `greater` against the depth buffer, and a transparent
    // surface writes no depth — so a glass wall hides nothing from the stage
    // however solid it looks. That is the right answer, since the cube can be
    // seen through it, and it is pinned here because the picture and the
    // reason are far apart: the report it produces is "the sensor stopped
    // working in the greenhouse".
    final behindGlass = await _frame(wall: true, xray: true, glass: true);
    expect(_count(behindGlass, _isSilhouette), 0);
    // The same wall, opaque, for the contrast that says the fixture is doing
    // what it claims rather than failing to draw a cube.
    expect(
      _count(await _frame(wall: true, xray: true), _isSilhouette),
      greaterThan(0),
    );
  });
}
