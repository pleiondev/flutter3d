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
/// * **Saves** — the world, the body and the hotbar, as a `Snapshot`, a few
///   seconds after the last edit and when the window goes.
///
/// W A S D walk, space jumps, shift runs, drag to look. A click digs, a
/// right click places — or Q and E — and 1 to 5 or the wheel pick a block.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show DesktopInput;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show physicsFallbackReason, preparePhysics, usePhysics;
import 'package:flutter3d_sim/flutter3d_sim.dart' show InputState;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/chunk_meshes.dart';
import 'src/palette.dart';
import 'src/staging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The run's physics, chosen once: the core, which the browser fetches as
  // WebAssembly, or the reference where it will not start.
  await preparePhysics();
  runApp(const SandboxApp());
}

/// The application: one screen.
class SandboxApp extends StatelessWidget {
  /// The sandbox, in a window of its own.
  const SandboxApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Voxel Sandbox',
    debugShowCheckedModeBanner: false,
    home: SandboxScreen(),
  );
}

/// Opens the device and the saved world, and plays it.
class SandboxScreen extends StatefulWidget {
  /// The one screen.
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

/// What the screen holds once the device is open.
typedef _Playing = ({Renderer renderer, Scene scene, ChunkMeshes meshes});

class _SandboxScreenState extends State<SandboxScreen>
    with SingleTickerProviderStateMixin {
  final Storage _storage = defaultStorage('flutter3d_demo_sandbox');

  /// The world as it was left, or a new one: before the device opens, so
  /// the window comes up on the right world.
  late final SandboxRun _run = SandboxRun.open(_storage, backend: usePhysics());

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.55, 0.72, 0.9, 1.0),
  );

  final InputState _input = InputState();
  late final DesktopInput _keys = DesktopInput(
    state: _input,
    bindings: sandboxBindings(),
    slotKeys: sandboxSlotKeys(),
  );
  final FocusNode _keyboard = FocusNode();

  /// Saves when the window is hidden or goes, whatever is waiting.
  late final AppLifecycleListener _lifecycle;

  final FrameClock _frames = FrameClock();
  Ticker? _ticker;

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
      final scene = Scene()
        ..ambientIntensity = 0.35
        ..ambientColor = Vector3(0.75, 0.85, 1.0)
        ..add(
          LightNode(name: 'sun', intensity: 2.6)
            ..setLocalForward(Vector3(-0.45, -1.0, -0.3)),
        )
        ..add(_camera);
      final meshes = ChunkMeshes(device, scene, _run.blocks);
      if (!mounted) return;
      setState(
        () => _playing = (
          renderer: Renderer.create(device: device),
          scene: scene,
          meshes: meshes,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onTick(Duration _) {
    final dt = _frames.tick();
    final playing = _playing;
    if (playing == null) return;
    _input.beginStep();
    _run.step(dt, _input);
    _input.endStep();
    final stale = _run.takeStaleSurfaces();
    if (stale.isNotEmpty) playing.meshes.refresh(stale);
    if (_run.unsaved) {
      _sinceEdit += dt;
      if (_sinceEdit > 3.0) _save();
    }
    if (mounted) setState(() {});
  }

  void _save() {
    _sinceEdit = 0.0;
    if (_run.unsaved) _run.save(_storage);
  }

  void _onPointerUp(PointerUpEvent event) {
    final down = _down;
    _down = null;
    if (down == null || _dragged > 6.0) return;
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
      onKeyEvent: (FocusNode node, KeyEvent event) =>
          _keys.handleKeyEvent(event),
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          _keyboard.requestFocus();
          _down = (at: event.localPosition, buttons: event.buttons);
          _dragged = 0.0;
        },
        onPointerMove: (PointerMoveEvent event) {
          if (_down == null) return;
          _dragged += event.delta.distance;
          _input.addLook(event.delta.dx, event.delta.dy);
        },
        onPointerUp: _onPointerUp,
        onPointerSignal: (PointerSignalEvent event) {
          if (event is! PointerScrollEvent) return;
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
              settings: () => const RenderSettings(),
              onBeforeFrame: () => _run.walk.placeCamera(_camera),
              presentFrame: presentFrame,
            ),
            const IgnorePointer(child: Center(child: _Crosshair())),
            Positioned(
              left: 16,
              top: 16,
              child: SafeArea(child: _Status(run: _run)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(child: _Hotbar(selected: _run.slot)),
            ),
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
  const _Status({required this.run});

  final SandboxRun run;

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
          const SizedBox(height: 6),
          const Text(
            'WASD walk · space jumps · drag to look · click digs · '
            'right click places · 1–5 picks',
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
    decoration: BoxDecoration(
      color: Color.from(
        alpha: 1,
        red: kind.colour.x,
        green: kind.colour.y,
        blue: kind.colour.z,
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
