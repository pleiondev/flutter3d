/// `KHR_texture_transform` at the sampler — `C8`: a matrix per map in the
/// layered stage's `LayerInfo`, read by `MapUv`.
///
///     dart test test/texture_transform_test.dart
///
/// The oracle is the path that already existed: a transform baked into the
/// coordinates by `withTextureTransform`. What the sampler draws has to be
/// what the baked mesh draws, map by map, and a map moved on its own has to
/// move alone.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector2, Vector3, Vector4;

const int _size = 32;

/// Four texels, one colour each, read without filtering: a coordinate moved
/// by a transform lands in a different colour rather than a blend of them.
TextureHandle _quadrants(CpuDevice device) => device.createTextureFromPixels(
  width: 2,
  height: 2,
  format: TextureFormat.r8g8b8a8UNormInt,
  pixels: ByteData.sublistView(
    Uint8List.fromList(<int>[
      ...<int>[230, 20, 20, 255],
      ...<int>[20, 230, 20, 255],
      ...<int>[20, 20, 230, 255],
      ...<int>[230, 230, 230, 255],
    ]),
  ),
)!;

/// A normal map whose four texels lean four different ways, so a frame that
/// fails to turn with the map lights each quadrant from the wrong side.
TextureHandle _leaningNormals(CpuDevice device) =>
    device.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[
          ...<int>[220, 128, 190, 255],
          ...<int>[128, 220, 190, 255],
          ...<int>[40, 128, 190, 255],
          ...<int>[128, 40, 190, 255],
        ]),
      ),
    )!;

/// The HDR frame of a two-metre plane seen from straight above, drawn with
/// [material] on [mesh] — the plain plane when null.
Float32List _render(
  Material Function(CpuDevice device) material, {
  MeshData? mesh,
  bool lit = false,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 2.0, 0.0)
    ..lookAt(Vector3.zero(), up: Vector3(0.0, 0.0, -1.0));
  final plane = MeshNode(
    DeviceMesh.upload(
      device,
      mesh ?? const PlaneShape(width: 2.0, depth: 2.0).build(),
    ),
    material(device),
  );
  final scene = Scene()
    ..add(plane)
    ..add(camera)
    ..ambientIntensity = 0.25;
  if (lit) {
    scene.add(
      LightNode(intensity: 3.0)..setRotationYawPitchRoll(0.4, -1.0, 0.0),
    );
  }
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
    ),
  );
  return device.readHdrPixels(result.frame);
}

double _largestDifference(Float32List a, Float32List b) {
  var largest = 0.0;
  for (var i = 0; i < a.length; i++) {
    largest = math.max(largest, (a[i] - b[i]).abs());
  }
  return largest;
}

/// A map read through [transform] at a quarter of the image, turned: every
/// part of the matrix is something other than the identity.
TextureTransform _turned() => TextureTransform(
  offset: Vector2(0.75, 0.25),
  scale: Vector2(0.5, -0.75),
  rotation: math.pi / 2,
);

void main() {
  group('texture-transform-per-map', () {
    test('the base colour read at the sampler is the baked mesh\'s', () {
      final plane = const PlaneShape(width: 2.0, depth: 2.0).build();
      final atSampler = _render(
        (device) => Material(
          lighting: LightingModel.pbrLayered,
          albedo: _quadrants(device),
          albedoSampler: SamplerOptions.nearestClamp,
          textureTransforms: <MaterialMap, TextureTransform>{
            MaterialMap.baseColor: _turned(),
          },
        ),
      );
      final baked = _render(
        (device) => Material(
          lighting: LightingModel.pbrLayered,
          albedo: _quadrants(device),
          albedoSampler: SamplerOptions.nearestClamp,
        ),
        mesh: withTextureTransform(plane, _turned()),
      );
      final untransformed = _render(
        (device) => Material(
          lighting: LightingModel.pbrLayered,
          albedo: _quadrants(device),
          albedoSampler: SamplerOptions.nearestClamp,
        ),
      );

      // Mutation: `MapUv` returning `v_texcoord` in `mapUv` (dropping the
      // matrix) makes the first expectation fail by a whole colour.
      expect(_largestDifference(atSampler, baked), lessThan(1e-4));
      expect(_largestDifference(atSampler, untransformed), greaterThan(0.1));
    });

    test('each map moves alone: base colour and emission apart', () {
      // One material gives the two maps two transforms, drawn twice: once
      // with only the colour showing and once with only the glow. Each has to
      // be the mesh baked with its own map's transform, not the other's.
      final plane = const PlaneShape(width: 2.0, depth: 2.0).build();
      final moveColour = TextureTransform(
        offset: Vector2(0.5, 0.0),
        scale: Vector2(0.5, 1.0),
      );
      final moveGlow = TextureTransform(
        offset: Vector2(0.0, 0.5),
        scale: Vector2(1.0, 0.5),
      );
      Material apart(CpuDevice device, {required bool glow}) => Material(
        lighting: LightingModel.pbrLayered,
        baseColor: glow ? Vector4(0.0, 0.0, 0.0, 1.0) : null,
        albedo: _quadrants(device),
        albedoSampler: SamplerOptions.nearestClamp,
        emissiveTexture: _quadrants(device),
        emissiveSampler: SamplerOptions.nearestClamp,
        emissive: glow ? Vector3(0.5, 0.5, 0.5) : null,
        textureTransforms: <MaterialMap, TextureTransform>{
          MaterialMap.baseColor: moveColour,
          MaterialMap.emissive: moveGlow,
        },
      );
      Material baked(CpuDevice device, {required bool glow}) => Material(
        lighting: LightingModel.pbrLayered,
        baseColor: glow ? Vector4(0.0, 0.0, 0.0, 1.0) : null,
        albedo: _quadrants(device),
        albedoSampler: SamplerOptions.nearestClamp,
        emissiveTexture: _quadrants(device),
        emissiveSampler: SamplerOptions.nearestClamp,
        emissive: glow ? Vector3(0.5, 0.5, 0.5) : null,
      );

      final colour = _render((device) => apart(device, glow: false));
      final colourBaked = _render(
        (device) => baked(device, glow: false),
        mesh: withTextureTransform(plane, moveColour),
      );
      final glow = _render((device) => apart(device, glow: true));
      final glowBaked = _render(
        (device) => baked(device, glow: true),
        mesh: withTextureTransform(plane, moveGlow),
      );

      // Mutation: reading the emissive map through `kMapBaseColor`'s rows
      // puts the glow in the colour's quadrants and the second fails.
      expect(_largestDifference(colour, colourBaked), lessThan(1e-4));
      expect(_largestDifference(glow, glowBaked), lessThan(1e-4));
      expect(_largestDifference(glow, colour), greaterThan(0.1));
    });

    test('a normal map turned by its transform turns its frame', () {
      final plane = const PlaneShape(width: 2.0, depth: 2.0).build();
      Material bumpy(CpuDevice device, {TextureTransform? transform}) =>
          Material(
            lighting: LightingModel.pbrLayered,
            normal: _leaningNormals(device),
            normalSampler: SamplerOptions.nearestClamp,
            roughness: 0.7,
            textureTransforms: <MaterialMap, TextureTransform>{
              MaterialMap.normal: ?transform,
            },
          );
      final atSampler = _render(
        (device) => bumpy(device, transform: _turned()),
        lit: true,
      );
      final baked = _render(
        bumpy,
        mesh: withTextureTransform(plane, _turned()),
        lit: true,
      );

      // Mutation: skipping the turn in `applyNormalMap` (the `C8` block)
      // leaves the texels in the right place and lights them from the wrong
      // side, and this fails by far more than rounding.
      expect(_largestDifference(atSampler, baked), lessThan(1e-3));
    });

    test('a turned normal map lights as the turned coordinates\' own frame', () {
      // The test above holds the sampler to the bake, and both could turn the
      // frame the same wrong way. This one holds it to the geometry: the frame
      // `withGeneratedTangents` derives from the moved coordinates, which knows
      // nothing of transforms. A turn and an even stretch, where a turned unit
      // tangent is exact.
      final plane = const PlaneShape(width: 2.0, depth: 2.0).build();
      final turn = TextureTransform(
        offset: Vector2(0.2, 0.6),
        scale: Vector2(0.8, 0.8),
        rotation: 0.9,
      );
      Material bumpy(CpuDevice device, {TextureTransform? transform}) =>
          Material(
            lighting: LightingModel.pbrLayered,
            normal: _leaningNormals(device),
            normalSampler: SamplerOptions.nearestClamp,
            roughness: 0.7,
            textureTransforms: <MaterialMap, TextureTransform>{
              MaterialMap.normal: ?transform,
            },
          );
      final atSampler = _render(
        (device) => bumpy(device, transform: turn),
        lit: true,
      );
      final generated = _render(
        bumpy,
        mesh: withTextureTransform(plane, turn).withGeneratedTangents(),
        lit: true,
      );

      // Mutation: `t * m11 - front * m10` in `applyNormalMap`, taking the
      // bitangent for dP/dv, turns the relief twice the angle and this fails.
      expect(_largestDifference(atSampler, generated), lessThan(1e-3));
    });

    test('the identity draws what no transform draws, to the bit', () {
      final none = _render(
        (device) => Material(
          lighting: LightingModel.pbrLayered,
          albedo: _quadrants(device),
          normal: _leaningNormals(device),
        ),
        lit: true,
      );
      final identity = _render(
        (device) => Material(
          lighting: LightingModel.pbrLayered,
          albedo: _quadrants(device),
          normal: _leaningNormals(device),
          textureTransforms: <MaterialMap, TextureTransform>{
            for (final map in MaterialMap.values) map: TextureTransform(),
          },
        ),
        lit: true,
      );
      expect(identity, none);
    });

    test('a pointer track moves the offset of the map it names', () {
      Material glowing(CpuDevice device) => Material(
        lighting: LightingModel.pbrLayered,
        baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
        emissiveTexture: _quadrants(device),
        emissiveSampler: SamplerOptions.nearestClamp,
        emissive: Vector3(1.0, 1.0, 1.0),
        textureTransforms: <MaterialMap, TextureTransform>{
          MaterialMap.emissive: TextureTransform(scale: Vector2(0.5, 0.5)),
        },
      );
      final pointer = AnimationPointer.parse(
        '/materials/0/emissiveTexture/extensions/KHR_texture_transform/'
        'offset',
      )!;

      final before = _render(glowing);
      final moved = _render((device) {
        final material = glowing(device);
        PointerTargets.applyToMaterial(material, pointer, <double>[0.5, 0.5]);
        return material;
      });
      final built = _render(
        (device) => glowing(device)
          ..textureTransforms[MaterialMap.emissive] = TextureTransform(
            offset: Vector2(0.5, 0.5),
            scale: Vector2(0.5, 0.5),
          ),
      );

      // Mutation: `applyToMaterial` ignoring `textureOffset` again, as it
      // did before `C8`, leaves `moved` equal to `before`.
      expect(moved, built);
      expect(_largestDifference(moved, before), greaterThan(0.1));
    });
  });
}
