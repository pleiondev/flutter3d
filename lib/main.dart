import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Aabb3, Vector2, Vector3;

import 'src/engine/animation/animation.dart';
import 'src/engine/assets/model_asset.dart';
import 'src/engine/assets/resource_cache.dart';
import 'src/engine/geometry/geometry.dart';
import 'src/engine/render/debug_draw.dart';
import 'src/engine/render/lighting_model.dart';
import 'src/engine/render/procedural_texture.dart';
import 'src/engine/render/render_view.dart';
import 'src/engine/render/renderer.dart';
import 'src/engine/scene/scene_graph.dart';
import 'src/spike/frame_capture.dart';
import 'src/spike/orbit_gestures.dart';
import 'src/spike/scene_source.dart';

void main() => runApp(const Flutter3dApp());

/// Everything the demo can display.
///
/// The glTF entries are Khronos sample assets, and between them they cover the
/// three ways a glTF file can carry its data: a GLB binary chunk, an embedded
/// base64 buffer, and a `.gltf` with external files next to it.
final List<SceneSource> kSources = <SceneSource>[
  ProceduralSource('Cube', CuboidShape(size: Vector3.all(1.0))),
  const ProceduralSource('Sphere', SphereShape(radius: 0.6)),
  const ProceduralSource('Cylinder', CylinderShape(height: 1.2)),
  const ProceduralSource('Cone', ConeShape(radius: 0.6, height: 1.2)),
  const ProceduralSource('Torus', TorusShape()),
  const ProceduralSource('Capsule', CapsuleShape()),
  const ProceduralSource('Disc', DiscShape(innerRadius: 0.2)),
  ProceduralSource('Vase', _vase),
  const ModelFileSource('glb: Box', 'assets/samples/Box.glb'),
  const ModelFileSource('glb: Textured', 'assets/samples/BoxTextured.glb'),
  const ModelFileSource(
    'glb: Vtx colors',
    'assets/samples/BoxVertexColors.glb',
  ),
  const ModelFileSource('gltf: Triangle', 'assets/samples/Triangle.gltf'),
  const ModelFileSource('gltf: Cube + bin', 'assets/samples/cube/Cube.gltf'),
  // Animated samples. Between them they cover all three glTF interpolations:
  // AnimatedCube is a single looping rotation, BoxAnimated animates a hierarchy
  // so a moving parent has to carry its child, and InterpolationTest exists
  // specifically to show STEP, LINEAR and CUBICSPLINE side by side.
  const ModelFileSource(
    'anim: Cube',
    'assets/samples/animated_cube/AnimatedCube.gltf',
  ),
  const ModelFileSource('anim: Box', 'assets/samples/BoxAnimated.glb'),
  const ModelFileSource(
    'anim: Interpolation',
    'assets/samples/InterpolationTest.glb',
  ),
  // The Utah teapot: positions and faces only, so its normals are generated.
  const ModelFileSource('obj: Teapot', 'assets/samples/teapot.obj'),
];

/// Surface of revolution from an arbitrary profile: a vase silhouette.
///
/// The same generator the rounded primitives delegate to, which is the point of
/// exposing it as a shape rather than hiding it behind them.
final LatheShape _vase = LatheShape(
  name: 'vase',
  segments: 64,
  profile: <Vector2>[
    Vector2(0.0, -0.62),
    Vector2(0.26, -0.62),
    Vector2(0.26, -0.62),
    Vector2(0.30, -0.50),
    Vector2(0.40, -0.28),
    Vector2(0.44, -0.06),
    Vector2(0.38, 0.16),
    Vector2(0.24, 0.32),
    Vector2(0.18, 0.44),
    Vector2(0.20, 0.56),
    Vector2(0.26, 0.62),
  ],
);

class Flutter3dApp extends StatelessWidget {
  const Flutter3dApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter3d spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const SpikePage(),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage>
    with SingleTickerProviderStateMixin {
  Renderer? _renderer;
  Object? _initError;
  StackTrace? _initStack;

  gpu.Texture? _fallbackAlbedo;
  gpu.Texture? _checkerAlbedo;

  late final Scene _scene;
  late final SceneNode _modelPivot;
  late final CameraNode _camera;
  late final LightNode _light;
  late final LightNode _fill;
  late final LightNode _spot;
  late final OrbitController _orbit;
  late final RenderView _view;

  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  /// Ref-counted cache, so returning to a source neither re-decodes nor
  /// re-uploads it, and two quick selections of the same model share one load.
  late final ResourceCache<String, ModelAsset> _assets;
  ResourceHandle<ModelAsset>? _held;

  /// Wall-clock time of the last load, to show that decoding moved off this
  /// isolate.
  int _lastLoadMillis = 0;

  int _sourceIndex = 0;
  ModelAsset? _asset;
  ModelInstance? _instance;
  String? _loadError;

  /// Frame time of the previous tick, so the animation player gets a delta
  /// rather than an absolute time — that is what lets speed and ping-pong work.
  Duration _lastTick = Duration.zero;

  LightingModel _lighting = LightingModel.pbr;
  double _roughness = 0.35;
  double _metallic = 0.0;
  double _specular = 1.0;
  double _exposure = 1.6;
  bool _wireframe = false;
  bool _spinning = startupSpinFromEnvironment();
  bool _culling = true;
  DebugDrawOptions _debug = debugDrawFromEnvironment();
  FrameResult? _lastFrame;

  /// Set only when `--dart-define=FLUTTER3D_CAPTURE=...` asked for a PNG.
  final FrameCapture? _capture = FrameCapture.fromEnvironment();

  /// Reused across taps: picking allocates nothing per cast, and the result
  /// object is owned by the caster.
  final Raycaster _raycaster = Raycaster();
  final List<SceneNode> _selection = <SceneNode>[];
  String? _pickDescription;

  /// Flutter's own frame timings, which are the numbers that actually say
  /// whether the app is dropping frames. The renderer's `cpuMicros` is only a
  /// slice of `buildDuration`, and neither of them is the GPU time.
  int _uiMicros = 0;
  int _rasterMicros = 0;

  @override
  void initState() {
    super.initState();

    _scene = Scene(name: 'demo');

    // A pivot the model hangs under, so "spin" animates the scene rather than
    // being baked into the renderer.
    _modelPivot = _scene.add(SceneNode(name: 'model pivot'));

    _camera = _scene.add(CameraNode(name: 'main camera'));

    // The key light is a CHILD OF THE CAMERA, which is the whole point of lights
    // being scene nodes: it follows the orbit for free, so whatever the user
    // turns towards stays lit. A world-fixed light would leave the far side of
    // the model in near-darkness, since ambient is deliberately low.
    _light = LightNode(
      type: LightType.directional,
      color: Vector3(1.0, 0.97, 0.92),
      name: 'key light',
    );
    _camera.add(_light);
    // Local direction, so it is relative to wherever the camera looks: shining
    // forward, from the upper left of the view.
    _light.setLocalForward(Vector3(0.35, -0.45, -0.82));

    // Two world-fixed lights of the other two types, so the demo actually
    // exercises attenuation and the spot cone rather than only the directional
    // path. They are placed from the model's bounds on load, because a scene
    // that fits in one unit and one that spans two hundred need very different
    // distances for the same look.
    _fill = LightNode(
      type: LightType.point,
      color: Vector3(0.35, 0.62, 1.0),
      intensity: 4.0,
      name: 'fill light',
    );
    _spot = LightNode(
      type: LightType.spot,
      color: Vector3(1.0, 0.45, 0.25),
      intensity: 12.0,
      innerConeAngle: 0.25,
      outerConeAngle: 0.5,
      name: 'spot light',
    );
    _scene
      ..add(_fill)
      ..add(_spot);

    final enabled = startupLightsFromEnvironment();
    if (enabled.isNotEmpty) {
      for (final light in <LightNode>[_light, _fill, _spot]) {
        light.visible = enabled.contains(light.name?.toLowerCase());
      }
    }

    _orbit = OrbitController(_camera, distance: 3.0, yaw: 0.6, pitch: 0.35);
    _view = RenderView(camera: _camera);

    try {
      final fallback = SolidColorTexture.white.upload();
      final checker = const CheckerboardTexture().upload();
      _fallbackAlbedo = fallback;
      _checkerAlbedo = checker;
      _renderer = Renderer.create(fallbackAlbedo: fallback);
    } catch (error, stack) {
      _initError = error;
      _initStack = stack;
    }

    _assets = ResourceCache<String, ModelAsset>(
      load: (label) {
        final source = kSources.firstWhere((s) => s.label == label);
        return source.load(
          fallbackAlbedo: _fallbackAlbedo!,
          checkerAlbedo: _checkerAlbedo!,
        );
      },
    );

    if (_renderer != null) _selectSource(_startupSourceIndex());

    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    _ticker = createTicker((elapsed) {
      setState(() => _elapsed = elapsed);
    })..start();
  }

  /// Selects whatever the tap landed on, or clears the selection.
  ///
  /// The ray is built from logical widget coordinates, not physical pixels: the
  /// two differ by the device pixel ratio, and the ray only depends on the
  /// aspect ratio, which they share.
  void _handleTap(Offset position, Size size) {
    _raycaster.setFromScreen(
      _camera,
      position.dx,
      position.dy,
      width: size.width,
      height: size.height,
    );
    final hit = _raycaster.intersectScene(_scene);

    setState(() {
      _selection.clear();
      if (hit == null) {
        _pickDescription = null;
        return;
      }
      _selection.add(hit.requireNode);
      _pickDescription =
          '${hit.requireNode.name ?? 'mesh'} · '
          'tri ${hit.triangleIndex} · '
          '${hit.distance.toStringAsFixed(2)} away · '
          'uv ${hit.uv.x.toStringAsFixed(2)},${hit.uv.y.toStringAsFixed(2)}'
          '${hit.approximate ? ' (bounds only)' : ''}';
    });
  }

  /// Index of the model named by `FLUTTER3D_SOURCE`, or 0.
  ///
  /// Matched case-insensitively on a substring so a capture command can say
  /// `teapot` instead of quoting the full chip label.
  int _startupSourceIndex() {
    final wanted = startupSourceFromEnvironment().trim().toLowerCase();
    if (wanted.isEmpty) return 0;
    for (var i = 0; i < kSources.length; i++) {
      if (kSources[i].label.toLowerCase().contains(wanted)) return i;
    }
    debugPrint(
      'FLUTTER3D_SOURCE: no model matches "$wanted"; using the first.',
    );
    return 0;
  }

  /// Records the most recent frame's UI and raster durations.
  ///
  /// Deliberately without `setState`: the ticker already rebuilds every frame,
  /// and asking for another build from inside a timings callback schedules a
  /// frame from within frame reporting.
  void _onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    final last = timings.last;
    _uiMicros = last.buildDuration.inMicroseconds;
    _rasterMicros = last.rasterDuration.inMicroseconds;
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _ticker.dispose();
    _held?.release();
    super.dispose();
  }

  Future<void> _selectSource(int index) async {
    final renderer = _renderer;
    if (renderer == null) return;

    final source = kSources[index];
    setState(() {
      _sourceIndex = index;
      _loadError = null;
    });

    final stopwatch = Stopwatch()..start();
    final ResourceHandle<ModelAsset> handle;
    try {
      handle = await _assets.acquire(source.label);
    } catch (error) {
      if (!mounted) return;
      // Log as well as show: a message that only reaches the UI is invisible when
      // the failure happens during automated checks.
      debugPrint('Model load failed for ${source.label}: $error');
      if (_sourceIndex == index) setState(() => _loadError = '$error');
      return;
    }
    stopwatch.stop();

    // A late load must not replace what the user has since selected — but the
    // reference still has to go back, or the cache would hold it forever.
    if (!mounted || _sourceIndex != index) {
      handle.release();
      return;
    }

    _held?.release();
    _held = handle;
    final asset = handle.value;
    _lastLoadMillis = stopwatch.elapsedMilliseconds;

    setState(() {
      _instance?.removeFromScene();
      _selection.clear();
      _pickDescription = null;

      final instance = asset.instantiate(_scene, parent: _modelPivot);
      _instance = instance;
      _asset = asset;

      // An animated model plays by default: a viewer that loads a clip and then
      // shows a still frame looks broken.
      instance.player?.play();

      // Show what the model actually uses, so the numbers on the sliders are not
      // a lie the moment a new model loads. A file with no materials at all — the
      // teapot, for instance — lands on the engine defaults, which is exactly the
      // case where the sliders are most useful.
      final first = _scene.meshes.isEmpty ? null : _scene.meshes.first.material;
      if (first != null) {
        _roughness = first.roughness;
        _metallic = first.metallic;
      }

      // Frame the newly placed model, and tie the depth range to it so small
      // models do not z-fight.
      final bounds = _scene.computeBounds();
      _orbit.frameBounds(bounds);
      _orbit.syncProjectionDepth(_camera);
      _placeSceneLights(bounds);
    });
  }

  /// Puts the point and spot lights at a sensible distance for this model.
  ///
  /// Scaled by the model rather than fixed: inverse-square falloff means a
  /// distance that flatters a one-unit cube leaves a two-hundred-unit scene in
  /// the dark, and the intensity would have to be retuned per model instead.
  void _placeSceneLights(Aabb3 bounds) {
    final centre = (bounds.min + bounds.max)..scale(0.5);
    final radius = ((bounds.max - bounds.min)..scale(0.5)).length;
    final distance = radius <= 0.0 ? 1.5 : radius * 2.0;

    _fill.setPosition(
      centre.x - distance,
      centre.y + distance * 0.35,
      centre.z + distance * 0.6,
    );
    // Intensity is photometric-ish: with inverse-square falloff it has to grow
    // with the square of the distance to keep the same brightness on the model.
    _fill
      ..intensity = 4.0 * distance * distance
      ..range = distance * 6.0;

    _spot.setPosition(
      centre.x + distance * 0.4,
      centre.y + distance * 1.6,
      centre.z + distance * 0.4,
    );
    _spot
      ..lookAt(centre)
      ..intensity = 12.0 * distance * distance
      ..range = distance * 6.0;
  }

  void _applyLighting(LightingModel model) {
    setState(() {
      _lighting = model;
      for (final mesh in _scene.meshes) {
        mesh.material.lighting = model;
      }
    });
  }

  /// Pushes the slider values onto every material in the scene.
  ///
  /// Deliberately unconditional: a viewer's sliders are overrides, and blocking
  /// them for files that ship materials was wrong twice over — it left a dead
  /// control, and it did so even for files with no materials at all, where there
  /// was nothing to protect.
  ///
  /// The trade-off is that a multi-material model gets flattened to one roughness
  /// while dragging. Reselecting the model restores the authored values, since
  /// materials are rebuilt per asset.
  void _applyMaterialSliders() {
    for (final mesh in _scene.meshes) {
      mesh.material
        ..roughness = _roughness
        ..metallic = _metallic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    if (renderer == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E1014),
        body: SafeArea(
          child: _ErrorPanel(error: _initError!, stack: _initStack),
        ),
      );
    }

    // Animate the pivot, not the renderer: the spin is now a property of the
    // scene, so one object could spin while another stays put.
    final seconds = _elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_spinning) {
      _modelPivot.setRotationYawPitchRoll(seconds * 0.7, 0.0, 0.0);
    }

    // The model's own clips advance on the same clock. A delta rather than the
    // elapsed total, so pausing the player actually pauses it instead of making
    // it jump on resume.
    final delta =
        (_elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = _elapsed;
    if (delta > 0.0 && delta < 0.5) _instance?.player?.update(delta);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1014),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: <Widget>[
              Expanded(
                child: _loadError != null
                    ? _LoadErrorPanel(message: _loadError!)
                    : OrbitGestureDetector(
                        controller: _orbit,
                        onChanged: () => setState(() {
                          _orbit.syncProjectionDepth(_camera);
                        }),
                        onTapPoint: _handleTap,
                        child: SceneSurface(
                          renderer: renderer,
                          scene: _scene,
                          view: _view,
                          settings: RenderSettings(
                            specular: _specular,
                            exposure: _exposure,
                            wireframe: _wireframe,
                            backfaceCulling: _culling,
                            debug: _debug,
                            highlighted: _selection,
                          ),
                          onFrame: (frame) {
                            _lastFrame = frame;
                            _capture?.offer(frame);
                          },
                        ),
                      ),
              ),
              // Bounded and scrollable: the panel grows with every feature, and an
              // unbounded one squeezed the viewport down to a single pixel row on
              // a short window — which looks exactly like a renderer that stopped
              // drawing.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.55,
                ),
                child: SingleChildScrollView(
                  child: _Controls(
                    sources: kSources,
                    sourceIndex: _sourceIndex,
                    onSource: _selectSource,
                    lighting: _lighting,
                    onLighting: _applyLighting,
                    roughness: _roughness,
                    onRoughness: (v) => setState(() {
                      _roughness = v;
                      _applyMaterialSliders();
                    }),
                    metallic: _metallic,
                    onMetallic: (v) => setState(() {
                      _metallic = v;
                      _applyMaterialSliders();
                    }),
                    specular: _specular,
                    onSpecular: (v) => setState(() => _specular = v),
                    exposure: _exposure,
                    onExposure: (v) => setState(() => _exposure = v),
                    ambient: _scene.ambientIntensity,
                    onAmbient: (v) =>
                        setState(() => _scene.ambientIntensity = v),
                    wireframe: _wireframe,
                    onWireframe: (v) => setState(() => _wireframe = v),
                    spinning: _spinning,
                    onSpinning: (v) => setState(() => _spinning = v),
                    culling: _culling,
                    onCulling: (v) => setState(() => _culling = v),
                    debug: _debug,
                    onDebug: (v) => setState(() => _debug = v),
                    lights: <LightNode>[_light, _fill, _spot],
                    onLightsChanged: () => setState(() {}),
                    uiMicros: _uiMicros,
                    rasterMicros: _rasterMicros,
                    pick: _pickDescription,
                    player: _instance?.player,
                    onPlayerChanged: () => setState(() {}),
                    onFrameAll: () => setState(() {
                      _orbit.frameBounds(_scene.computeBounds());
                      _orbit.syncProjectionDepth(_camera);
                    }),
                    renderer: renderer,
                    scene: _scene,
                    asset: _asset,
                    frame: _lastFrame,
                    loadMillis: _lastLoadMillis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the scene at the widget's physical pixel size and paints the result.
class SceneSurface extends StatelessWidget {
  const SceneSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.view,
    required this.settings,
    required this.onFrame,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;
  final RenderSettings settings;
  final ValueChanged<FrameResult> onFrame;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Render at physical resolution: sizing the target in logical pixels
        // would make the result soft on any HiDPI display.
        final width = (constraints.maxWidth * dpr).round().clamp(1, 8192);
        final height = (constraints.maxHeight * dpr).round().clamp(1, 8192);

        final frame = renderer.render(
          width: width,
          height: height,
          scene: scene,
          views: <RenderView>[view],
          settings: settings,
        );
        onFrame(frame);

        return CustomPaint(
          painter: _ImagePainter(frame.image),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  // The image is a new object every frame, so always repaint.
  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => true;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.sources,
    required this.sourceIndex,
    required this.onSource,
    required this.lighting,
    required this.onLighting,
    required this.roughness,
    required this.onRoughness,
    required this.metallic,
    required this.onMetallic,
    required this.specular,
    required this.onSpecular,
    required this.exposure,
    required this.onExposure,
    required this.ambient,
    required this.onAmbient,
    required this.wireframe,
    required this.onWireframe,
    required this.spinning,
    required this.onSpinning,
    required this.culling,
    required this.onCulling,
    required this.debug,
    required this.onDebug,
    required this.lights,
    required this.onLightsChanged,
    required this.uiMicros,
    required this.rasterMicros,
    required this.pick,
    required this.player,
    required this.onPlayerChanged,
    required this.onFrameAll,
    required this.renderer,
    required this.scene,
    required this.asset,
    required this.frame,
    required this.loadMillis,
  });

  final List<SceneSource> sources;
  final int sourceIndex;
  final ValueChanged<int> onSource;
  final LightingModel lighting;
  final ValueChanged<LightingModel> onLighting;
  final double roughness;
  final ValueChanged<double> onRoughness;
  final double metallic;
  final ValueChanged<double> onMetallic;
  final double specular;
  final ValueChanged<double> onSpecular;
  final double exposure;
  final ValueChanged<double> onExposure;
  final double ambient;
  final ValueChanged<double> onAmbient;
  final bool wireframe;
  final ValueChanged<bool> onWireframe;
  final bool spinning;
  final ValueChanged<bool> onSpinning;
  final bool culling;
  final ValueChanged<bool> onCulling;
  final DebugDrawOptions debug;
  final ValueChanged<DebugDrawOptions> onDebug;

  /// The scene's lights, so each can be switched on and off.
  final List<LightNode> lights;

  final VoidCallback onLightsChanged;
  final int uiMicros;
  final int rasterMicros;

  /// What the last tap selected, or null when nothing is selected.
  final String? pick;

  /// The current model's animation player, null when it carries no clips.
  final AnimationPlayer? player;

  /// Called after a transport control mutates the player, so the panel redraws.
  final VoidCallback onPlayerChanged;

  final VoidCallback onFrameAll;
  final Renderer renderer;
  final Scene scene;
  final ModelAsset? asset;
  final FrameResult? frame;

  /// Wall-clock time of the last load, including the isolate round trip.
  final int loadMillis;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sliders = lighting.usesMaterialParameters;
    final warnings = asset?.warnings ?? const <String>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: const Color(0xFF16191F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Label('Lighting model', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final m in LightingModel.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m == lighting,
                  onSelected: (_) => onLighting(m),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Label('Model', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < sources.length; i++)
                ChoiceChip(
                  label: Text(sources[i].label),
                  selected: i == sourceIndex,
                  onSelected: (_) => onSource(i),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: _Slider(
                  label: 'Roughness',
                  value: roughness,
                  enabled: sliders,
                  onChanged: onRoughness,
                ),
              ),
              Expanded(
                child: _Slider(
                  label: 'Metallic',
                  value: metallic,
                  enabled: sliders && lighting.usesMetallic,
                  onChanged: onMetallic,
                ),
              ),
              Expanded(
                child: _Slider(
                  label: 'Specular',
                  value: specular,
                  enabled: sliders && lighting != LightingModel.lambert,
                  onChanged: onSpecular,
                ),
              ),
              Expanded(
                child: _Slider(
                  label: 'Ambient',
                  value: ambient,
                  max: 0.4,
                  enabled: sliders,
                  onChanged: onAmbient,
                ),
              ),
              Expanded(
                child: _Slider(
                  label: 'Exposure',
                  value: exposure,
                  max: 4.0,
                  enabled: sliders,
                  onChanged: onExposure,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilterChip(
                label: const Text('Wireframe'),
                selected: wireframe,
                onSelected: onWireframe,
              ),
              FilterChip(
                label: const Text('Spin'),
                selected: spinning,
                onSelected: onSpinning,
              ),
              FilterChip(
                label: const Text('Backface cull'),
                selected: culling,
                onSelected: onCulling,
              ),
              ActionChip(label: const Text('Frame all'), onPressed: onFrameAll),
            ],
          ),
          if (player != null && player!.hasClips) ...<Widget>[
            const SizedBox(height: 6),
            _Label('Animation', textTheme),
            _AnimationControls(player: player!, onChanged: onPlayerChanged),
          ],
          const SizedBox(height: 6),
          _Label('Lights', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final light in lights)
                FilterChip(
                  label: Text('${light.name ?? light.type.name} '
                      '(${light.type.name})'),
                  selected: light.visible,
                  // Switching a light off only shortens the shader's loop; the
                  // pipeline is untouched, which the "pipeline sw" counter below
                  // keeps honest.
                  onSelected: (v) {
                    light.visible = v;
                    onLightsChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          _Label('Debug draw', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('Bounds'),
                selected: debug.bounds,
                onSelected: (v) => onDebug(debug.copyWith(bounds: v)),
              ),
              FilterChip(
                label: const Text('Normals'),
                selected: debug.normals,
                onSelected: (v) => onDebug(debug.copyWith(normals: v)),
              ),
              FilterChip(
                label: const Text('Lights'),
                selected: debug.lightGizmos,
                onSelected: (v) => onDebug(debug.copyWith(lightGizmos: v)),
              ),
              FilterChip(
                label: const Text('Axes'),
                selected: debug.axes,
                onSelected: (v) => onDebug(debug.copyWith(axes: v)),
              ),
              FilterChip(
                label: const Text('Frusta'),
                selected: debug.cameraFrustums,
                onSelected: (v) => onDebug(debug.copyWith(cameraFrustums: v)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            asset == null
                ? 'loading…'
                : '${asset!.vertexCount} vtx · ${asset!.triangleCount} tri · '
                      '${scene.meshes.length} nodes · '
                      'load $loadMillis ms · '
                      'MSAA ${renderer.msaaEnabled ? '4x' : 'off'}',
            style: textTheme.bodySmall,
          ),
          Text(
            'ui ${_ms(uiMicros)} · raster ${_ms(rasterMicros)} · '
            'render ${_ms(frame?.cpuMicros ?? 0)} · '
            'submit ${_ms(frame?.submitMicros ?? 0)} · '
            '${frame?.drawCalls ?? 0} draws · '
            '${frame?.pipelineSwitches ?? 0} pipeline sw · '
            '${frame?.culled ?? 0} culled · '
            '${frame?.lights ?? 0} lights'
            '${(frame?.lightsDropped ?? 0) > 0 ? ' (+${frame!.lightsDropped} dropped)' : ''}'
            '${(frame?.debugLines ?? 0) > 0 ? ' · ${frame!.debugLines} debug lines' : ''}',
            style: textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              pick == null
                  ? 'Drag to orbit · scroll or pinch to zoom · two fingers to '
                        'pan · tap to pick'
                  : 'picked: $pick',
              style: textTheme.bodySmall?.copyWith(
                color: pick == null ? Colors.white38 : Colors.lightGreenAccent,
              ),
            ),
          ),
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '⚠ ${warnings.first}'
                '${warnings.length > 1 ? ' (+${warnings.length - 1} more)' : ''}',
                style: textTheme.bodySmall?.copyWith(color: Colors.amberAccent),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Transport controls for the current model's clips.
///
/// Scrubbing pauses first: dragging a slider while the clip is running fights
/// the ticker, and every frame would snap the playhead back.
class _AnimationControls extends StatelessWidget {
  const _AnimationControls({required this.player, required this.onChanged});

  final AnimationPlayer player;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = player.clipNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilterChip(
              label: Text(player.isPlaying ? 'Pause' : 'Play'),
              selected: player.isPlaying,
              onSelected: (_) {
                player.isPlaying ? player.pause() : player.play();
                onChanged();
              },
            ),
            ActionChip(
              label: const Text('Rewind'),
              onPressed: () {
                player.stop();
                onChanged();
              },
            ),
            for (final wrap in AnimationWrap.values)
              ChoiceChip(
                label: Text(wrap.name),
                selected: player.wrap == wrap,
                onSelected: (_) {
                  player.wrap = wrap;
                  onChanged();
                },
              ),
            if (names.length > 1)
              for (var i = 0; i < names.length; i++)
                ChoiceChip(
                  label: Text(names[i]),
                  selected: player.clipIndex == i,
                  onSelected: (_) {
                    player.play(i);
                    onChanged();
                  },
                ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: _Slider(
                label:
                    'Time '
                    '${player.time.toStringAsFixed(2)}/'
                    '${player.duration.toStringAsFixed(2)}s',
                value: player.duration <= 0.0
                    ? 0.0
                    : player.time / player.duration,
                enabled: player.duration > 0.0,
                onChanged: (v) {
                  player.pause();
                  player.seek(v * player.duration);
                  onChanged();
                },
              ),
            ),
            Expanded(
              child: _Slider(
                label: 'Speed ${player.speed.toStringAsFixed(2)}x',
                value: player.speed,
                max: 3.0,
                enabled: true,
                onChanged: (v) {
                  player.speed = v;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        Text(
          '${player.clips.length} clip'
          '${player.clips.length == 1 ? '' : 's'} · '
          '${player.clip?.tracks.length ?? 0} tracks',
          style: textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
      ],
    );
  }
}

/// Microseconds as milliseconds with two decimals, so a sub-millisecond phase is
/// still readable instead of collapsing to "0 ms".
String _ms(int micros) => '${(micros / 1000.0).toStringAsFixed(2)} ms';

class _Label extends StatelessWidget {
  const _Label(this.text, this.theme);

  final String text;
  final TextTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: theme.labelSmall?.copyWith(letterSpacing: 1.1),
    ),
  );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.max = 1.0,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$label ${value.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: enabled ? null : Theme.of(context).disabledColor,
          ),
        ),
        Slider(
          value: value.clamp(0.0, max),
          max: max,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _LoadErrorPanel extends StatelessWidget {
  const _LoadErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.amberAccent),
            const SizedBox(height: 12),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Renderer failed to start',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Most likely the shader bundle is missing or stale. Rebuild it with '
            'tool/build_shaders.sh, then restart. The bundle format is tied to '
            'the Flutter version.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            '$error\n\n${stack ?? ''}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
