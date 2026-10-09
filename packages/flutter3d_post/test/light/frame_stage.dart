/// What every addon test installs its plugins into: a renderer on the
/// software device, a scene with something for every step to do, a plugin
/// host with no loop behind it, and the frame's order as one list.
///
/// The same file in each addon package, because a test helper is not API and
/// no package of the engine's exports one.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        BusChannel,
        BusEvent,
        EventCodec,
        EventDeclaration,
        EventHandler,
        EventRegistry,
        Flutter3dPlugin,
        LoopPhase,
        LoopRegistry,
        LoopSystem,
        PluginManager,
        PluginRegistry,
        PluginScope;
import 'package:vector_math/vector_math.dart';

/// Every step on, with something to do — the settings the frame order
/// fixture (`flutter3d_cpu/test/goldens/frame_order.jsonl`) calls
/// "everything", with the sky switched on as well.
const RenderSettings everything = RenderSettings(
  shadows: ShadowSettings(
    filter: ShadowFilter.evsm,
    translucentCasters: true,
    caustics: true,
    resolution: 64,
    cubeResolution: 16,
  ),
  reflections: ReflectionSettings(enabled: true),
  ambientOcclusion: AmbientOcclusionSettings(enabled: true, blurTaps: 4),
  contactShadows: ContactShadowSettings(enabled: true),
  volumetricFog: VolumetricFogSettings(enabled: true),
  lightShafts: LightShaftSettings(enabled: true),
  depthOfField: DepthOfFieldSettings(enabled: true),
  motionBlur: MotionBlurSettings(enabled: true),
  antiAlias: AntiAliasSettings(
    enabled: true,
    temporal: TemporalSettings(enabled: true, reactive: 0.5),
  ),
  autoExposure: AutoExposureSettings(enabled: true),
  localExposure: LocalExposureSettings(enabled: true),
  bloom: BloomSettings(
    intensity: 0.8,
    lensFlare: LensFlareSettings(enabled: true),
  ),
  look: LookSettings(
    contrast: 1.1,
    saturation: 0.9,
    vignette: 0.3,
    grain: 0.02,
    distortion: 0.1,
    chromaticAberration: 0.003,
  ),
  fog: FogSettings(density: 0.05),
  renderScale: 0.75,
  spatialUpscale: SpatialUpscaleSettings(enabled: true),
  highContrast: HighContrastSettings(enabled: true),
  viewportShading: ViewportShadingSettings(
    mode: ViewportShading.outline,
    amount: 0.5,
  ),
  occlusion: OcclusionMode.hiZ,
  decals: DecalSettings(enabled: true),
  planarReflections: PlanarReflectionSettings(enabled: true),
  sky: SkySettings(enabled: true),
);

/// A renderer, a scene and its one view.
final class FrameStage {
  FrameStage._(this.renderer, this.scene, this.views);

  factory FrameStage() {
    final device = CpuDevice(
      width: 24,
      height: 24,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    MeshNode mesh(MeshData shape, RenderMaterial material, Vector3 at) =>
        MeshNode(DeviceMesh.upload(device, shape), material)
          ..setPositionFrom(at);
    final floor = mesh(
      const PlaneShape(width: 8.0, depth: 8.0).build(),
      RenderMaterial(baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0)),
      Vector3.zero(),
    );
    final camera = CameraNode()
      ..setPosition(0.0, 2.5, 4.0)
      ..lookAt(Vector3.zero());
    final scene = Scene()
      ..add(floor)
      ..add(
        mesh(
          CuboidShape(size: Vector3.all(1.0)).build(),
          RenderMaterial(baseColor: LinearColor.fromSrgb(0.8, 0.3, 0.2, 1.0)),
          Vector3(0.0, 0.5, 0.0),
        )..outlineColor = LinearColor(1.0, 1.0, 0.0),
      )
      ..add(
        mesh(
          const SphereShape(radius: 0.3).build(),
          RenderMaterial(
            lighting: LightingModel.unlit,
            baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, 1.0),
            emissive: Vector3.all(8.0).toLinearColor(),
          ),
          Vector3(1.2, 1.2, 0.0),
        ),
      )
      ..add(
        LightNode(intensity: 3.0 * Photometric.legacyUnit, castsShadow: true)
          ..setPosition(2.0, 4.0, 1.0)
          ..lookAt(Vector3.zero()),
      )
      ..add(ReflectionProbeNode(faceSize: 8, levels: 2))
      ..add(PlanarReflectorNode(surfaces: <MeshNode>[floor]))
      ..add(camera);
    return FrameStage._(Renderer.create(device: device), scene, <RenderView>[
      RenderView(camera: camera),
    ]);
  }

  final Renderer renderer;
  final Scene scene;
  final List<RenderView> views;

  /// A plugin host over this renderer's registry, with [plugins] installed.
  PluginManager install(Iterable<Flutter3dPlugin> plugins) => PluginManager(
    loop: _Loop(),
    events: _Events(),
    registries: <PluginRegistry>[renderer.renderSteps],
  )..installAll(plugins);

  /// The frame [settings] plans, as the fixture writes a line of it: the
  /// passes that run, those left out, and every skip with its reason.
  List<String> plan(RenderSettings settings) {
    final plan = renderer.planFrame(
      scene: scene,
      views: views,
      settings: settings,
    );
    return <String>[
      for (final node in plan.order) 'runs ${node.name}',
      for (final node in plan.culled) 'culled ${node.name}',
      for (final skip in plan.skipped) '${skip.name}: ${skip.reason.name}',
    ];
  }

  /// The passes that run in the frame [settings] plans.
  List<String> passes(RenderSettings settings) => <String>[
    for (final node
        in renderer
            .planFrame(scene: scene, views: views, settings: settings)
            .order)
      node.name,
  ];

  /// The skips of a frame drawn with [settings], as `name: reason`: the
  /// passes left out and every step switched off by name, a step with no
  /// pass of its own included — which only a drawn frame reports.
  List<String> drawnSkips(RenderSettings settings) => <String>[
    for (final skip
        in renderer
            .render(
              width: 24,
              height: 24,
              scene: scene,
              views: views,
              settings: settings,
            )
            .skipped)
      '${skip.name}: ${skip.reason.name}',
  ];

  /// The skips the frame [settings] plans, as `name: reason`.
  List<String> skips(RenderSettings settings) => <String>[
    for (final skip
        in renderer
            .planFrame(scene: scene, views: views, settings: settings)
            .skipped)
      '${skip.name}: ${skip.reason.name}',
  ];
}

final class _Loop extends LoopRegistry {
  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  LoopRegistry forPlugin(PluginScope scope) => this;
}

final class _Events extends EventRegistry {
  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}
