/// A first-person sandbox of blocks.
///
///     flutter run -d macos
///
/// **The game `flutter3d_voxel` is for.** Rolling hills drawn from a seed,
/// in sixty-four metres square of chunks: walk them, dig the block you look
/// at, put one from the hotbar against the face you look at, and quit — the
/// next launch finds the world as it was left, because what is kept is the
/// seed and the edits, never the blocks.
///
/// What it exercises, each through the package rather than beside it:
///
/// * **Meshes** — every chunk is a node a material, and an edit draws again
///   only the chunks whose faces it moved (`ChunkMeshes`).
/// * **Collision** — the body is a `CharacterController` in a
///   `CollisionWorld` the chunks' greedy boxes are in, attached to the run's
///   physics: the native core where it starts, the Dart reference with
///   `--dart-define=FLUTTER3D_PHYSICS=dart`.
/// * **Navigation** — the navigation mesh is baked again where each edit
///   lands, and the HUD says whether the body could still walk back to where
///   it started: wall yourself in and it says no.
/// * **Saves** — the world, the body, the hotbar and the hour, as a
///   `Snapshot`, a few seconds after the last edit and when the window goes.
/// * **The sky** — the air's own, over a day of twenty minutes, with stars
///   at night; see `Daylight` in `flutter3d_game_kit/world.dart`.
/// * **Photo mode** — P stops the world and hands over a camera; see
///   `photo_mode.dart`.
///
/// * **Replays** — every step reads its input, so the play is recorded as
///   it happens: F5 keeps the run so far as a `.f3drun` — the tape, the
///   loop's journal, each step's events, checkpoints of the whole state and
///   where the body and the falling blocks went — and F9 plays the last one
///   kept back from its start and says whether it went where it went.
///
/// W A S D walk, space jumps, shift runs, drag to look. A click digs, a
/// right click places — or Q and E — and 1 to 5 or the wheel pick a block.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show DemoFile, DemoReplay, DesktopInput;
import 'package:flutter3d_game_physics/elements.dart' show DaylightOnWater;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show physicsFallbackReason, preparePhysics, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show EngineLoop, InputState, ReplayException;

import 'src/block_surfaces.dart';
import 'src/chunk_meshes.dart';
import 'src/elements.dart';
import 'src/palette.dart';
import 'src/photo_mode.dart';
import 'src/runs.dart';
import 'src/staging.dart';

/// What this build calls itself in a run file.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The run's physics, chosen once: the core, which the browser fetches as
  // WebAssembly, or the reference where it will not start.
  await preparePhysics();
  // The world as it was left, read before the first frame so the window
  // comes up on the right world.
  final storage = defaultStorage('flutter3d_demo_sandbox');
  final saved = await storage.read(sandboxSaveName);
  runApp(SandboxApp(storage: storage, saved: saved));
}

/// The application: one screen.
class SandboxApp extends StatelessWidget {
  /// The sandbox, in a window of its own, over the world [saved] in
  /// [storage].
  const SandboxApp({super.key, required this.storage, this.saved});

  /// Where the world is kept.
  final Storage storage;

  /// The world as it was left, or null for a new one.
  final String? saved;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Voxel Sandbox',
    debugShowCheckedModeBanner: false,
    home: SandboxScreen(storage: storage, saved: saved),
  );
}

/// Opens the device and the saved world, and plays it.
class SandboxScreen extends StatefulWidget {
  /// The one screen, over the world [saved] in [storage].
  const SandboxScreen({super.key, required this.storage, this.saved});

  /// Where the world is kept.
  final Storage storage;

  /// The world as it was left, or null for a new one.
  final String? saved;

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

/// The frame's exposure, below the renderer's default: with the block
/// pictures on, a sunlit top at the default rolled off to nearly white, its
/// picture and the shade in its corners gone with it.
const double _exposure = 1.1;

/// The sun's shadows at twice the renderer's default tile. Every edge in a
/// world of blocks is a long straight one, and the sun crosses them at a
/// slant, so at the default a step's shadow came out as a saw of texels
/// along the sand.
const ShadowSettings _shadows = ShadowSettings(resolution: 2048);

/// What the screen holds once the device is open.
typedef _Playing = ({Renderer renderer, Scene scene, ChunkMeshes meshes});

class _SandboxScreenState extends State<SandboxScreen>
    with SingleTickerProviderStateMixin {
  late final Storage _storage = widget.storage;

  /// The world as it was left, or a new one: before the device opens, so
  /// the window comes up on the right world.
  late final SandboxRun _run = SandboxRun.fromSaved(
    widget.saved,
    backend: usePhysics(),
  );

  final CameraNode _camera = CameraNode(name: 'eye');

  /// Nearly nothing shows this: the sky is drawn wherever no block stands.
  /// It is what is behind the first frames, before the world has loaded.
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColorSrgb: Vector4(0.55, 0.72, 0.9, 1.0),
  );

  /// The sun and the moon, moved along the day by [Daylight.light] every
  /// frame. The sun first: the renderer shadows the first one that asks.
  final LightNode _sun = LightNode(name: 'sun');
  final LightNode _moon = LightNode(name: 'moon');

  /// P stops the world and hands the player a camera.
  final PhotoMode _photo = sandboxPhotoMode();

  final InputState _input = InputState();
  late final DesktopInput _keys = DesktopInput(
    state: _input,
    actions: sandboxActionMap(),
  );
  final FocusNode _keyboard = FocusNode();

  /// Saves when the window is hidden or goes, whatever is waiting.
  late final AppLifecycleListener _lifecycle;

  final FrameClock _frames = FrameClock();
  Ticker? _ticker;

  /// What a drag turned the eye by since the last step, handed to the loop,
  /// which spreads it over the frame's steps.
  final Vector2 _drag = Vector2.zero();

  /// The run's loop: its fixed steps, phase by phase, then the frame —
  /// the day's light, the chunks drawn again, the save. Stopped while a
  /// photo is taken.
  late final EngineLoop _loop = _loopFor();

  /// The run being recorded, and the last one kept. Begun once the elements
  /// are up, since the state it starts from holds them.
  late final SandboxRuns _runs = SandboxRuns(
    loop: _loop,
    run: _run,
    file: DemoFile(appName: 'flutter3d_demo_sandbox'),
    buildStamp: _buildStamp,
    platform: defaultTargetPlatform.name,
  );

  /// What the last keep or replay came to, for the status.
  String _said = 'F5 keeps the run · F9 plays the last one back';

  EngineLoop _loopFor() {
    final loop = EngineLoop(
      input: _input,
      drainLook: (Vector2 out) {
        out.add(_drag);
        _drag.setZero();
      },
    );
    _run.install(loop, _input);
    loop
      ..addSystem('sandbox.daylight', LoopPhase.animate, (_) {
        _run.day.light(sun: _sun, moon: _moon);
        if (_run.elements case final elements?) {
          _run.day.lightWater(elements.elements);
        }
      })
      ..addSystem('sandbox.chunks', LoopPhase.render, (_) {
        final stale = _run.takeStaleSurfaces();
        if (stale.isNotEmpty) _playing?.meshes.refresh(stale);
      })
      ..addSystem('sandbox.save', LoopPhase.ui, (frame) {
        if (!_run.unsaved) return;
        _sinceEdit += frame.realDt;
        if (_sinceEdit > 3.0) _save();
      });
    return loop;
  }

  /// Seconds since the last edit was saved, counting only while one is
  /// waiting: a save a few seconds after building stops, not one a block.
  double _sinceEdit = 0.0;

  /// Where a press went down and with which buttons, to tell a click from
  /// a drag.
  ({Offset at, int buttons})? _down;
  double _dragged = 0.0;

  _Playing? _playing;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _save, onDetach: _save);
    _ticker = createTicker(_onTick)..start();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final device = await openDevice(width: 1280, height: 720);
      // The ambient's colour is the sky's: the renderer takes it from the
      // physical sky, so it is blue at noon and dark at midnight with no tint
      // typed for either.
      _run.day.light(sun: _sun, moon: _moon);
      final scene = Scene()
        ..ambientIntensity = 0.35 * Photometric.legacyUnit
        ..add(_sun)
        ..add(_moon)
        ..add(_camera);
      // A picture a block face, from `assets/blocks/`.
      final surfaces = await BlockSurfaces.load(device, rootBundle);
      final meshes = ChunkMeshes(
        device,
        scene,
        _run.blocks,
        surfaces: surfaces,
      );
      final renderer = Renderer.create(device: device);
      // Water over the blocks and fire through the planks: the physics
      // core's, drawn and heard by the effects package.
      final elements = await Elements.open(
        device: device,
        renderer: renderer,
        scene: scene,
        load: rootBundle.load,
        quality: const ElementsQuality(
          liquid: LiquidDetail.light,
          fire: FireDetail.full,
        ),
      );
      if (!mounted) {
        elements.dispose();
        return;
      }
      _run.elements = BlockElements(
        blocks: _run.blocks,
        elements: elements,
        device: device,
        setBlock: _run.setBlock,
        surfaces: surfaces,
      );
      _runs.begin();
      setState(
        () => _playing = (renderer: renderer, scene: scene, meshes: meshes),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onTick(Duration _) {
    final dt = _frames.tick();
    if (_playing == null) return;
    // The world is stopped while a photo is framed, the day with it: no
    // step runs, and what the keys and the drag ask for goes to the photo
    // camera.
    _loop.isPaused = _photo.isActive;
    if (_photo.isActive) _photo.fly(dt);
    _loop.frame(dt);
    // Not while a photo is drawn: a rebuild draws a frame on the renderer the
    // tiles are drawn on — see `capturePhoto`.
    if (mounted && !_photo.isBusy) setState(() {});
  }

  /// Opens photo mode where the eye is, or closes it.
  void _togglePhoto() {
    if (_photo.isActive) {
      setState(_photo.leave);
      return;
    }
    // Whatever the hands were holding is let go, or the walk comes back
    // out of photo mode still walking.
    _input.clear();
    setState(
      () => _photo.enter(
        world: _run.physics,
        eye: _run.eye,
        target: _run.eye + _run.gaze,
        anchor: _run.walk.body.position,
      ),
    );
  }

  /// Draws the photo at [scale] times the window and saves it.
  Future<void> _takePhoto(int scale) async {
    final playing = _playing;
    if (playing == null || _photo.isBusy) return;
    final size =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    setState(() => _photo.isBusy = true);
    // The frame saying so is drawn first; after it nothing redraws until the
    // picture is done.
    await SchedulerBinding.instance.endOfFrame;
    final taken = await savePhoto(
      renderer: playing.renderer,
      scene: playing.scene,
      camera: _camera,
      width: (size.width * scale).round(),
      height: (size.height * scale).round(),
      settings: _settings(filtered: false),
      filter: _photo.filter,
      clearColorSrgb: _view.clearColorSrgb,
      shelf: defaultPhotoShelf('sandbox'),
      name: 'sandbox-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (!mounted) return;
    setState(() {
      _photo
        ..isBusy = false
        ..said = taken.saved.message;
    });
  }

  /// What every frame is drawn with: the day's sky, and in photo mode the
  /// chosen filter when [filtered], and the photo camera's exposure once its
  /// dials have been turned.
  RenderSettings _settings({bool filtered = true}) {
    final game = RenderSettings(
      exposure: _exposure,
      shadows: _shadows,
      sky: _run.day.sky,
      look: filtered && _photo.isActive
          ? _photo.look(const LookSettings())
          : const LookSettings(),
    );
    return _photo.isActive ? _photo.settings(game) : game;
  }

  /// Puts the eye on the camera, or the photo camera when one is flying.
  void _placeCamera() {
    if (_photo.isActive) {
      _photo.applyTo(_camera);
    } else {
      _camera.projection = _photo.lens;
      _run.walk.placeCamera(_camera);
    }
  }

  void _save() {
    _sinceEdit = 0.0;
    if (_run.unsaved) _run.save(_storage).ignore();
  }

  /// Keeps the run so far, and says so.
  void _keep() {
    final kept = _runs.keep();
    setState(
      () => _said = kept == null
          ? 'Nothing to keep yet'
          : 'Kept a run of ${kept.tape.steps} steps',
    );
  }

  /// Plays the last run kept back from its start, and says how it went.
  Future<void> _replay() async {
    // The world is stopped while a photo is framed; a replay would move it.
    if (_photo.isActive) return;
    String said;
    try {
      final replay = await _runs.replay();
      said = switch (replay) {
        null => 'No run kept to play back',
        DemoReplay(divergence: final d?) =>
          'Played ${replay.steps} steps; it parted at step ${d.step}',
        DemoReplay(eventDivergence: final e?) =>
          'Played ${replay.steps} steps; the events parted at step ${e.step}',
        _ => 'Played ${replay.steps} steps, every checkpoint matched',
      };
    } on ReplayException catch (refused) {
      said = 'Not replayed: ${refused.message}';
    } on FormatException catch (error) {
      said = 'Not replayed: ${error.message}';
    }
    if (!mounted) return;
    setState(() => _said = said);
  }

  void _onPointerUp(PointerUpEvent event) {
    final down = _down;
    _down = null;
    // A click in photo mode digs nothing: the world is stopped.
    if (down == null || _dragged > 6.0 || _photo.isActive) return;
    final action = down.buttons & kSecondaryMouseButton != 0
        ? SandboxActions.place
        : SandboxActions.dig;
    _input
      ..press(action)
      ..release(action);
  }

  @override
  void dispose() {
    _save();
    _ticker?.dispose();
    _lifecycle.dispose();
    _keyboard.dispose();
    unawaited(_keys.dispose());
    _runs.dispose();
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch ((_error, _playing)) {
    (final Object error, _) => DidNotStart(
      error,
      background: const Color(0xFF14161A),
      foreground: const Color(0xFFFF8A80),
    ),
    (_, null) => const ColoredBox(
      color: Color(0xFF14161A),
      child: Center(child: CircularProgressIndicator()),
    ),
    (_, final _Playing playing) => _game(playing),
  };

  Widget _game(_Playing playing) => Scaffold(
    backgroundColor: const Color(0xFF14161A),
    body: Focus(
      focusNode: _keyboard,
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            !_photo.isBusy &&
            (event.logicalKey == LogicalKeyboardKey.keyP ||
                (_photo.isActive &&
                    event.logicalKey == LogicalKeyboardKey.escape))) {
          _togglePhoto();
          return KeyEventResult.handled;
        }
        final photoSays = _photo.key(
          event,
          onCapture: (int scale) => unawaited(_takePhoto(scale)),
        );
        if (photoSays != null) {
          setState(() {});
          return photoSays;
        }
        // Flint and a bucket: the elements' own keys, past the walk's.
        if (event is KeyDownEvent) {
          // As actions, taken by the next step like a dig or a place.
          if (event.logicalKey == LogicalKeyboardKey.keyF) {
            _input
              ..press(SandboxActions.strike)
              ..release(SandboxActions.strike);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyR) {
            _input
              ..press(SandboxActions.pour)
              ..release(SandboxActions.pour);
            return KeyEventResult.handled;
          }
          // The run: kept, or played back. Not input — nothing a step
          // reads, and nothing a tape should hold.
          if (event.logicalKey == LogicalKeyboardKey.f5) {
            _keep();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f9) {
            _replay();
            return KeyEventResult.handled;
          }
        }
        return _keys.handleKeyEvent(event);
      },
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          _keyboard.requestFocus();
          _down = (at: event.localPosition, buttons: event.buttons);
          _dragged = 0.0;
        },
        onPointerMove: (PointerMoveEvent event) {
          if (_down == null) return;
          _dragged += event.delta.distance;
          if (_photo.isActive) {
            _photo.turn(
              event.delta.dx,
              event.delta.dy,
              perPixel: _run.walk.lookSpeed,
            );
          } else {
            _drag.add(Vector2(event.delta.dx, event.delta.dy));
          }
        },
        onPointerUp: _onPointerUp,
        onPointerSignal: (PointerSignalEvent event) {
          if (event is! PointerScrollEvent || _photo.isActive) return;
          final by = event.scrollDelta.dy > 0 ? 1 : hotbar.length - 1;
          _input.requestSlot((_run.slot + by) % hotbar.length);
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SceneSurface(
              renderer: playing.renderer,
              scene: playing.scene,
              view: _view,
              settings: _settings,
              onBeforeFrame: _placeCamera,
              presentFrame: presentFrame,
            ),
            // In photo mode the picture is the world, and the bar is all
            // that is over it.
            if (_photo.isActive)
              PhotoBar(mode: _photo)
            else ...<Widget>[
              const IgnorePointer(child: Center(child: _Crosshair())),
              Positioned(
                left: 16,
                top: 16,
                child: SafeArea(
                  child: _Status(run: _run, said: _said),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(child: _Hotbar(selected: _run.slot)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 14,
    height: 14,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xCCFFFFFF), width: 2),
        ),
      ),
    ),
  );
}

/// What is looked at, whether home is still reachable, and the controls.
class _Status extends StatelessWidget {
  const _Status({required this.run, required this.said});

  final SandboxRun run;

  /// What the last keep or replay came to.
  final String said;

  @override
  Widget build(BuildContext context) {
    final hit = run.target;
    final looked = hit == null
        ? 'nothing in reach'
        : '${blockKinds[run.blocks.at(hit.x, hit.y, hit.z)]?.name ?? 'a block'}'
              ' at ${hit.x}, ${hit.y}, ${hit.z}';
    final physics = physicsFallbackReason == null
        ? usePhysics().name
        : '${usePhysics().name} (the core would not start)';
    return DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        shadows: <Shadow>[Shadow(blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Looking at $looked'),
          Text(
            run.homeReachable
                ? 'The way home is open'
                : 'No way home on foot from here',
          ),
          Text('${run.blocks.editCount} blocks changed · physics: $physics'),
          Text(said),
          const SizedBox(height: 6),
          const Text(
            'WASD walk · space jumps · drag to look · click digs · '
            'right click places · 1–5 picks · F strikes flint at planks · '
            'R tips a bucket of water · P photo mode · F5 keep the run · '
            'F9 play it back',
            style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Hotbar extends StatelessWidget {
  const _Hotbar({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (var i = 0; i < hotbar.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _Swatch(kind: blockKinds[hotbar[i]]!, chosen: i == selected),
        ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.kind, required this.chosen});

  final BlockKind kind;
  final bool chosen;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    // The block's side, the picture it is drawn with, over its colour for
    // the moment before the picture is read.
    decoration: BoxDecoration(
      color: Color.from(
        alpha: 1,
        red: kind.color.x,
        green: kind.color.y,
        blue: kind.color.z,
      ),
      image: DecorationImage(
        image: AssetImage('assets/blocks/${kind.side}.jpg'),
        fit: BoxFit.cover,
      ),
      border: Border.all(
        color: chosen ? Colors.white : const Color(0x66000000),
        width: chosen ? 3 : 1,
      ),
    ),
    alignment: Alignment.bottomCenter,
    child: Text(
      kind.name,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        shadows: <Shadow>[Shadow(blurRadius: 3)],
      ),
    ),
  );
}
