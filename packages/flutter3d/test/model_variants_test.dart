/// A model switches material variants, and a pointer clip colours it.
///
///     flutter test test/model_variants_test.dart
///
/// The format tests in `flutter3d_core` hold the files; these hold what an
/// application sees after the upload: `ModelInstance.selectVariant` putting
/// each mesh node in the material its variant names, and a
/// `KHR_animation_pointer` clip reaching the bound material through the
/// instance's player, drawn on the CPU device at three times.
///
/// Mutation: make `selectVariant` keep `part.material` and the variant frame
/// stays red; drop `pointers:` from the player `instantiate` builds and the
/// three frames come out the same.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

MeshData _quad() => MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List.fromList(<double>[
    // position, normal, texcoord, tangent, colour
    -1, -1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1,
    1, -1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1,
    1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1,
    -1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1,
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2, 0, 2, 3]),
);

/// One quad in dim red, a "blue" variant that dresses it in blue, and a clip
/// that brightens the red over two seconds through a pointer at
/// `/materials/0/pbrMetallicRoughness/baseColorFactor`.
PlainModelDocument _document() => PlainModelDocument(
  surfaces: <ModelSurface>[
    ModelSurface(
      mesh: _quad(),
      materialIndex: 0,
      variantMaterials: const <int, int>{0: 1},
    ),
  ],
  materials: <SurfaceMaterial>[
    SurfaceMaterial(baseColor: Vector4(0.1, 0.0, 0.0, 1.0), unlit: true),
    SurfaceMaterial(baseColor: Vector4(0.0, 0.0, 1.0, 1.0), unlit: true),
  ],
  nodes: <ModelNode>[
    ModelNode(surfaces: <int>[0]),
  ],
  variants: const <String>['blue'],
  animations: <AnimationClip>[
    AnimationClip(
      name: 'brighten',
      tracks: <AnimationTrack>[
        AnimationTrack(
          nodeIndex: -1,
          path: AnimationPath.pointer,
          interpolation: AnimationInterpolation.linear,
          times: Float32List.fromList(<double>[0.0, 2.0]),
          values: Float32List.fromList(<double>[0.01, 0, 0, 1, 1, 0, 0, 1]),
          componentCount: 4,
          pointer: AnimationPointer.of(AnimationPointerProperty.baseColor, 0),
        ),
      ],
    ),
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
  )!;
  return (
    device: device,
    renderer: Renderer.create(device: device, fallbackNormal: flat),
  );
}

/// The centre pixel of [scene] seen head on, as 8-bit RGBA.
Future<List<int>> _centre(
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
  final pixels = (await engine.device.readPixels(
    frame.frame,
  ))!.buffer.asUint8List();
  final i = (_size ~/ 2 * _size + _size ~/ 2) * 4;
  return pixels.sublist(i, i + 4);
}

void main() {
  test(
    'a variant dresses the parts it names, and null undresses them',
    () async {
      final engine = _engine();
      final asset = await ModelAsset.fromDocument(
        _document(),
        device: engine.device,
      );
      expect(asset.variants, <String>['blue']);
      expect(asset.materials.keys, unorderedEquals(<int>[0, 1]));

      final instance = asset.instantiate(Scene());
      final mesh = instance.meshes.single;
      final red = mesh.material;

      expect(instance.selectVariant('green'), isFalse);
      expect(
        mesh.material,
        same(red),
        reason: 'an unknown name changes nothing',
      );

      expect(instance.selectVariant('blue'), isTrue);
      expect(instance.variant, 'blue');
      expect(mesh.material, same(asset.materials[1]));

      expect(instance.selectVariant(null), isTrue);
      expect(instance.variant, isNull);
      expect(mesh.material, same(red));
    },
  );

  test('two unshared instances wear and animate their own materials', () async {
    final engine = _engine();
    final asset = await ModelAsset.fromDocument(
      _document(),
      device: engine.device,
    );
    final scene = Scene();
    final a = asset.instantiate(scene, shareMaterials: false);
    final b = asset.instantiate(scene, shareMaterials: false);

    a.selectVariant('blue');
    expect(a.meshes.single.material, isNot(same(asset.materials[1])));
    expect(a.meshes.single.material.baseColor.z, 1.0);
    expect(b.meshes.single.material.baseColor.x, closeTo(0.1, 1e-6));

    a.player!
      ..play(0)
      ..seek(2.0);
    expect(a.pointerTargets.materials[0]!.baseColor.x, closeTo(1.0, 1e-6));
    expect(b.meshes.single.material.baseColor.x, closeTo(0.1, 1e-6));
    expect(asset.materials[0]!.baseColor.x, closeTo(0.1, 1e-6));
  });

  test(
    'variants-pointer: the clip at 0, 1 and 2 s, then the variant',
    () async {
      final engine = _engine();
      final asset = await ModelAsset.fromDocument(
        _document(),
        device: engine.device,
      );
      final scene = Scene();
      final instance = asset.instantiate(scene);
      final player = instance.player!..play(0);

      final frames = <List<int>>[];
      for (final t in <double>[0.0, 1.0, 2.0]) {
        player.seek(t);
        frames.add(await _centre(engine, scene));
      }
      // Red climbs with the clip and stays the dominant channel. The tone map
      // lifts green and blue together as full red nears white, so they are
      // held to a third of red rather than to zero.
      expect(frames[0][0], lessThan(frames[1][0]));
      expect(frames[1][0], lessThan(frames[2][0]));
      expect(frames[2][0], greaterThan(240));
      for (final frame in frames) {
        expect(frame[1], lessThan(frame[0] ~/ 3 + 1));
        expect(frame[2], lessThan(frame[0] ~/ 3 + 1));
      }

      // The clip drives material 0; the variant's material is another one, so
      // switching to it shows blue whatever the clip last wrote.
      instance.selectVariant('blue');
      final blue = await _centre(engine, scene);
      expect(blue[2], greaterThan(200));
      expect(blue[0], lessThan(blue[2] ~/ 2));
    },
  );
}
