/// A model edited while the game runs is drawn in the nodes the game holds.
///
///     flutter test test/model_adopt_test.dart
///
/// `ModelInstance.adopt` matches surfaces by the name of the node that draws
/// them and their place there, so the nodes survive and only what they draw
/// changes. Drawn on the CPU device, because "the new model is on screen" is
/// a claim about pixels.
///
/// Mutation: drop the `selectVariant` call at the end of `adopt` and the
/// frame stays red; key the slots on the part's name instead of the node's
/// and the renamed-part case finds nothing to swap.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 32;

MeshData _quad(double half) => MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List.fromList(<double>[
    // position, normal, texcoord, tangent, colour
    -half, -half, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1,
    half, -half, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1,
    half, half, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1,
    -half, half, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1,
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2, 0, 2, 3]),
);

/// A hull and, when [withFlag], a flag: one quad each, unlit in [color].
PlainModelDocument _ship(
  Vector4 color, {
  bool withFlag = false,
  String hull = 'hull',
  String? partName,
}) => PlainModelDocument(
  surfaces: <ModelSurface>[
    ModelSurface(mesh: _quad(1.0), materialIndex: 0, name: partName),
    if (withFlag) ModelSurface(mesh: _quad(0.1), materialIndex: 0),
  ],
  materials: <SurfaceMaterial>[
    SurfaceMaterial(baseColor: _fromSrgb(color), unlit: true),
  ],
  nodes: <ModelNode>[
    ModelNode(name: hull, surfaces: <int>[0]),
    if (withFlag) ModelNode(name: 'flag', surfaces: <int>[1]),
  ],
);

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final flat = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(Uint8List.fromList(<int>[128, 128, 255, 255])),
  );
  return (
    device: device,
    renderer: Renderer.create(device: device, fallbackNormal: flat),
  );
}

Future<List<int>> _center(
  ({CpuDevice device, Renderer renderer}) engine,
  Scene scene,
) async {
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 3.0)
    ..lookAt(Vector3.zero());
  final frame = engine.renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = (await engine.device.readback(
    frame.frame,
  )).buffer.asUint8List();
  final i = (_size ~/ 2 * _size + _size ~/ 2) * 4;
  return pixels.sublist(i, i + 4);
}

void main() {
  test('the new model is drawn in the nodes the game already holds', () async {
    final engine = _engine();
    final red = await ModelAsset.fromDocument(
      _ship(Vector4(1.0, 0.0, 0.0, 1.0)),
      device: engine.device,
    );
    final blue = await ModelAsset.fromDocument(
      _ship(Vector4(0.0, 0.0, 1.0, 1.0)),
      device: engine.device,
    );
    final scene = Scene();
    final ship = red.instantiate(scene);
    final hull = ship.nodes.single..setPosition(0.0, 0.0, 0.5);
    final mesh = ship.meshes.single;
    expect((await _center(engine, scene))[0], greaterThan(200));

    final swap = ship.adopt(blue);

    expect(swap.swapped, 1);
    expect(swap.isComplete, isTrue);
    expect(ship.nodes.single, same(hull));
    expect(ship.meshes.single, same(mesh));
    expect(
      hull.localMatrix.getTranslation().z,
      0.5,
      reason: 'where the game put it stays',
    );
    expect(mesh.mesh, same(blue.parts.single.mesh));
    final pixel = await _center(engine, scene);
    expect(pixel[2], greaterThan(200));
    // The tone map lifts the other channels as full blue nears white, so
    // red is held to a third of blue, as the variants test holds it.
    expect(pixel[0], lessThan(pixel[2] ~/ 3 + 1));
  });

  test('a part renamed in the file is still found by its node', () async {
    final engine = _engine();
    final before = await ModelAsset.fromDocument(
      _ship(Vector4(1.0, 0.0, 0.0, 1.0), partName: 'Cube'),
      device: engine.device,
    );
    final after = await ModelAsset.fromDocument(
      _ship(Vector4(0.0, 1.0, 0.0, 1.0), partName: 'Cube.001'),
      device: engine.device,
    );
    final ship = before.instantiate(Scene());

    expect(ship.adopt(after).swapped, 1);
    expect(ship.meshes.single.material, same(after.parts.single.material));
  });

  test('what the new file adds is reported, and what it drops stays', () async {
    final engine = _engine();
    final plain = await ModelAsset.fromDocument(
      _ship(Vector4(1.0, 0.0, 0.0, 1.0)),
      device: engine.device,
    );
    final flagged = await ModelAsset.fromDocument(
      _ship(Vector4(0.0, 1.0, 0.0, 1.0), withFlag: true, hull: 'keel'),
      device: engine.device,
    );
    final ship = plain.instantiate(Scene());
    final old = ship.meshes.single.mesh;

    final swap = ship.adopt(flagged);

    expect(swap.swapped, 0);
    expect(swap.kept, <String>['hull/s0']);
    expect(swap.added, unorderedEquals(<String>['keel/s0', 'flag/s0']));
    expect(swap.isComplete, isFalse);
    expect(ship.meshes.single.mesh, same(old));
  });

  test(
    'an unshared instance adopts copies, not the asset\'s materials',
    () async {
      final engine = _engine();
      final red = await ModelAsset.fromDocument(
        _ship(Vector4(1.0, 0.0, 0.0, 1.0)),
        device: engine.device,
      );
      final blue = await ModelAsset.fromDocument(
        _ship(Vector4(0.0, 0.0, 1.0, 1.0)),
        device: engine.device,
      );
      final ship = red.instantiate(Scene(), shareMaterials: false)..adopt(blue);

      final material = ship.meshes.single.material;
      expect(material, isNot(same(blue.parts.single.material)));
      expect(material.baseColor.toSrgb().b, 1.0);
    },
  );
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
