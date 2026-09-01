/// A field drawn as one batch looks like the same field drawn as nodes.
///
///     flutter test test/instancing_test.dart
///
/// The whole claim of instancing is that it changes the cost and not the
/// picture. So the picture is held: a grid of cubes under a sun that casts,
/// drawn once as an `InstancedMeshNode` and once as a node per cube, on the
/// backend that can be read back with no GPU. The two are not byte-identical
/// — the instanced stage multiplies the instance transform into the position
/// before the node's matrix, the plain stage folds both into one matrix
/// first, and the rounding lands a silhouette pixel over here and there — so
/// the budget is a silhouette's worth, the same kind of number the cross-
/// backend comparisons carry.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 180;
const int _side = 4;

/// The same placements for both scenes: a grid, each cube turned and scaled
/// by something the row and column decide, so no two look alike.
List<Matrix4> _placements() => <Matrix4>[
  for (var row = 0; row < _side; row++)
    for (var col = 0; col < _side; col++)
      Matrix4.identity()
        ..setTranslationRaw((col - 1.5) * 2.0, 0.5, (row - 1.5) * 2.0)
        ..rotateY((row * _side + col) * 0.37)
        ..scaleByDouble(
          0.6 + 0.1 * ((row + col) % 3),
          0.6 + 0.1 * ((row + col) % 3),
          0.6 + 0.1 * ((row + col) % 3),
          1.0,
        ),
];

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _field(
  bool instanced,
) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();
  final cube = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
  );
  final material = Material(
    name: 'stone',
    baseColor: Vector4(0.7, 0.6, 0.5, 1.0),
    roughness: 0.8,
  );

  // The batch and the nodes both hang off the same parent, placed off the
  // origin, so the node's own transform is exercised as well as the
  // instances': an instance is relative to its node, and a stage that read
  // it as world space would draw the field in the wrong place.
  final parent = SceneNode(name: 'field')..setPosition(0.5, 0.0, -0.25);
  scene.root.add(parent);
  final placements = _placements();
  if (instanced) {
    final batch = InstancedMeshNode(
      cube,
      material,
      capacity: placements.length,
      name: 'batch',
    );
    for (final placement in placements) {
      batch.addInstance(placement);
    }
    parent.add(batch);
  } else {
    for (final placement in placements) {
      final node = MeshNode(cube, material)..setLocalMatrix(placement);
      parent.add(node);
    }
  }

  // Something to receive the shadows, or the test would not know whether the
  // batch cast any.
  scene.root.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(14.0, 0.2, 14.0)).build(),
        ),
        Material(name: 'ground', baseColor: Vector4(0.4, 0.45, 0.4, 1.0)),
        name: 'ground',
      )
      ..setPosition(0.0, -0.1, 0.0)
      ..castsShadow = false,
  );

  final sun = LightNode(name: 'sun')..castsShadow = true;
  sun.lookAt(Vector3(-0.6, -1.0, -0.4));
  scene.root.add(sun);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 100.0,
    ),
  )..setPosition(6.0, 6.0, 8.0);
  camera.lookAt(Vector3(0.0, 0.0, 0.0));
  scene.root.add(camera);

  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it,
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
  return pixels!.buffer.asUint8List();
}

/// Pixels where any channel differs by more than [tolerance].
int _differing(Uint8List a, Uint8List b, {int tolerance = 8}) {
  var count = 0;
  for (var p = 0; p < _width * _height; p++) {
    final at = p * 4;
    for (var c = 0; c < 3; c++) {
      if ((a[at + c] - b[at + c]).abs() > tolerance) {
        count++;
        break;
      }
    }
  }
  return count;
}

void main() {
  test('a batch draws the field the nodes draw', () async {
    final asNodes = _field(false);
    final asBatch = _field(true);

    final nodes = await _draw(asNodes);
    final batch = await _draw(asBatch);

    final differing = _differing(nodes, batch);
    final fraction = differing / (_width * _height);
    expect(
      fraction,
      lessThan(0.002),
      reason:
          '$differing pixels differ, ${(fraction * 100).toStringAsFixed(3)}%',
    );

    // And the field is actually there: a frame of ground alone would agree
    // with itself perfectly.
    final empty = _field(true);
    empty.scene.root.remove(empty.scene.root.children.first);
    final blank = await _draw(empty);
    expect(_differing(batch, blank), greaterThan(_width * _height ~/ 50));
  });

  test('a batch is one draw where the nodes are many', () async {
    final asNodes = _field(false);
    final asBatch = _field(true);

    final nodes = asNodes.renderer.render(
      width: _width,
      height: _height,
      scene: asNodes.scene,
      views: <RenderView>[RenderView(camera: asNodes.camera)],
      settings: const RenderSettings(),
    );
    final batch = asBatch.renderer.render(
      width: _width,
      height: _height,
      scene: asBatch.scene,
      views: <RenderView>[RenderView(camera: asBatch.camera)],
      settings: const RenderSettings(),
    );

    expect(
      nodes.drawCalls - batch.drawCalls,
      _side * _side - 1,
      reason:
          'sixteen cubes as one draw instead of sixteen, in the colour '
          'pass; the shadow pass has the same saving and is counted apart',
    );
  });

  test('an instance colour tints its copy alone', () async {
    final it = _field(true);
    final plain = await _draw(it);
    final batch =
        it.scene.root.children.first.children.first as InstancedMeshNode;

    batch.setColor(5, Vector4(1.0, 0.0, 0.0, 1.0));
    final tinted = await _draw(it);

    final differing = _differing(plain, tinted, tolerance: 4);
    expect(differing, greaterThan(20), reason: 'one cube changed colour');
    expect(
      differing,
      lessThan(_width * _height ~/ 16),
      reason:
          'and only one: a tint that reached the whole batch would '
          'recolour a sixteenth of the frame or more',
    );
  });
}
