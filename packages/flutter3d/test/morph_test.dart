/// A mesh morphed by the vertex stage looks like the same mesh morphed by hand.
///
///     flutter test test/morph_test.dart
///
/// **The transcription of `lib/morph.glsl` had nothing looking at a pixel.**
/// `cpu_shaders_morph.dart` reads deltas out of a texture by vertex index and
/// adds them, and every claim about it so far was a claim about the arithmetic
/// in the file rather than about the picture the rasteriser drew. This is the
/// picture: the same shape reached two ways, once by weighting a target at draw
/// time and once by `MorphBlend` folding the same delta into the vertices
/// before they were ever uploaded. Those must agree, and a mesh at weight
/// nought must differ from both — otherwise the deltas were never read and
/// three tests would pass on a stage that does nothing.
///
/// The budget is a silhouette's worth for the same reason `instancing_test`
/// carries one: the morph adds in the vertex stage after the attribute is read
/// and `MorphBlend` adds before, so a rounded position lands an edge pixel one
/// place or the other.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 180;

/// How far the target lifts the upper half. Large on purpose: a delta of a
/// millimetre would be a test that passes whether or not it was applied.
const double _lift = 0.6;

MeshData _cube() => CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build();

/// One target that raises every vertex above the middle and leaves the rest.
///
/// Asymmetric, so the morphed cube is a shape and not a translation: a stage
/// that added the delta to every vertex alike would move the whole cube and
/// still differ from the base, which is exactly the failure a symmetric target
/// would let through.
MorphTarget _riseTarget(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final positionAt = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final deltas = Float32List(mesh.vertexCount * 3);

  for (var v = 0; v < mesh.vertexCount; v++) {
    final y = mesh.vertices[v * stride + positionAt + 1];
    deltas[v * 3 + 1] = y > 0.0 ? _lift : 0.0;
  }
  return MorphTarget(
    vertexCount: mesh.vertexCount,
    name: 'rise',
    positions: deltas,
  );
}

/// A scene holding one cube, either morphed at draw time or already deformed.
///
/// [weight] drives the target through a [MorphState]; [preBlended] instead
/// uploads the vertices `MorphBlend` produced and binds no morph at all.
({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _one({
  double weight = 0.0,
  bool preBlended = false,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final base = _cube();
  final target = _riseTarget(base);
  final source = MeshData(
    layout: base.layout,
    vertices: base.vertices,
    indices: base.indices,
    morphTargets: <MorphTarget>[target],
  );

  final scene = Scene();
  final material = Material(
    name: 'stone',
    baseColor: Vector4(0.7, 0.6, 0.5, 1.0),
    roughness: 0.8,
  );

  final MeshNode node;
  if (preBlended) {
    final blend = MorphBlend(source)..blend(<double>[weight]);
    node = MeshNode(
      DeviceMesh.upload(
        device,
        MeshData(
          layout: source.layout,
          vertices: blend.vertices,
          indices: source.indices,
        ),
      ),
      material,
      name: 'cube',
    );
  } else {
    final packed = MorphTexture.pack(source)!;
    final texture = device.createTextureFromPixels(
      width: packed.width,
      height: packed.height,
      format: TextureFormat.r32g32b32a32Float,
      pixels: packed.bytes,
    );
    expect(texture, isNotNull, reason: 'the deltas would not upload');
    node = MeshNode(DeviceMesh.upload(device, source), material, name: 'cube')
      ..morph = (MorphState(texture: texture!, targetCount: 1)
        ..setWeights(<double>[weight]));
  }
  scene.root.add(node);

  final sun = LightNode(name: 'sun');
  sun.lookAt(Vector3(-0.6, -1.0, -0.4));
  scene.root.add(sun);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 100.0,
    ),
  )..setPosition(2.4, 1.8, 3.2);
  camera.lookAt(Vector3(0.0, 0.2, 0.0));
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
  const int total = _width * _height;

  test('a weighted target moves the picture', () async {
    final rest = await _draw(_one());
    final morphed = await _draw(_one(weight: 1.0));

    final moved = _differing(rest, morphed) / total * 100.0;
    expect(
      moved,
      greaterThan(2.0),
      reason: 'the deltas never reached the vertex stage',
    );
  });

  test('and lands where the host blend puts it', () async {
    // The claim the transcription exists to keep. Mutation: swap the row
    // arithmetic in `applyMorph` — read row `i` instead of `i * kMorphRows` —
    // and the first test still passes while this one does not.
    final morphed = await _draw(_one(weight: 1.0));
    final blended = await _draw(_one(weight: 1.0, preBlended: true));

    final apart = _differing(morphed, blended) / total * 100.0;
    expect(
      apart,
      lessThan(0.5),
      reason: 'the vertex stage and MorphBlend disagree about the shape',
    );
  });

  test('a half weight lands between the two', () async {
    // Linear in the weight, which is the whole reason deltas are stored
    // rather than poses.
    final rest = await _draw(_one());
    final half = await _draw(_one(weight: 0.5));
    final full = await _draw(_one(weight: 1.0));

    expect(_differing(half, rest), greaterThan(0));
    expect(_differing(half, full), greaterThan(0));
    expect(
      _differing(half, _differing(rest, full) > 0 ? rest : full),
      lessThan(_differing(rest, full)),
      reason: 'half a weight should be nearer either end than they are apart',
    );
  });

  test('a weight of nought costs nothing at all', () async {
    // A mesh that carries targets and weights none of them has to draw
    // exactly as a mesh that carries none — a stage that added a zero-weighted
    // delta anyway would drift every model with a face in it.
    final withTargets = await _draw(_one());
    final plain = await _draw(_one(weight: 0.0, preBlended: true));
    expect(_differing(withTargets, plain), 0);
  });
}
