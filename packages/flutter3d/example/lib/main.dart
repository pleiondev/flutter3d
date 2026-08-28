import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart' as engine;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart' show Aabb3, Vector3, Vector4;

import 'src/spike/backend.dart';
import 'src/spike/control_panel.dart';
import 'src/spike/error_panels.dart';
import 'src/spike/frame_capture.dart';
import 'src/spike/golden_extras.dart';
import 'src/spike/golden_runner.dart';
import 'src/spike/orbit_gestures.dart';
import 'src/spike/sample_sources.dart';
import 'src/spike/scene_surface.dart';

void main() => runApp(const Flutter3dApp());

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

  /// Kept because the asset loader needs one long after `initState`.
  GraphicsDevice? _device;
  Object? _initError;
  StackTrace? _initStack;

  TextureHandle? _checkerAlbedo;

  late final Scene _scene;
  late final SceneNode _modelPivot;
  late final CameraNode _camera;
  late final LightNode _sun;
  late final LightNode _light;
  late final LightNode _fill;

  /// Additional shadow-casting point lights, only for the multi-row golden.
  final List<LightNode> _extraPoints = <LightNode>[];

  /// Frames elapsed, for the golden whose caster has to move. See build().
  int _moverFrame = 0;
  late final LightNode _spot;

  /// A plane under the model, so the shadow has somewhere to land.
  late final MeshNode _ground;
  bool _showGround = GoldenRunner.fromEnvironment()?.scene.ground ?? true;

  /// Set when the ground was wanted but the scene could not be measured yet.
  bool _groundPending = false;
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

  LightingModel _lighting =
      GoldenRunner.fromEnvironment()?.scene.lighting ?? LightingModel.pbr;
  double _roughness = 0.35;
  double _metallic = 0.0;
  double _specular = 1.0;
  double _exposure = 1.6;
  bool _wireframe = false;
  // A golden must not move between the frame it is recorded on and the frame it
  // is compared on, so the turntable is off for every scene.
  bool _spinning =
      GoldenRunner.fromEnvironment() == null && startupSpinFromEnvironment();
  bool _culling = true;
  DebugDrawOptions _debug =
      GoldenRunner.fromEnvironment()?.scene.debug ?? debugDrawFromEnvironment();

  /// Set only by a golden that wants to look at the surface buffer.
  final bool _showSurfaceBuffer =
      GoldenRunner.fromEnvironment()?.scene.surfaceBuffer ?? false;

  /// The sky the golden scene asks for, or none at all — which is what every
  /// scene but one asks for, and what this application shows when it is being
  /// driven by hand rather than by the golden runner.
  final SkySettings _sky =
      GoldenRunner.fromEnvironment()?.scene.sky ?? const SkySettings();

  final bool _showShadowMap =
      GoldenRunner.fromEnvironment()?.scene.shadowMap ?? false;

  BloomSettings _bloom = BloomSettings(
    enabled: GoldenRunner.fromEnvironment()?.scene.bloom ?? true,
  );
  ShadowSettings _shadows = ShadowSettings(
    enabled:
        GoldenRunner.fromEnvironment()?.scene.shadows ??
        startupShadowsFromEnvironment(),
  );
  FrameResult? _lastFrame;

  /// Set only when `--dart-define=FLUTTER3D_CAPTURE=...` asked for a PNG.
  final FrameCapture? _capture = FrameCapture.fromEnvironment();

  /// Set only when `--dart-define=FLUTTER3D_GOLDEN=...` named a scene.
  final GoldenRunner? _golden = GoldenRunner.fromEnvironment();

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
    unawaited(_openScene());
  }

  /// Builds the backend and the whole demo scene under it.
  ///
  /// Asynchronous for one reason: loading the shader bundle is, since
  /// flutter_gpu 3.47. Everything after the first line runs exactly as it did
  /// when `initState` ran it directly, in the same order, and the ticker at the
  /// end is what puts the finished scene on screen.
  Future<void> _openScene() async {
    // The backend, before anything that needs one. It used to be built inline
    // at `Renderer.create`, which was fine while meshes and textures reached a
    // global to upload themselves; now that they take a device, it has to exist
    // first. A failure here is the same failure as a missing shader bundle, so
    // it lands in the same place and `build` shows the same panel.
    final GraphicsDevice device;
    try {
      device = await createBackend(width: 480, height: 360);
    } catch (error, stack) {
      // Inside `setState` because the failing frame is no longer the first
      // one: `build` has already run and shown the empty gap.
      if (mounted) {
        setState(() {
          _initError = error;
          _initStack = stack;
        });
      }
      return;
    }
    if (!mounted) return;
    _device = device;

    _scene = Scene(name: 'demo');

    // A pivot the model hangs under, so "spin" animates the scene rather than
    // being baked into the renderer.
    _modelPivot = _scene.add(SceneNode(name: 'model pivot'));

    // Added before the camera's key light so it is the first directional in the
    // registry, and therefore the one that casts. A shadow from a
    // camera-parented light would swing with the orbit, which makes it useless
    // for judging whether the pass is right.
    // The dominant source, and the only one that casts. It has to out-light the
    // other three put together, or its shadow is a few percent of the total and
    // reads as nothing — which is exactly what happened when it was set to 1.6
    // against a combined 17.
    _sun = LightNode(
      type: LightType.directional,
      color: Vector3(1.0, 0.95, 0.85),
      intensity: 4.0,
      name: 'sun',
    );
    _scene.add(_sun);
    // Low and oblique, roughly 30 degrees above the horizon. A sun overhead
    // drops the shadow directly under the object, where the object itself
    // covers it — the shadow is still being cast, it is just never visible. An
    // oblique sun throws it out to the side, which is the only reason to have a
    // ground plane in the demo at all.
    _sun.setLocalForward(Vector3(-0.85, -0.5, -0.2));

    _ground = MeshNode(
      // Uploaded, not a CpuMesh: this one is drawn, and the renderer refuses
      // geometry that never reached the GPU rather than skipping it quietly.
      DeviceMesh.upload(device, const PlaneShape().build()),
      engine.Material(
        lighting: LightingModel.pbr,
        // Mid grey, not white: a white floor under a lit model saturates and
        // the shadow lands on a surface with no headroom to darken.
        baseColor: Vector4(0.45, 0.45, 0.47, 1.0),
        roughness: 0.9,
      ),
      name: 'ground',
    );
    // Receives shadows without casting one: a plane's own back face in the
    // shadow map would fight the surface it is meant to darken.
    _ground.castsShadow = false;

    _camera = _scene.add(CameraNode(name: 'main camera'));

    // The key light is a CHILD OF THE CAMERA, which is the whole point of lights
    // being scene nodes: it follows the orbit for free, so whatever the user
    // turns towards stays lit. A world-fixed light would leave the far side of
    // the model in near-darkness, since ambient is deliberately low.
    _light = LightNode(
      type: LightType.directional,
      color: Vector3(1.0, 0.97, 0.92),
      // Dim, because a light parented to the camera is a headlight: it fills in
      // every shadow the viewer can see, which is the one place a shadow needs
      // to survive. It earns its keep as a fill, not as a key.
      intensity: 0.35,
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
      // Set only by the golden that wants to look at the cube atlas, because
      // the atlas costs six views of the scene and nothing else here needs it.
      castsShadow: GoldenRunner.fromEnvironment()?.scene.pointShadow ?? false,
    );
    _spot = LightNode(
      type: LightType.spot,
      color: Vector3(1.0, 0.45, 0.25),
      intensity: 12.0,
      innerConeAngle: 0.25,
      outerConeAngle: 0.5,
      name: 'spot light',
      // Same reasoning as the fill light above: a caster takes a row of the
      // cube atlas, and only the golden that wants to look at one asks for it.
      castsShadow: GoldenRunner.fromEnvironment()?.scene.spotShadow ?? false,
    );
    _scene
      ..add(_fill)
      ..add(_spot);

    // Extra point casters for the golden that checks more than one atlas row.
    // Placed in _placeSceneLights with the others, since the distance that
    // suits a model depends on its bounds.
    final extras = _golden?.scene.extraPointShadows ?? 0;
    for (var i = 0; i < extras; i++) {
      final light = LightNode(
        type: LightType.point,
        color: Vector3(1.0, 0.72, 0.4),
        intensity: 4.0,
        name: 'extra point $i',
        castsShadow: true,
      );
      _extraPoints.add(light);
      _scene.add(light);
    }

    final enabled = _golden?.scene.lights ?? startupLightsFromEnvironment();
    if (enabled.isNotEmpty) {
      for (final light in <LightNode>[_light, _fill, _spot]) {
        light.visible = enabled.contains(light.name?.toLowerCase());
      }
    }

    _orbit = OrbitController(_camera, distance: 3.0, yaw: 0.6, pitch: 0.35);
    _view = RenderView(camera: _camera);

    try {
      _checkerAlbedo = const CheckerboardTexture().upload(device);
      _renderer = Renderer.create(device: device);
    } catch (error, stack) {
      _initError = error;
      _initStack = stack;
    }

    // What a golden draws besides the world. Registered here rather than per
    // frame, because a plugin is a property of the renderer now — and built
    // from GoldenExtras, where every input is fixed, because a reference image
    // of a random burst compares against nothing.
    final goldenScene = _golden?.scene;
    final renderer = _renderer;
    if (goldenScene != null && renderer != null) {
      if (goldenScene.name == 'particles-textured') {
        renderer.addContributor(
          ParticleContributor(
            GoldenExtras.texturedParticles(),
            texture: GoldenExtras.particleSprite(device),
          ),
        );
      } else if (goldenScene.name == 'particles-mesh') {
        // A different contributor, not a mode of the other one: the mesh path
        // binds two vertex buffers where the billboard path binds one.
        renderer.addContributor(
          MeshParticleContributor(
            GoldenExtras.meshParticles(),
            mesh: GoldenExtras.meshParticleShape(device),
          ),
        );
      } else if (goldenScene.particles) {
        renderer.addContributor(
          ParticleContributor(switch (goldenScene.name) {
            'particle-one' => GoldenExtras.oneParticle(),
            'particles-recycled' => GoldenExtras.recycled(),
            'particle-stack' => GoldenExtras.stackedParticles(),
            _ => GoldenExtras.burst(),
          }),
        );
      }
      if (goldenScene.viewModel) {
        renderer.addNode(GoldenExtras.viewModel(device));
      }
    }

    _assets = ResourceCache<String, ModelAsset>(
      load: (label) {
        final source = kSources.firstWhere((s) => s.label == label);
        return source.load(device: _device!, checkerAlbedo: _checkerAlbedo!);
      },
    );

    // Deliberately not awaited: the first frame must not wait for a model to
    // decode. `unawaited` says so rather than leaving it to be read as a
    // forgotten `await`.
    if (_renderer != null) unawaited(_selectSource(_startupSourceIndex()));

    if (const bool.fromEnvironment('FLUTTER3D_MRT_PROBE')) {
      unawaited(_renderer?.probeMultipleRenderTargets().then(debugPrint));
    }

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
    final wanted = (_golden?.scene.source ?? startupSourceFromEnvironment())
        .trim()
        .toLowerCase();
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
    _renderer?.dispose();
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
      // shows a still frame looks broken. A capture can pin it instead.
      final frozen =
          _golden?.scene.animationTime ?? startupAnimationTimeFromEnvironment();
      if (frozen != null) {
        instance.player
          ?..play()
          ..pause()
          ..seek(frozen);
      } else {
        instance.player?.play();
      }

      // Every material a newly loaded model brought with it arrives on the
      // engine default, which is PBR. Pushing the chosen model onto them here
      // rather than only from the control panel is what makes the lighting
      // switchable at all from outside the UI — and its absence is why five of
      // the six lighting goldens recorded byte-identical PBR images and then
      // passed against each other's references.
      for (final mesh in _scene.meshes) {
        mesh.material.lighting = _lighting;
      }

      // Show what the model actually uses, so the numbers on the sliders are not
      // a lie the moment a new model loads. A file with no materials at all — the
      // teapot, for instance — lands on the engine defaults, which is exactly the
      // case where the sliders are most useful.
      final first = _scene.meshes.isEmpty ? null : _scene.meshes.first.material;
      if (first != null) {
        _roughness = first.roughness;
        _metallic = first.metallic;
      }

      // Measure the model in its rest pose, whatever the pivot happens to be
      // holding right now.
      //
      // The floor, the camera distance and the scene lights are all derived
      // from these bounds, once, here — on whichever build the asynchronous
      // load happened to finish on. `cube-shadow-mover` turns the pivot a
      // little on every build, so the bounds it was measured by used to be a
      // function of how long the load took, and the whole frame moved with
      // them. Measured: the load normally lands on build 3 and the camera sits
      // at 13.994; delayed by 400 ms it lands on build 14, the camera goes to
      // 15.884, and 9878 of 172800 pixels disagree with the reference — 5.7%
      // against a 0.2% limit. It is a race that this machine simply keeps
      // winning the same way.
      //
      // Zeroing the pivot makes the measurement a function of the model
      // instead. Nothing else reads the pivot in this method, and the next
      // build puts the turn straight back — see the mover block in build().
      _modelPivot.setRotationYawPitchRoll(0.0, 0.0, 0.0);

      // Frame the newly placed model, and tie the depth range to it so small
      // models do not z-fight.
      // The ground is sized from the model, so it must not be in the bounds the
      // model is measured by — nor in the ones the camera frames, or every
      // scene would be viewed from far enough away to fit a floor six times its
      // width.
      _ground.removeFromParent();
      final bounds = _scene.computeBounds();
      _placeGround(bounds);

      _orbit.frameBounds(bounds);
      // After framing, because frameBounds sets the distance but leaves the
      // angles alone — a capture that names an angle has to keep it.
      final golden = _golden?.scene;
      final orbit = golden != null
          ? (yaw: golden.yaw, pitch: golden.pitch)
          : startupOrbitFromEnvironment();
      if (orbit != null) {
        _orbit
          ..yaw = orbit.yaw
          ..pitch = orbit.pitch
          ..apply();
      }
      _orbit.syncProjectionDepth(_camera);
      _placeSceneLights(bounds);
    });
  }

  /// Sits the ground plane just under the model and scales it to suit.
  ///
  /// Recomputed per model because the scenes range from a one-unit cube to a
  /// two-hundred-unit wall, and a fixed plane would either be invisible or fill
  /// the frame.
  void _placeGround(Aabb3 bounds) {
    _ground.removeFromParent();
    if (!_showGround) {
      _groundPending = false;
      return;
    }
    if (!bounds.min.x.isFinite) {
      // Nothing measurable yet. A skinned mesh has no world bounds until its
      // skeleton has been posed, and the pose happens during the first draw —
      // so a rigged model installed here measures as empty and, before this
      // flag existed, silently never got a floor at all. Which floor a frame
      // had then depended on load timing, and the golden for the rigged figure
      // failed about one run in three.
      _groundPending = true;
      return;
    }
    _groundPending = false;
    if (!bounds.min.x.isFinite) return;

    final centre = (bounds.min + bounds.max)..scale(0.5);
    final extent = (bounds.max - bounds.min)..scale(0.5);
    final radius = math.max(extent.length, 1e-3);

    // Dropped for the golden that needs a gap between caster and receiver; see
    // GoldenScene.groundDrop. Widened with it so the shadow still lands on it.
    final drop = radius * (_golden?.scene.groundDrop ?? 0.0);
    _scene.add(_ground);
    _ground
      ..setPosition(centre.x, bounds.min.y - radius * 0.02 - drop, centre.z)
      ..setScale(radius * (3.0 + drop), 1.0, radius * (3.0 + drop));
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
      ..intensity = 1.0 * distance * distance
      ..range = distance * 6.0;

    // Spread around the model, each at a different distance and height, so no
    // two rows of the atlas hold the same view.
    //
    // The radius **shrinks** with the index, which is the whole point when
    // there are more casters than rows: the lights added last are the nearest,
    // so choosing by relevance and choosing by scene order pick different sets.
    // The first attempt had the radius fixed and the height rising with the
    // index, which made scene order agree with distance — and
    // `cube-shadow-crowded` passed with the ranking stubbed out to a constant,
    // pinning nothing at all.
    for (var i = 0; i < _extraPoints.length; i++) {
      final angle = (i + 1) * math.pi * 2.0 / (_extraPoints.length + 1);
      final radius = distance * (1.7 - 0.22 * i);
      _extraPoints[i]
        ..setPosition(
          centre.x + math.cos(angle) * radius,
          centre.y + distance * (0.9 - 0.12 * i),
          centre.z + math.sin(angle) * radius,
        )
        ..intensity = 1.0 * distance * distance
        ..range = distance * 6.0;
    }

    _spot.setPosition(
      centre.x + distance * 0.4,
      centre.y + distance * 1.6,
      centre.z + distance * 0.4,
    );
    _spot
      ..lookAt(centre)
      ..intensity = 2.5 * distance * distance
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
    final initError = _initError;
    if (renderer == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E1014),
        // No renderer and no error is the gap while the backend is being
        // built, which exists because loading the shader bundle became
        // asynchronous. It used to be impossible, and `_initError!` used to say
        // so; an empty frame is the honest thing to show for the one frame it
        // usually lasts.
        body: SafeArea(
          child: initError == null
              ? const SizedBox.shrink()
              : ErrorPanel(error: initError, stack: _initStack),
        ),
      );
    }

    // Animate the pivot, not the renderer: the spin is now a property of the
    // scene, so one object could spin while another stays put.
    final seconds = _elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_spinning) {
      _modelPivot.setRotationYawPitchRoll(seconds * 0.7, 0.0, 0.0);
    }

    // A caster that moves, for the golden that has to prove a moving shadow
    // follows it. Driven by a frame count and then held still, not by the
    // clock: a golden must be identical on the frame it is compared on, which
    // is why the turntable above is off for every scene. Counting frames and
    // stopping well before the capture gives motion *and* a settled pose, so
    // the atlas must have been redrawn after the opening one.
    if (_golden?.scene.moverFrames case final int frames when frames > 0) {
      _moverFrame++;
      final held = _moverFrame < frames ? _moverFrame : frames;
      _modelPivot.setRotationYawPitchRoll(held * 0.02, 0.0, 0.0);
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
                    ? LoadErrorPanel(message: _loadError!)
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
                          // A golden renders at a size it names, or the
                          // reference depends on the window it was recorded on
                          // and no two machines agree.
                          fixedSize: _golden == null
                              ? null
                              : Size(
                                  _golden.scene.width.toDouble(),
                                  _golden.scene.height.toDouble(),
                                ),
                          settings: RenderSettings(
                            specular: _specular,
                            exposure: _exposure,
                            wireframe: _wireframe,
                            backfaceCulling: _culling,
                            debug: _debug,
                            highlighted: _selection,
                            bloom: _bloom,
                            shadows: _shadows,
                            // The normals view is not light, so the display
                            // transform would corrupt it: a normal encoded as
                            // RGB has no business being rolled off or exposed.
                            tonemap: _lighting != LightingModel.normals,
                            showSurfaceBuffer: _showSurfaceBuffer,
                            showShadowMap: _showShadowMap,
                            sky: _sky,
                          ),
                          onFrame: (frame) {
                            _lastFrame = frame;
                            if (_groundPending) {
                              // Retried rather than given up on. By now the
                              // first draw has posed any skeleton, so the
                              // bounds are real.
                              //
                              // In the rest pose, for the same reason as at the
                              // load site above: which frame the measurement
                              // lands on must not decide how big the floor is.
                              _modelPivot.setRotationYawPitchRoll(
                                0.0,
                                0.0,
                                0.0,
                              );
                              _placeGround(_scene.computeBounds());
                            }
                            _capture?.offer(renderer.device, frame);
                            // Missing this was why the first recording run
                            // never finished: the scene's settings were being
                            // applied, but nothing counted frames, so the app
                            // simply ran for ever.
                            _golden?.offer(renderer.device, frame);
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
                  child: ControlPanel(
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
                    lights: <LightNode>[_sun, _light, _fill, _spot],
                    onLightsChanged: () => setState(() {}),
                    bloom: _bloom,
                    onBloom: (v) => setState(() => _bloom = v),
                    shadows: _shadows,
                    onShadows: (v) => setState(() => _shadows = v),
                    ground: _showGround,
                    onGround: (v) => setState(() {
                      _showGround = v;
                      _ground.removeFromParent();
                      _placeGround(_scene.computeBounds());
                    }),
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
