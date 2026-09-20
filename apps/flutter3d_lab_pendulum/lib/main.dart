/// A live look at `edu-04`'s own pieces, all of which existed only behind
/// tests until now: a real swinging [PendulumSimulation], a real
/// `WidgetSurface` carrying [PendulumLabPanel], a real tap routed through
/// [Raycaster] the same way `flutter3d_template_app`'s own
/// `_tapWidgetSurface` already proved for `tpl-04`.
///
/// Its own application, not a mode of the crypt's `main.dart`: nothing here
/// is a level, a genre or a save — it is a demonstration, run with
///
///     flutter run -d chrome
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_lab/flutter3d_lab.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/lab_review_panel.dart';
import 'src/pendulum_lab_panel.dart';

void main() {
  runApp(const PendulumLabDemoApp());
}

class PendulumLabDemoApp extends StatelessWidget {
  const PendulumLabDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'edu-04: pendulum lab',
      debugShowCheckedModeBanner: false,
      home: PendulumLabScreen(),
    );
  }
}

class PendulumLabScreen extends StatefulWidget {
  const PendulumLabScreen({super.key});

  @override
  State<PendulumLabScreen> createState() => _PendulumLabScreenState();
}

class _PendulumLabScreenState extends State<PendulumLabScreen>
    with SingleTickerProviderStateMixin {
  // A getter, not a `static final` — a shared `Vector3` instance is mutable,
  // and `tool/structure.dart`'s own rule against that is not theoretical: the
  // first caller that scaled or normalized this in place would corrupt it
  // for every frame after. A fresh vector each read costs nothing a pivot
  // that never moves needs to avoid.
  static Vector3 get _pivot => Vector3(0.0, 2.0, 0.0);

  static const double _assignedLength = 1.2;

  final PendulumSimulation _pendulum = PendulumSimulation(
    lengthMeters: _assignedLength,
    startAngle: 0.9,
  );
  final ValueNotifier<double> _length = ValueNotifier<double>(_assignedLength);
  final Raycaster _raycaster = Raycaster();

  /// `ls-e-01`'s own recording — the length this run actually held at every
  /// fixed step, the same `DataSourceTrace` `pendulum_lab_panel_test.dart`
  /// already proved records a tap at the step it happened rather than
  /// before, now kept for real rather than only under a test.
  final DataSourceTrace _lengths = DataSourceTrace();
  double _stepAccumulator = 0.0;
  int _step = 0;

  Renderer? _renderer;
  Object? _initError;
  late Scene _scene;
  late CameraNode _camera;
  late MeshNode _bob;
  late MeshNode _string;
  late WidgetSurface _panel;
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
      device = await openDevice(width: 1280, height: 720);
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }

    final scene = Scene();
    // `-Z`, not `+Z`: `WidgetSurface.yaw`'s setter always applies yaw *before*
    // the fixed `pitch = -π/2` that stands the plane up
    // (`SceneNode.setRotationYawPitchRoll`'s own order), so a panel turned to
    // face `+Z` with `yaw = π` tips up already rotated a half-turn and
    // renders upside down — found live, not guessed: `edu-00` §7's
    // `view-caption` widget carries the identical `yaw: 3.1416` and would
    // have the same fault the day something actually draws it. Easier to
    // stand on the side the panel's default `yaw = 0.0` already faces than
    // to fight the order.
    final camera = CameraNode(name: 'eye')
      ..setPositionFrom(Vector3(0.0, 1.6, -4.2))
      ..lookAt(_pivot);
    scene.add(camera);

    scene.add(
      LightNode(type: LightType.point, intensity: 8.0, name: 'sun')
        ..setPositionFrom(Vector3(1.0, 4.0, -3.0)),
    );

    final pivotMesh = MeshNode(
      DeviceMesh.upload(device, const SphereShape(radius: 0.06).build()),
      Material(
        lighting: LightingModel.unlit,
        baseColor: Vector4(0.6, 0.62, 0.66, 1.0),
      ),
      name: 'pivot',
    )..setPositionFrom(_pivot);
    scene.add(pivotMesh);

    final bob = MeshNode(
      DeviceMesh.upload(device, const SphereShape(radius: 0.16).build()),
      Material(
        lighting: LightingModel.pbr,
        baseColor: Vector4(0.86, 0.71, 0.32, 1.0),
        roughness: 0.4,
      ),
      name: 'bob',
    );
    scene.add(bob);

    // The string: a unit-height cylinder, thin, unlit (a shading model has
    // nothing to add to a thread nobody looks at closely) — stretched and
    // aimed fresh every frame in `_placeString`, since its own length and
    // direction are exactly `edu-04`'s one live number and its swing.
    final string = MeshNode(
      DeviceMesh.upload(
        device,
        const CylinderShape(
          radiusTop: 0.012,
          radiusBottom: 0.012,
          height: 1.0,
          segments: 8,
          capped: false,
        ).build(),
      ),
      Material(
        lighting: LightingModel.unlit,
        baseColor: Vector4(0.75, 0.75, 0.72, 1.0),
      ),
      name: 'string',
    );
    scene.add(string);

    // Left at its default `yaw = 0.0`: that already faces `-Z`, which is
    // where the camera stands (see the comment on `camera` above for why
    // turning the panel instead would render it upside down).
    //
    // **`Transform.flip(flipX/flipY: true)` — a full 180° turn — is a local
    // workaround, not a fix.** Empirically, live, in two rounds: `flipY`
    // alone (a vertical mirror) turned upside-down text right-side up but
    // left it mirrored left-to-right (backward letters, `+`/`-` swapped) —
    // which only a *rotation*, not a single-axis mirror, explains. So a
    // `WidgetSurface`'s content is rendered rotated a half turn from what
    // its geometry says, not merely flipped on one axis. Root-causing that
    // (texture upload row/column order, or the plane's own UV winding)
    // did not finish inside this session's budget, and a probe built to
    // chase it hung on `pumpAndSettle` and then, worked around with
    // `runAsync`, read back an unrelated all-black frame — a second,
    // unexplained finding, not a confirmation of the first. Turning the
    // child here a half turn fixes what this app shows without touching
    // `flutter3d_session` blind; `doc/tooling-plan.md`'s own edu-04 entry
    // names the open question for whoever next hosts a `WidgetSurface`
    // with legible content — `edu-00` §7's own annotation widget among
    // them.
    final panel = WidgetSurface(
      device: device,
      width: 1.8,
      height: 1.1,
      name: 'pendulum-panel',
      child: Transform.flip(
        flipX: true,
        flipY: true,
        child: PendulumLabPanel(
          lengthMeters: _length,
          onChangeLength: (value) {
            _pendulum.lengthMeters = value;
            _length.value = value;
          },
        ),
      ),
    )..setPosition(Vector3(1.6, 1.9, -1.6));
    scene.add(panel.node);

    _scene = scene;
    _camera = camera;
    _bob = bob;
    _string = string;
    _panel = panel;
    _placeBob();
    _placeString();

    _ticker = createTicker(_onTick)..start();
    if (mounted) setState(() => _renderer = Renderer.create(device: device));
  }

  void _placeBob() {
    final theta = _pendulum.theta;
    final length = _pendulum.lengthMeters;
    _bob.setPositionFrom(
      Vector3(
        _pivot.x + length * math.sin(theta),
        _pivot.y - length * math.cos(theta),
        _pivot.z,
      ),
    );
  }

  /// Stretches and aims the unit-height cylinder from the pivot to wherever
  /// [_placeBob] just put the bob — a string has no simulation of its own,
  /// only the two points [PendulumSimulation] already gives a reason to
  /// know.
  void _placeString() {
    final pivot = _pivot;
    final bobAt = _bob.readPosition();
    final delta = bobAt - pivot;
    final length = math.max(delta.length, 1e-6);
    _string
      ..setScale(1.0, length, 1.0)
      // The cylinder's own local +Y is its long axis (`CylinderShape`'s own
      // doc comment); this is the rotation that takes that axis to wherever
      // the bob actually is, not a yaw/pitch pair guessed and checked.
      ..setRotation(
        Quaternion.fromTwoVectors(Vector3(0.0, 1.0, 0.0), delta.normalized()),
      )
      ..setPositionFrom(pivot + delta.scaled(0.5));
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // The first callback's `elapsed` is already nonzero (a ticker's clock
    // starts when the scheduler binding did, not when this one started), so
    // clamping is what stands in for "skip the first frame" without a bool.
    //
    // Fixed steps of `labFixedDt`, not the raw frame `dt`: `_lengths`'s own
    // step numbers are what `LabReviewPanel` shows a teacher, and a step
    // that means a different amount of real time on every frame would make
    // "diverged at step 40" say nothing a teacher could act on.
    _stepAccumulator += dt.clamp(0.0, 0.05);
    while (_stepAccumulator >= labFixedDt) {
      _stepAccumulator -= labFixedDt;
      _lengths.record(_step, <String, Object?>{
        'length': _pendulum.lengthMeters,
      });
      _pendulum.step(labFixedDt);
      _step++;
    }
    _placeBob();
    _placeString();
    unawaited(_panel.tick());
    if (mounted) setState(() {});
  }

  /// The same raycast `flutter3d_template_app`'s own `_tapWidgetSurface`
  /// proved for `tpl-04` — a real tap, through [Raycaster], landing on the
  /// panel exactly the way a player's would in a shipped level.
  bool _tapPanel(Offset local) {
    final size = context.size;
    if (size == null || size.width <= 0.0 || size.height <= 0.0) return false;
    final hit = _raycaster
        .setFromScreen(
          _camera,
          local.dx,
          local.dy,
          width: size.width,
          height: size.height,
        )
        .intersectScene(_scene);
    if (hit == null || hit.node != _panel.node) return false;
    final surfaceUv = _panel.uvAt(hit.point);
    if (surfaceUv == null) return false;

    // `uvAt` answers in mesh-UV — where the tap physically landed on the
    // panel's surface, purely from geometry. Empirically, not by the same
    // reasoning that fixed display: inverting both axes here (the naive
    // mirror of `Transform.flip(flipX: true, flipY: true)`) hit a real
    // button, but the wrong one — `+` acted as `-`. `uvAt`'s own `u` must
    // already run the opposite way from the pipeline's, independently of
    // the display bug, so only `v` wants inverting here. Found live, by a
    // person actually pressing the buttons — not re-derived from the
    // display fix a second time, since the first re-derivation already
    // predicted the wrong answer once.
    final uv = Offset(surfaceUv.dx, 1.0 - surfaceUv.dy);

    const pointer = 9001;
    _panel.pipeline.announcePointer(pointer, added: true);
    _panel.pipeline.dispatchAtUv(
      uv,
      (local) => PointerDownEvent(pointer: pointer, position: local),
    );
    _panel.pipeline.dispatchAtUv(
      uv,
      (local) => PointerUpEvent(pointer: pointer, position: local),
    );
    _panel.pipeline.announcePointer(pointer, added: false);
    return true;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) {
      return DidNotStart(
        initError,
        background: const Color(0xFF14161A),
        foreground: const Color(0xFFFF8A80),
      );
    }
    final renderer = _renderer;
    if (renderer == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF14161A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Listener(
        onPointerDown: (PointerDownEvent event) =>
            _tapPanel(event.localPosition),
        child: SceneSurface(
          renderer: renderer,
          scene: _scene,
          view: RenderView(camera: _camera),
          settings: () => const RenderSettings(),
          onBeforeFrame: () {},
        ),
      ),
      floatingActionButton: LabReviewButton(onPressed: _showReview),
    );
  }

  /// `ls-e-01`'s teacher screen: names the first fixed step this run's own
  /// length differs from [_assignedLength], from [_lengths] — the run
  /// actually recorded, not a re-simulation.
  void _showReview() {
    final assignment = DataSourceTrace();
    for (final step in _lengths.steps) {
      assignment.record(step, <String, Object?>{'length': _assignedLength});
    }
    final divergence = firstLabDivergence(assignment, _lengths, path: 'length');
    showDialog<void>(
      context: context,
      builder: (context) => LabReviewPanel(
        assignedLength: _assignedLength,
        divergence: divergence,
        stepsPerSecond: (1.0 / labFixedDt).round(),
      ),
    );
  }
}
