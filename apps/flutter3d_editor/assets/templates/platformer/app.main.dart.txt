/// A level you can walk around, which is what a new project starts as.
///
///     flutter run -d macos
///
/// **This is a seed, not a game.** It reads the level in `assets/levels/`,
/// builds it, and puts a body in it that walks, looks and jumps. What it
/// deliberately does not do is anything a *genre* does: no weapons, no
/// monsters, no coins, no doors that open, no score, no menu, no saving. Those
/// live in `flutter3d_game_shooter` and `flutter3d_game_platformer`, and wiring one
/// up is the next thing to do here — the three games in this repository are the
/// worked examples, and each of them keeps that wiring in its own
/// `lib/src/staging.dart`.
///
/// It is a real application in this repository as well as a template, so that
/// it is analysed and compiled by CI. **A `main.dart` that is only ever a
/// string in a scaffolder is one that stops compiling six months later and
/// nobody finds out until somebody creates a project.**
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_twin/flutter3d_twin.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/template_widgets.dart';

/// The level this project opens with.
const String kLevel = String.fromEnvironment(
  'level',
  defaultValue: 'assets/levels/first.json',
);

/// `tpl-04`'s viewer: an `edu_sequence`'s own `steps`, resolved to the
/// caption each named `edu_step` carries, in the order the sequence names
/// them — the same ordering rule `edu-01`'s `orderedSteps` already proved,
/// repeated here in five lines rather than pulling a document-authoring
/// package into a running game's dependencies. A level with no `edu_sequence`
/// answers with nothing, which [ViewerTourController.setCaptions] already
/// turns into its own placeholder.
///
/// Public rather than private: `test/tpl04_levels_test.dart` calls this
/// directly against a level read with no window, the same way
/// `test/level_cubit_test.dart` already drives [LevelCubit] with no window.
List<String> stepCaptions(Level level) {
  EntityDef? sequence;
  for (final entity in level.entities) {
    if (entity.type == 'edu_sequence') {
      sequence = entity;
      break;
    }
  }
  final names = sequence?.properties['steps'];
  if (names is! List) return const <String>[];

  return <String>[
    for (final name in names)
      if (name is String) level.named(name)?.string('caption') ?? '?',
  ];
}

/// `tpl-04`'s twin: the one `edu_step` naming `bindings`, if this level has
/// one — `edu-05`'s own format keeps a binding on a step rather than on the
/// document, so this is where a level names which step's reading is live.
EntityDef? stepWithBindings(Level level) {
  for (final entity in level.entities) {
    if (entity.type == 'edu_step' && entity.properties['bindings'] is List) {
      return entity;
    }
  }
  return null;
}

void main() => runApp(const TemplateApp());

class TemplateApp extends StatelessWidget {
  const TemplateApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A level',
    debugShowCheckedModeBanner: false,
    home: const LevelScreen(),
  );
}

/// A kind for a type this application has not been taught.
///
/// **The level names things the game does not spawn yet** — a monster, a
/// pickup, a lift — and a registry that has never heard of them refuses to load
/// the document at all. So every type in the document is accepted and none of
/// them is given a meaning: they are coordinates with words attached until
/// there is something to spawn them into.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

/// What the level is doing, as far as the screen is concerned.
///
/// Screen state, and only that — this seed has no restart, no next level and
/// no save to model, so a plain `Cubit` over three states is enough on its own.
/// `RunSession`, in `flutter3d_session`, is for once one of those shows up; see
/// its doc comment for why [LevelReady] below is still safe to hold the scene
/// and the body in even then — they do not change sixty times a second, only
/// what is inside them does, and that is read by the render loop directly
/// rather than republished as a new state on every frame.
sealed class LevelState {
  const LevelState();
}

/// Before the level is up.
final class LevelLoading extends LevelState {
  const LevelLoading();
}

/// The level is built: a scene to draw, a body to walk it with.
final class LevelReady extends LevelState {
  const LevelReady(
    this.scene,
    this.body, {
    required this.yaw,
    required this.level,
    this.widgetSurfaces,
  });

  final Scene scene;
  final CharacterController body;

  /// Which way the spawn faces, in radians.
  final double yaw;

  /// The document itself, kept rather than thrown away once built — `tpl-04`'s
  /// three templates read an `edu_step`'s caption or bindings back off it
  /// every frame, which nothing before `tpl-04` needed a live `Level` for.
  final Level level;

  /// `wg-01`'s bridge for this level's `widget_surface` entities, or null when
  /// [level] named none. Ticked once a frame by [LevelScreen] and raycast
  /// against on a tap, the same two calls `wg-02`'s own demo already proved.
  final WidgetSurfaceVisuals? widgetSurfaces;
}

/// The level would not load, and why.
///
/// **A level that will not read used to be a black screen for ever**: the load
/// caught its own throw and printed it, which is a line in a console nobody
/// playing the game can see.
final class LevelFailed extends LevelState {
  const LevelFailed(this.error);

  final Object error;
}

/// Reads [kLevel] and builds everything it takes to walk around in it.
///
/// [device] is taken rather than opened in here, the same split
/// `flutter3d_demo_dungeon`'s `DungeonRun` makes and for the same reason: a
/// test can hand over a `CpuDevice` and drive the whole load without a window,
/// which is what `test/level_cubit_test.dart` does.
class LevelCubit extends Cubit<LevelState> {
  LevelCubit() : super(const LevelLoading());

  /// [world] is where the body collides; [camera] is added to the scene once
  /// it is built, so the widget never has to reach back in and do it. [asset]
  /// defaults to [kLevel] — overridable so a test can point at a level that is
  /// not there and see [LevelFailed] rather than a hang.
  Future<void> open(
    GraphicsDevice device, {
    required CollisionWorld world,
    required CameraNode camera,
    String asset = kLevel,
    Map<String, WidgetBuilder> widgetRegistry = const <String, WidgetBuilder>{},
  }) async {
    try {
      // Read first, build second: the registry is made out of what the
      // document happens to name, which is not knowable before reading it.
      final level = Level.fromJson(
        jsonDecode(await rootBundle.loadString(asset)) as Map<String, Object?>,
      );
      final loaded = await LevelLoader().build(
        level,
        device: device,
        registry: EntityRegistry(<EntityKind>[
          for (final type
              in level.entities.map((EntityDef e) => e.type).toSet())
            OpenKind(type),
        ]),
      );
      loaded.level.addTo(world);

      // Where the author said somebody stands, lifted by half a body: a spawn
      // is authored at the feet, which is the only place an author can see.
      final spawn = level.entities
          .where((EntityDef it) => it.type.contains('spawn'))
          .firstOrNull;
      final at = (spawn?.position ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0);

      // `tpl-04`: every `widget_surface` this document names, resolved
      // through whatever the caller's own registry knows — a level with none
      // gets a `WidgetSurfaceVisuals` that never adds a node, not a null
      // check scattered through the render loop.
      final widgetSurfaces = WidgetSurfaceVisuals(
        loaded.scene,
        device: device,
        registry: widgetRegistry,
      );
      for (final entity in level.entities) {
        widgetSurfaces.add(entity);
      }

      emit(
        LevelReady(
          loaded.scene..add(camera),
          CharacterController(world: world, position: at),
          yaw: spawn?.yaw ?? 0.0,
          level: level,
          widgetSurfaces: widgetSurfaces,
        ),
      );
    } catch (error) {
      emit(LevelFailed(error));
    }
  }

  @override
  Future<void> close() {
    final current = state;
    if (current is LevelReady) current.widgetSurfaces?.dispose();
    return super.close();
  }
}

class LevelScreen extends StatefulWidget {
  const LevelScreen({super.key});

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen>
    with SingleTickerProviderStateMixin {
  Renderer? _renderer;

  /// The device failed to open, or the renderer failed to build on top of it.
  /// Kept apart from [LevelFailed]: that is a level's own document being
  /// wrong, this is the machine underneath being unable to draw at all, and
  /// the two want different words on screen.
  Object? _initError;

  final CollisionWorld _world = CollisionWorld();

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.05, 0.05, 0.07, 1.0),
  );

  final InputState _input = InputState();
  late final DesktopInput _keys = DesktopInput(state: _input);
  final FocusNode _keyboard = FocusNode();

  double _yaw = 0.0;
  double _pitch = 0.0;
  Offset? _dragged;

  Ticker? _ticker;

  /// How long since the last frame, and how long since the first.
  final FrameClock _frames = FrameClock();

  /// Owned here rather than reached for through `BlocProvider.of`: nothing
  /// else in this seed needs to see it, and the game loop below reads its
  /// state directly, sixty times a second, which is no place for a lookup.
  final LevelCubit _level = LevelCubit();

  /// `tpl-04`'s own state, shared by whichever of the three templates is
  /// open — a level with none of these entities simply never touches them.
  final ViewerTourController _tour = ViewerTourController();
  final ConfiguratorController _configurator = ConfiguratorController();
  final ValueNotifier<double> _twinReading = ValueNotifier<double>(0.0);
  final DataSourceRegistry _dataSources = twinDataSources();
  int _twinStep = 0;

  /// The `edu_step` naming this level's `bindings`, if any — resolved once at
  /// load rather than searched for every frame.
  EntityDef? _boundStep;

  /// For a tap: `wg-01`'s own chain, against the render scene rather than
  /// [CollisionWorld] — a `widget_surface` is a mesh in [Scene], not
  /// something a player collides with.
  final Raycaster _raycaster = Raycaster();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    unawaited(_open());
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
      // Through `openDevice` rather than by naming a backend — see
      // `src/backend.dart`. It picks Impeller or WebGL for the build, and
      // falls back to the software rasteriser at run time when flutter_gpu
      // will not start, which is the difference between a window that draws
      // slowly and one that draws nothing.
      //
      // The size is what the software fallback would draw at; the two hardware
      // backends size themselves to the surface and ignore it.
      device = await openDevice(width: 1280, height: 720);
      if (!mounted) return;
      setState(() => _renderer = Renderer.create(device: device));
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    // The cubit handles its own failures from here — see [LevelFailed] —
    // so nothing thrown by a bad document reaches this `try` at all.
    await _level.open(
      device,
      world: _world,
      camera: _camera,
      widgetRegistry: templateWidgetRegistry(
        viewerTour: _tour,
        configurator: _configurator,
        twinReading: _twinReading,
      ),
    );
    final ready = _level.state;
    if (ready is LevelReady) {
      _tour.setCaptions(stepCaptions(ready.level));
      _boundStep = stepWithBindings(ready.level);
    }
  }

  void _onTick(Duration _) {
    // The ticker's argument is the frame's scheduled time, not the present;
    // `FrameClock` says why the wall is measured instead.
    final dt = _frames.tick();

    final state = _level.state;
    if (state is! LevelReady) return;
    final body = state.body;

    if (_input.pressed(GameAction.jump)) body.requestJump();

    // Where the keys are asking to go, turned by where the head is pointing.
    final wish = _input.moveAxis;
    final forward = Vector3(math.sin(_yaw), 0.0, -math.cos(_yaw));
    final right = Vector3(-forward.z, 0.0, forward.x);
    body.step(
      dt.clamp(0.0, 0.1),
      wishDirection: Vector3(
        forward.x * wish.y + right.x * wish.x,
        0.0,
        forward.z * wish.y + right.z * wish.x,
      ),
      sprint: _input.held(GameAction.sprint),
    );

    // `tpl-04`: redraws every `widget_surface` this level named, only when
    // its own pipeline actually asked to (`wg-00`'s own rule, not repeated
    // here).
    final widgetSurfaces = state.widgetSurfaces;
    if (widgetSurfaces != null) unawaited(widgetSurfaces.tickAll());

    // `edu-05`'s own mechanism: a data source sampled every step, written to
    // wherever the level's own `bindings` say — here, straight into the
    // dashboard's own notifier, since this seed has nowhere else for a
    // "sensor value" to live.
    final boundStep = _boundStep;
    if (boundStep != null) {
      _twinStep++;
      final resolved = resolveBindings(boundStep, _twinStep, _dataSources);
      final value = resolved['dashboard.temperature'];
      if (value is num) _twinReading.value = value.toDouble();
    }

    if (mounted) setState(() {});
  }

  /// Puts the camera at eye height, looking where the mouse has been dragged.
  void _place() {
    final state = _level.state;
    if (state is! LevelReady) return;
    final eye = state.body.position + Vector3(0.0, 0.7, 0.0);
    final cosPitch = math.cos(_pitch);
    _camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(
        eye +
            Vector3(
              math.sin(_yaw) * cosPitch,
              math.sin(_pitch),
              -math.cos(_yaw) * cosPitch,
            ),
        up: Vector3(0.0, 1.0, 0.0),
      );
  }

  /// `tpl-04`: the first place in this repository that raycasts a real
  /// pointer against a running scene to find a `widget_surface` — every
  /// earlier proof of `wg-00`/`wg-01`'s own chain (raycast → `uvAt` →
  /// `dispatchAtUv`) built its ray by hand in a test; this builds it from an
  /// actual tap, through [Raycaster], since a `widget_surface` is a node in
  /// [Scene] rather than a [CollisionWorld] collider.
  ///
  /// Dispatches a whole tap (down and up together) rather than tracking a
  /// captured pointer across [onPointerMove]/[onPointerUp]: `wg-01`'s own
  /// write-up found that a drag through this same path never reaches a
  /// `Scrollable` at all, so a tap is the one gesture this seed can offer
  /// honestly.
  bool _tapWidgetSurface(Offset local) {
    final state = _level.state;
    if (state is! LevelReady) return false;
    final surfaces = state.widgetSurfaces?.surfaces;
    if (surfaces == null || surfaces.isEmpty) return false;

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
        .intersectScene(state.scene);
    if (hit == null) return false;

    for (final surface in surfaces) {
      if (hit.node != surface.node) continue;
      final uv = surface.uvAt(hit.point);
      if (uv == null) return false;

      const pointer = 9000;
      surface.pipeline.announcePointer(pointer, added: true);
      surface.pipeline.dispatchAtUv(
        uv,
        (local) => PointerDownEvent(pointer: pointer, position: local),
      );
      surface.pipeline.dispatchAtUv(
        uv,
        (local) => PointerUpEvent(pointer: pointer, position: local),
      );
      surface.pipeline.announcePointer(pointer, added: false);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
    unawaited(_keys.dispose());
    unawaited(_level.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) return _didNotStart(initError);

    final renderer = _renderer;
    if (renderer == null) return _loading();

    return BlocProvider.value(
      value: _level,
      // The listener is the one-time effect a fresh level brings — reading
      // which way the spawn faces — and the builder is everything that is
      // drawn from the state, including the one that is not playing yet.
      child: BlocConsumer<LevelCubit, LevelState>(
        listener: (BuildContext context, LevelState state) {
          if (state is LevelReady) _yaw = state.yaw;
        },
        builder: (BuildContext context, LevelState state) => switch (state) {
          LevelFailed(:final error) => _didNotStart(error),
          LevelLoading() => _loading(),
          LevelReady(:final scene) => _game(renderer, scene),
        },
      ),
    );
  }

  Widget _didNotStart(Object error) => DidNotStart(
    error,
    background: const Color(0xFF14161A),
    foreground: const Color(0xFFFF8A80),
  );

  Widget _loading() => const Scaffold(
    backgroundColor: Color(0xFF14161A),
    body: Center(child: CircularProgressIndicator()),
  );

  Widget _game(Renderer renderer, Scene scene) => Scaffold(
    backgroundColor: const Color(0xFF14161A),
    body: Focus(
      focusNode: _keyboard,
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) =>
          _keys.handleKeyEvent(event),
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          _keyboard.requestFocus();
          if (_tapWidgetSurface(event.localPosition)) return;
          _dragged = event.localPosition;
        },
        onPointerMove: (PointerMoveEvent event) {
          final from = _dragged;
          if (from == null) return;
          final by = event.localPosition - from;
          _dragged = event.localPosition;
          _yaw -= by.dx * 0.0032;
          _pitch = (_pitch - by.dy * 0.0032).clamp(-1.5, 1.5);
        },
        onPointerUp: (_) => _dragged = null,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SceneSurface(
              renderer: renderer,
              scene: scene,
              view: _view,
              settings: () => const RenderSettings(),
              onBeforeFrame: _place,
              presentFrame: presentFrame,
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Color(0xCC0E1013),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'W A S D walk · shift runs · space jumps · drag to look',
                    style: TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
