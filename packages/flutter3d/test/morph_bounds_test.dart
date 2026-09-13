/// A morphed mesh is culled against where it morphed to.
///
///     flutter test test/morph_bounds_test.dart
///
/// **A mesh's bounds describe its base vertices, and a morphed vertex is
/// somewhere else.** So a face that opens its jaw past the box around its rest
/// pose is culled while it is on screen, and its shadow falls out of the
/// cascade fitted to that box. Skinning has exactly this trap and closes it
/// with `MeshNode.skinReach`; this is the same closure for the other way a
/// vertex moves.
///
/// The frame below is the cost of not having it, measured rather than
/// imagined: a cube whose one target slides it twelve metres sideways drew
/// **nothing at all** with the camera pointed where it ends up, because the
/// frustum was tested against a half-metre box back at the origin.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 200;
const int _height = 150;

/// How far the target slides the whole cube. Far enough that the base bounds
/// and the morphed ones do not overlap at all.
const double _slide = 12.0;

/// A cube at the origin whose single target slides it [_slide] along X, drawn
/// with the camera looking at where it lands.
///
/// [told] is whether the state is given the target's reach — the thing under
/// test. Without it the node's bounds stay the mesh's own.
({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
  MeshNode node,
})
_scene({required double weight, required bool told}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final base = CuboidShape(size: Vector3.all(1.0)).build();
  final source = MeshData(
    layout: base.layout,
    vertices: base.vertices,
    indices: base.indices,
    morphTargets: <MorphTarget>[
      MorphTarget(
        vertexCount: base.vertexCount,
        name: 'slide',
        positions: Float32List.fromList(<double>[
          for (var v = 0; v < base.vertexCount; v++) ...<double>[_slide, 0, 0],
        ]),
      ),
    ],
  );

  final packed = MorphTexture.pack(source)!;
  final texture = device.createTextureFromPixels(
    width: packed.width,
    height: packed.height,
    format: TextureFormat.r32g32b32a32Float,
    pixels: packed.bytes,
  );
  expect(texture, isNotNull, reason: 'the deltas would not upload');

  final scene = Scene();
  final node =
      MeshNode(
          DeviceMesh.upload(device, source),
          Material(name: 'cube', baseColor: Vector4(0.8, 0.6, 0.4, 1.0)),
          name: 'cube',
        )
        ..morph = (MorphState(
          texture: texture!,
          targetCount: 1,
          reaches: told ? packed.reaches : null,
        )..setWeights(<double>[weight]));
  scene.add(node);

  final sun = LightNode(name: 'sun')..lookAt(Vector3(0.0, -1.0, -0.3));
  scene.add(sun);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 0.7,
      near: 0.1,
      far: 100.0,
    ),
  )..setPosition(_slide, 0.0, 6.0);
  camera.lookAt(Vector3(_slide, 0.0, 0.0));
  scene.add(camera);

  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
    node: node,
  );
}

Future<int> _litPixels(
  ({
    CpuDevice device,
    Renderer renderer,
    Scene scene,
    CameraNode camera,
    MeshNode node,
  })
  it,
) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[RenderView(camera: it.camera)],
    settings: const RenderSettings(),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  final bytes = pixels!.buffer.asUint8List();

  var lit = 0;
  for (var p = 0; p < _width * _height; p++) {
    if (bytes[p * 4] > 40) lit++;
  }
  return lit;
}

void main() {
  test('the bounds grow with the expression', () {
    // Mutation: return nought from `MorphState.reach` and the box stays the
    // half-metre one the mesh was built with.
    final it = _scene(weight: 1.0, told: true);
    expect(it.node.morph!.growth.max.x, closeTo(_slide, 1e-6));
    expect(it.node.worldBounds.max.x, greaterThan(_slide));
    expect(
      it.node.morph!.growth.min.x,
      0.0,
      reason:
          'the target only ever moves the cube one way, and the box '
          'follows the deltas rather than a radius around them',
    );
    expect(
      it.node.morph!.growth.max.y,
      0.0,
      reason: 'nothing moves along Y, so the box does not grow along Y',
    );
  });

  test('and shrink again when the expression relaxes', () {
    final it = _scene(weight: 1.0, told: true);
    expect(it.node.worldBounds.max.x, greaterThan(_slide));

    it.node.morph!.setWeights(const <double>[0.0]);
    expect(it.node.morph!.growth.max.x, 0.0);
    expect(
      it.node.worldBounds.max.x,
      lessThan(1.0),
      reason: 'a box that only ever grows culls nothing and is not a box',
    );
  });

  test('so the mesh is drawn where it morphed to', () async {
    // The whole point, at the level of pixels: the camera is pointed at where
    // the target puts the cube, and the cube has to be there.
    expect(await _litPixels(_scene(weight: 1.0, told: true)), greaterThan(500));
  });

  test('and a state that was told nothing loses the model', () async {
    // The bug this closes, kept as a test so the cost of it stays measured
    // rather than remembered. A `MorphState` with no reaches behaves exactly as
    // every one did before this existed.
    expect(await _litPixels(_scene(weight: 1.0, told: false)), 0);
  });

  test('two half weights reach as far as one whole one', () {
    // The sum rather than the largest: two shapes at half strength can put a
    // vertex where either alone could not.
    final it = _scene(weight: 0.5, told: true);
    expect(it.node.morph!.growth.max.x, closeTo(_slide * 0.5, 1e-6));
  });
}
