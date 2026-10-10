/// A model that changes its look by name, and a clip that animates a material
/// and a light, both written into a GLB and read back.
///
/// Quoted by `variants_and_pointers.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class VariantsAndPointersDemo extends ShowcaseDemo {
  /// 0 is the default look, then one option for each of the file's variants.
  int variant = 1;

  late final GltfAsset _readBack;
  late final ModelAsset _asset;
  late final ModelInstance _instance;
  late final AnimationPlayer _player;
  late final LightNode _sun;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..pitch = 0.35
      ..yaw = 0.6;
  }

  @override
  Future<void> prepare(DemoContext context) async {
    // #region materials
    // Five materials. The body wears the first and the ball the second
    // unless a variant says otherwise; the other three are only ever worn
    // through a variant.
    final List<SurfaceMaterial> materials = <SurfaceMaterial>[
      SurfaceMaterial(
        name: 'red paint',
        baseColor: LinearColor.fromSrgb(0.6, 0.2, 0.15, 1),
      ),
      SurfaceMaterial(
        name: 'cream',
        baseColor: LinearColor.fromSrgb(0.6, 0.55, 0.45, 1),
        roughness: 0.6,
      ),
      SurfaceMaterial(
        name: 'teal paint',
        baseColor: LinearColor.fromSrgb(0.12, 0.45, 0.42, 1),
      ),
      SurfaceMaterial(
        name: 'graphite',
        baseColor: LinearColor.fromSrgb(0.2, 0.2, 0.22, 1),
        roughness: 0.35,
      ),
      SurfaceMaterial(
        name: 'chalk',
        baseColor: LinearColor.fromSrgb(0.55, 0.55, 0.55, 1),
        roughness: 0.8,
      ),
    ];
    // #endregion materials

    // #region variants
    // `variantMaterials` maps a variant, by its index in `variants`, to the
    // material the surface wears in it. The body changes in both variants;
    // the ball only in "graphite".
    final List<ModelSurface> surfaces = <ModelSurface>[
      ModelSurface(
        mesh: CuboidShape(size: Vector3(1.2, 0.8, 0.8)).build(),
        materialIndex: 0,
        variantMaterials: const <int, int>{0: 2, 1: 3},
      ),
      ModelSurface(
        mesh: SphereShape(radius: 0.4, segments: 32, rings: 16).build(),
        materialIndex: 1,
        variantMaterials: const <int, int>{1: 4},
      ),
    ];
    const List<String> variants = <String>['teal', 'graphite'];
    // #endregion variants

    // #region clip
    // Two pointer tracks and no node track. One warms the ball's material
    // (index 1) from cream to amber and back; the other dims the file's
    // light (index 0) from 110 lux to 45 and back. Colour keys are linear,
    // as glTF keeps them; the first is the cream above.
    AnimationTrack track(AnimationPointer pointer, List<double> values) =>
        AnimationTrack(
          nodeIndex: -1,
          path: AnimationPath.pointer,
          interpolation: AnimationInterpolation.linear,
          times: Float32List.fromList(<double>[0.0, 1.5, 3.0]),
          values: Float32List.fromList(values),
          componentCount: pointer.property.componentCount,
          pointer: pointer,
        );
    final AnimationClip evening = AnimationClip(
      name: 'evening',
      tracks: <AnimationTrack>[
        track(
          AnimationPointer.of(AnimationPointerProperty.baseColor, 1),
          <double>[
            0.319, 0.262, 0.171, 1, //
            0.32, 0.09, 0.02, 1, //
            0.319, 0.262, 0.171, 1,
          ],
        ),
        track(
          AnimationPointer.of(AnimationPointerProperty.lightIntensity, 0),
          <double>[110, 45, 110],
        ),
      ],
    );
    // #endregion clip

    // #region roundtrip
    final PlainModelDocument document = PlainModelDocument(
      surfaces: surfaces,
      materials: materials,
      lights: <ModelLight>[
        ModelLight(type: ModelLightType.directional, intensity: 110),
      ],
      nodes: <ModelNode>[
        ModelNode(
          name: 'body',
          surfaces: <int>[0],
          translation: Vector3(0, 0.4, 0),
        ),
        ModelNode(
          name: 'ball',
          surfaces: <int>[1],
          translation: Vector3(0, 1.2, 0),
        ),
        ModelNode(name: 'sun', lightIndex: 0),
      ],
      variants: variants,
      animations: <AnimationClip>[evening],
    );
    final Uint8List bytes = GltfWriter(document).writeGlb();
    _readBack = await GltfLoader().load(bytes);
    _asset = await ModelAsset.fromDocument(_readBack, device: context.device);
    // #endregion roundtrip
  }

  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.45, 0.45, 0.45, 1.0),
            roughness: 0.9,
          ),
          name: 'floor',
        ),
      );

    // #region bind
    // Instantiating creates no lights, so the page places its own sun and
    // hands it to the instance as the file's light 0. The intensity track
    // reaches it through `pointerTargets`; the material tracks reach the
    // asset's materials the same way, by their index in the file.
    _instance = _asset.instantiate(scene);
    final ModelLight light = _readBack.lights.single;
    _sun = LightNode(
      name: 'sun',
      color: light.color,
      intensity: light.intensity,
    )..setLocalForward(Vector3(-0.5, -0.8, -0.4));
    _instance.bindLight(0, _sun);
    // #endregion bind

    // #region play
    // The page opens halfway through the clip, where both tracks are
    // furthest from what the file says, and plays on from there.
    _player = _instance.player!
      ..play(0)
      ..seek(1.5);
    // #endregion play
    _wear(variant);
    return scene..add(_sun);
  }

  // #region select
  void _wear(int option) {
    variant = option;
    _instance.selectVariant(option == 0 ? null : _asset.variants[option - 1]);
  }
  // #endregion select

  // The file's light is in lux, as glTF's is, and 110 lux is a lamp-lit
  // room rather than the sun. So the camera is metered as it would be in
  // one: for the light at its authored 110 lux plus the scene's flat
  // ambient (in the engine's pre-1.0 unit), about EV100 7.5, and held there
  // while the clip dims the light to 45 and back.
  static final PhysicalCamera _camera = PhysicalCamera.metered(
    110.0 + 0.06 * Photometric.legacyUnit,
  );

  @override
  RenderSettings settings(DemoContext context) =>
      RenderSettings(camera: _camera);

  @override
  void update(DemoContext context, double dt) {
    // #region tick
    _player.update(dt);
    // #endregion tick
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Variant',
      options: <String>['Default', ..._asset.variants],
      index: () => variant,
      onChanged: _wear,
    ),
    ToggleControl(
      'Play clip',
      value: () => _player.isPlaying,
      onChanged: (bool v) => v ? _player.play() : _player.pause(),
    ),
    SliderControl(
      'Time',
      min: 0,
      max: _player.duration,
      value: () => _player.time,
      onChanged: (double v) => _player
        ..pause()
        ..seek(v),
      format: (double v) => '${v.toStringAsFixed(2)} s',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // One mesh node a surface, in the order the nodes are walked: the body,
    // then the ball. Each must point at the material the file gives it in
    // the variant being worn, and that material is the asset's own.
    final int worn = _instance.variant == null
        ? -1
        : _asset.variants.indexOf(_instance.variant!);
    for (var i = 0; i < _readBack.surfaces.length; i++) {
      final ModelSurface surface = _readBack.surfaces[i];
      final int expected =
          surface.variantMaterials[worn] ?? surface.materialIndex!;
      if (!identical(
        _instance.meshes[i].material,
        _asset.materials[expected],
      )) {
        throw StateError(
          'surface $i is not wearing material $expected, which '
          '${_instance.variant ?? 'the default look'} gives it',
        );
      }
    }

    // The clip is past its first key, so both tracks have moved their
    // targets away from what the file says.
    final LinearColor authored = _readBack.materials[1].baseColor;
    final LinearColor now = _asset.materials[1]!.baseColor;
    if ((now.r - authored.r).abs() +
            (now.g - authored.g).abs() +
            (now.b - authored.b).abs() <
        0.05) {
      throw StateError("the colour track did not move the ball's material");
    }
    final double fileSun = _readBack.lights[0].intensity;
    if ((_sun.intensity - fileSun).abs() < 0.1) {
      throw StateError('the intensity track did not move the sun');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the model was not drawn');
    }
    // #endregion check
  }
}
