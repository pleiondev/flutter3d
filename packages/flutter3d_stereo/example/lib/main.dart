/// A room in stereo, pointed by the device's own rotation sensor.
///
///     flutter run -d <a phone>
///
/// **What this is for is the half of a headset that a phone already has.** Two
/// eyes a fixed distance apart, two views into one frame, the settings a pair
/// can actually have, and a head that moves when you move — all of that is the
/// same on a phone held up to the face as it is in a headset, and all of it can
/// be got wrong long before there is a runtime to blame. What a phone cannot
/// show is the rest: a compositor's predicted pose, seventy-two hertz, and a
/// swapchain owned by somebody else.
///
/// So this example is deliberately not a demo of VR. It is the acceptance tool
/// for `StereoRig`, `StereoSurface` and `OffAxisProjection` on real hardware.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_backend/flutter3d_backend.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape and nothing else on screen: a phone in a holder has no room for
  // a status bar, and a picture that reflows halfway through a turn of the head
  // is worse than one that never rotates.
  unawaitedChrome();
  runApp(const StereoExampleApp());
}

void unawaitedChrome() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

class StereoExampleApp extends StatelessWidget {
  const StereoExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'flutter3d in stereo',
    debugShowCheckedModeBanner: false,
    home: StereoScreen(),
  );
}

class StereoScreen extends StatefulWidget {
  const StereoScreen({super.key});

  @override
  State<StereoScreen> createState() => _StereoScreenState();
}

class _StereoScreenState extends State<StereoScreen>
    with SingleTickerProviderStateMixin {
  final StereoRig _rig = StereoRig();
  final SensorHeadTracker _tracker = SensorHeadTracker();
  Scene? _scene;
  Renderer? _renderer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // The size is what the software fallback would draw at; the hardware
      // backends size themselves to the surface and ignore it.
      // `--dart-define=software=true` draws in Dart instead, at a size a
      // rasteriser without a GPU can keep up with. It is for a device whose
      // driver will not run the engine — the picture is what is being checked,
      // not the frame rate.
      final device = const bool.fromEnvironment('software')
          ? CpuDevice(
              width: 400,
              height: 200,
              shaders: CpuShaderLibrary(builtinCpuShaders()),
            )
          : await openDevice(width: 1920, height: 1080);
      if (!mounted) return;
      final scene = _room(device);
      scene.add(_rig.stage);
      // Standing height, so the floor is where a floor is rather than at the
      // eyes. The rig's stage is the only thing an application moves.
      _rig.stage.setPosition(0.0, 1.6, 0.0);
      setState(() {
        _renderer = Renderer.create(device: device);
        _scene = scene;
      });
      await _tracker.start();
      // **A ticker rather than the sensor drives the frame.** The sensor
      // arrives about fifty times a second whatever the renderer can manage,
      // and a rebuild per reading on the software rasteriser is a queue of
      // frames the platform thread never gets out of — which Android reports
      // as an application not responding. One frame at a time, each reading
      // the latest pose, is the honest arrangement on any backend.
      _ticker = createTicker(_onTick)..start();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Ticker? _ticker;
  final Stopwatch _clock = Stopwatch();
  int _frames = 0;

  void _onTick(Duration _) {
    if (!mounted) return;
    if (!_clock.isRunning) _clock.start();
    _frames++;
    if (_clock.elapsedMilliseconds >= 2000) {
      debugPrint(
        '[stereo] ${(_frames * 1000 / _clock.elapsedMilliseconds)
            .toStringAsFixed(1)} fps '
        '(${(_clock.elapsedMilliseconds / _frames).toStringAsFixed(1)} ms a '
        'frame)',
      );
      _frames = 0;
      _clock
        ..reset()
        ..start();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No device: $error',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    final renderer = _renderer;
    final scene = _scene;
    if (renderer == null || scene == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // A one-eyed variant, for telling "the stereo pair is the problem" from
    // "this device and this engine are the problem":
    //     flutter run --dart-define=mono=true
    if (const bool.fromEnvironment('mono')) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            _rig.applyHead(_tracker.pose.value);
            final width = (constraints.maxWidth * dpr).round().clamp(2, 8192);
            final height = (constraints.maxHeight * dpr).round().clamp(1, 8192);
            _rig.fitToViewport(width: width * 2, height: height);
            final frame = renderer.render(
              width: width,
              height: height,
              scene: scene,
              views: <RenderView>[
                RenderView(camera: _rig.camera(Eye.left)),
              ],
              settings: const RenderSettings(exposure: 1.2).forStereo(),
            );
            return renderer.device.present(frame.frame);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: StereoSurface(
        renderer: renderer,
        scene: scene,
        rig: _rig,
        onBeforeFrame: () => _rig.applyHead(_tracker.pose.value),
        settings: () => const RenderSettings(exposure: 1.2),
      ),
    );
  }
}

/// A room with a floor, four walls' worth of pillars, and something to look up
/// at — enough for parallax to have work to do at several distances.
Scene _room(GraphicsDevice device) {
  final scene = Scene();

  final tile = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(0.98, 0.08, 0.98)).build(),
  );
  final pillar = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(0.35, 3.0, 0.35)).build(),
  );
  final crate = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
  );

  // A checkerboard rather than one big quad: the seams are what the eye reads
  // distance from when there is no other texture.
  for (var x = -4; x <= 4; x++) {
    for (var z = -4; z <= 4; z++) {
      final light = (x + z).isEven;
      scene.add(
        MeshNode(
          tile,
          engine.Material(
            name: 'tile',
            baseColor: light
                ? Vector4(0.42, 0.44, 0.50, 1.0)
                : Vector4(0.24, 0.26, 0.32, 1.0),
            lighting: LightingModel.unlit,
          ),
          name: 'tile.$x.$z',
        )..setPosition(x.toDouble(), 0.0, z.toDouble()),
      );
    }
  }

  const colours = <(double, double, double)>[
    (0.92, 0.35, 0.28),
    (0.35, 0.78, 0.45),
    (0.36, 0.55, 0.95),
    (0.95, 0.78, 0.30),
  ];
  for (var i = 0; i < 4; i++) {
    final angle = i * math.pi / 2.0;
    final colour = colours[i % colours.length];
    scene.add(
      MeshNode(
        pillar,
        engine.Material(
          name: 'pillar',
          baseColor: Vector4(colour.$1, colour.$2, colour.$3, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'pillar.$i',
      )..setPosition(math.sin(angle) * 4.5, 1.5, math.cos(angle) * 4.5),
    );
  }

  // Near, so that the difference between the two eyes is obvious: at half a
  // metre the parallax is a good fraction of the frame.
  for (var i = 0; i < 2; i++) {
    scene.add(
      MeshNode(
        crate,
        engine.Material(
          name: 'crate',
          baseColor: Vector4(0.85, 0.85, 0.88, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'crate.$i',
      )..setPosition(-0.6 + i * 0.6, 0.45 + i * 0.1, -0.9 - i * 0.7),
    );
  }

  return scene;
}
