/// A batch where each copy wears its own expression looks like a copy per node.
///
///     flutter test test/morph_instanced_test.dart
///
/// **The claim instancing always makes, applied to a new thing.** A batch is
/// supposed to change the cost and not the picture, and until per-instance
/// weights existed a batch could not make this picture at all: the weights came
/// from a uniform, which is the same for every instance in a draw by
/// definition, so a thousand villagers morphed as one.
///
/// So the same three shapes are drawn twice — once as three instances of one
/// batch with three sets of weights, once as three ordinary nodes with a
/// `MorphState` each — and held to a silhouette's worth of each other, which is
/// the budget `instancing_test.dart` already carries for the same reason: the
/// instanced stage multiplies the instance transform into the position and the
/// plain stage folds both into one matrix first.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 180;

/// Weights for the three copies: one shape each, at three strengths, so a
/// picture drawn with the wrong row is a different picture.
const List<List<double>> _weights = <List<double>>[
  <double>[1.0, 0.0],
  <double>[0.0, 1.0],
  <double>[0.5, 0.5],
];

/// Where the three stand.
List<Matrix4> _places() => <Matrix4>[
  for (var i = 0; i < 3; i++)
    Matrix4.identity()..setTranslationRaw((i - 1) * 2.4, 0.0, 0.0),
];

MeshData _shapes() {
  final base = CuboidShape(size: Vector3.all(1.2)).build();
  Float32List delta(double x, double y) => Float32List.fromList(<double>[
    for (var v = 0; v < base.vertexCount; v++) ...<double>[x, y, 0.0],
  ]);
  return MeshData(
    layout: base.layout,
    vertices: base.vertices,
    indices: base.indices,
    morphTargets: <MorphTarget>[
      MorphTarget(
        vertexCount: base.vertexCount,
        name: 'lean',
        positions: delta(0.9, 0.0),
      ),
      MorphTarget(
        vertexCount: base.vertexCount,
        name: 'rise',
        positions: delta(0.0, 0.9),
      ),
    ],
  );
}

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _scene({
  required bool batched,
  bool weighted = true,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final source = _shapes();
  final mesh = DeviceMesh.upload(device, source);
  final packed = MorphTexture.pack(source)!;
  final deltas = device.createTextureFromPixels(
    width: packed.width,
    height: packed.height,
    format: TextureFormat.r32g32b32a32Float,
    pixels: packed.bytes,
  );
  expect(deltas, isNotNull, reason: 'the deltas would not upload');

  final material = Material(
    name: 'stone',
    baseColor: Vector4(0.7, 0.6, 0.5, 1.0),
    roughness: 0.8,
  );
  final scene = Scene();
  final places = _places();

  if (batched) {
    final batch = InstancedMeshNode(
      mesh,
      material,
      capacity: places.length,
      name: 'crowd',
    );
    for (var i = 0; i < places.length; i++) {
      batch.addInstance(places[i]);
      if (weighted) batch.setMorphWeights(i, _weights[i]);
    }
    // The deltas are the batch's, shared by every copy; only the weights differ.
    batch.morph = MorphState(texture: deltas!, targetCount: 2);
    scene.add(batch);
  } else {
    for (var i = 0; i < places.length; i++) {
      scene.add(
        MeshNode(mesh, material, name: 'copy$i')
          ..setLocalMatrix(places[i])
          ..morph = (MorphState(texture: deltas!, targetCount: 2)
            ..setWeights(_weights[i])),
      );
    }
  }

  final sun = LightNode(name: 'sun');
  sun.lookAt(Vector3(-0.6, -1.0, -0.4));
  scene.add(sun);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 100.0,
    ),
  )..setPosition(0.0, 1.6, 8.0);
  camera.lookAt(Vector3.zero());
  scene.add(camera);

  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

/// The same three copies as one batch with no per-instance weights, wearing
/// [shared] through the uniform every instance of a draw has in common.
({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera})
_sceneWithoutInstanceWeights(List<double> shared) {
  final it = _scene(batched: true, weighted: false);
  final batch = it.scene.meshes.whereType<InstancedMeshNode>().single;
  batch.morph!.setWeights(shared);
  return it;
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
  const total = _width * _height;

  test('three instances wear three expressions', () async {
    // Mutation: read the weights texture at a fixed row rather than at
    // `instance` — all three copies take the first one's shape, and this rises
    // from a silhouette to whole cubes.
    final batched = await _draw(_scene(batched: true));
    final apart = await _draw(_scene(batched: false));

    final differing = _differing(batched, apart) / total * 100.0;
    expect(
      differing,
      lessThan(1.5),
      reason: 'the batch drew a different set of shapes from the nodes',
    );
  });

  test('and it is the weights doing it, not the transforms', () async {
    // The control the test above needs: if every instance wore the same shape,
    // the two pictures would still differ — but so would a batch against
    // itself with the weights taken away. This is that second difference, and
    // it has to be large, or the first assertion is measuring nothing.
    final withWeights = await _draw(_scene(batched: true));

    final flat = _scene(batched: true);
    for (final node in flat.scene.meshes) {
      if (node is InstancedMeshNode) {
        for (var i = 0; i < node.count; i++) {
          node.setMorphWeights(i, const <double>[0.0, 0.0]);
        }
      }
    }
    final withoutWeights = await _draw(flat);

    expect(
      _differing(withWeights, withoutWeights) / total * 100.0,
      greaterThan(3.0),
      reason: 'the per-instance weights changed nothing',
    );
  });

  test('a batch that sets no weights draws the batch-wide shape', () async {
    // The fall-through, and it is the case every existing batch is in:
    // `MorphInstanceInfo.instance_params.x` is nought, the stage reads the
    // uniform, and a batch that never heard of this feature morphs exactly as
    // it did before it existed. Mutation: make the flag always one and this
    // reads black — the shader samples a stand-in texture nobody filled.
    final byUniform = _scene(batched: true);
    final batch = byUniform.scene.meshes.whereType<InstancedMeshNode>().single;
    expect(
      batch.hasInstanceMorphWeights,
      isTrue,
      reason: 'the fixture sets them, and this test is about taking them away',
    );

    // A batch with no per-instance weights at all, wearing the first shape
    // through the uniform every copy shares.
    final plain = _sceneWithoutInstanceWeights(<double>[1.0, 0.0]);
    // The same picture reached the other way: every copy given that shape of
    // its own.
    final each = _scene(batched: true);
    final crowd = each.scene.meshes.whereType<InstancedMeshNode>().single;
    for (var i = 0; i < crowd.count; i++) {
      crowd.setMorphWeights(i, const <double>[1.0, 0.0]);
    }

    expect(_differing(await _draw(plain), await _draw(each)), 0);
  });

  test('reads back the weights it was given', () {
    // Not decoration: a game that keeps a face's expression on the batch has
    // to be able to ask what it is, and a shorter list than the maximum leaves
    // the rest at nought rather than at whatever was there.
    final it = _scene(batched: true);
    final batch = it.scene.meshes.whereType<InstancedMeshNode>().single;

    expect(batch.morphWeightsOf(1).take(2), _weights[1]);
    expect(
      batch.morphWeightsOf(1).skip(2).every((w) => w == 0.0),
      isTrue,
      reason: 'a short list leaves the rest at nought',
    );

    batch.setMorphWeights(1, const <double>[0.1]);
    expect(batch.morphWeightsOf(1).first, closeTo(0.1, 1e-6));
    expect(batch.morphWeightsOf(1)[1], 0.0, reason: 'the old second weight');
  });

  test('a weight set to what it already was rebuilds nothing', () async {
    // The skip that makes this affordable: a texture cannot be written after
    // it is made, so a batch that rewrote its weights every frame would build
    // a texture every frame. Setting a weight to the value it already holds is
    // the case a game hits constantly — a crowd where most faces are still.
    final it = _scene(batched: true);
    final batch = it.scene.meshes.whereType<InstancedMeshNode>().single;

    final first = batch.instanceMorphWeights(it.device);
    batch.setMorphWeights(0, _weights[0]);
    expect(
      identical(batch.instanceMorphWeights(it.device), first),
      isTrue,
      reason: 'an unchanged weight rebuilt the texture',
    );

    batch.setMorphWeights(0, const <double>[0.25, 0.25]);
    expect(
      identical(batch.instanceMorphWeights(it.device), first),
      isFalse,
      reason: 'a changed weight did not rebuild the texture',
    );
  });
}
