/// Two plates with the same four-colour texture: one read as it is, one whose
/// colour map and glow map are each moved by a transform of their own.
///
/// Quoted by `texture_transforms.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TextureTransformsDemo extends ShowcaseDemo {
  double turn = math.pi / 4;
  double repeat = 2.0;
  double slide = 0.5;

  static const SamplerOptions _nearestRepeat = SamplerOptions(
    minFilter: MinMagFilter.nearest,
    magFilter: MinMagFilter.nearest,
    widthAddressMode: SamplerAddressMode.repeat,
    heightAddressMode: SamplerAddressMode.repeat,
  );

  late final Material _moved;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.6
      ..yaw = 0.0
      ..pitch = 0.0;
  }

  // #region texture
  /// Four texels, one colour each: red, green, blue and white.
  TextureHandle _quadrants(GraphicsDevice device) =>
      device.createTextureFromPixels(
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
  // #endregion texture

  // #region transforms
  /// The colour map turned and tiled, the glow map slid sideways: two maps of
  /// one material that no longer agree.
  Map<MaterialMap, TextureTransform> _transforms() =>
      <MaterialMap, TextureTransform>{
        MaterialMap.baseColor: TextureTransform(
          scale: Vector2(repeat, repeat),
          rotation: turn,
        ),
        MaterialMap.emissive: TextureTransform(offset: Vector2(slide, 0.0)),
      };
  // #endregion transforms

  @override
  Scene build(DemoContext context) {
    final TextureHandle quadrants = _quadrants(context.device);

    // #region plates
    final Material asIs = Material(
      name: 'as is',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.3, 0.3, 0.3, 1.0),
      albedo: quadrants,
      albedoSampler: _nearestRepeat,
      emissiveTexture: quadrants,
      emissiveSampler: _nearestRepeat,
      emissive: Vector3(0.5, 0.5, 0.5),
    );
    _moved = Material(
      name: 'moved',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.3, 0.3, 0.3, 1.0),
      albedo: quadrants,
      albedoSampler: _nearestRepeat,
      emissiveTexture: quadrants,
      emissiveSampler: _nearestRepeat,
      emissive: Vector3(0.5, 0.5, 0.5),
      textureTransforms: _transforms(),
    );
    // #endregion plates

    final DeviceMesh plate = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 1.6, depth: 1.6).build(),
    );
    final Quaternion upright = Quaternion.axisAngle(
      Vector3(1.0, 0.0, 0.0),
      math.pi / 2,
    );
    return Scene()
      ..ambientIntensity = 0.25
      ..add(
        MeshNode(plate, asIs, name: 'as is')
          ..setRotation(upright)
          ..setPosition(-0.95, 0.0, 0.0),
      )
      ..add(
        MeshNode(plate, _moved, name: 'moved')
          ..setRotation(upright)
          ..setPosition(0.95, 0.0, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.2, -0.3, -1.0).normalized()),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _moved.textureTransforms.addAll(_transforms());
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Colour map: turn',
      min: 0,
      max: 2 * math.pi,
      value: () => turn,
      onChanged: (double v) => turn = v,
      format: (double v) => '${(v * 180 / math.pi).round()}°',
    ),
    SliderControl(
      'Colour map: repeat',
      min: 1,
      max: 4,
      value: () => repeat,
      onChanged: (double v) => repeat = v,
      format: (double v) => '${v.toStringAsFixed(1)}x',
    ),
    SliderControl(
      'Glow map: slide',
      min: 0,
      // Half a tile: the map repeats, so a slide of one looks like nought.
      max: 0.5,
      value: () => slide,
      onChanged: (double v) => slide = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final MeshNode moved = scene.meshes.firstWhere(
      (MeshNode m) => m.name == 'moved',
    );
    if (moved.material.textureTransforms.length != 2) {
      throw StateError('the moved plate does not carry a transform per map');
    }
    if (frame.drawCalls < 2) {
      throw StateError('the two plates were not both drawn');
    }
  }
}
