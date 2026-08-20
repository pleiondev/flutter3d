/// A level editor: open a document, move what is in it, write it back.
///
///     cd apps/editor
///     flutter run -d macos --dart-define=level=../dungeon/assets/levels/crypt.json
///
/// **Desktop only, and that is not an omission.** This application exists to
/// write a file back over itself, which a browser will not do — so unlike the
/// three games there is no web build and no backend to choose between.
///
/// What is here is the shell: a window, a camera, a mouse and a keyboard. The
/// parts that can lose somebody's work are in `src/editing.dart`, which needs
/// no window and is tested without one.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/editing.dart';
import 'src/fly_camera.dart';
import 'src/picking.dart';
import 'src/vocabulary.dart';

/// The document opened on launch.
///
/// A define rather than a file dialogue, for now: the whole repository's levels
/// are a relative path away, and a picker is a platform channel's worth of work
/// that adds nothing to the part that is hard.
const String kLevelPath = String.fromEnvironment(
  'level',
  defaultValue: '../dungeon/assets/levels/crypt.json',
);

/// What this editor calls itself when it takes ownership of a document.
const String kAuthor = 'apps/editor';

void main() => runApp(const EditorApp());

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'flutter3d level editor',
        debugShowCheckedModeBanner: false,
        home: const EditorScreen(),
      );
}

/// The actions the camera is flown with.
///
/// Bound rather than read off the keys directly, because held movement is what
/// `InputState` is for — and because an editor is a thing people rebind.
abstract final class _Fly {
  static const GameAction forward = GameAction('flyForward');
  static const GameAction back = GameAction('flyBack');
  static const GameAction left = GameAction('flyLeft');
  static const GameAction right = GameAction('flyRight');
  static const GameAction down = GameAction('flyDown');
  static const GameAction up = GameAction('flyUp');
  static const GameAction fast = GameAction('flyFast');
}

/// Which axis the size keys work on.
enum _Axis { x, y, z }

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  GraphicsDevice? _device;
  Renderer? _renderer;
  Scene? _scene;
  Object? _error;

  Editing? _editing;

  final CameraNode _camera = CameraNode(name: 'editor');
  final FlyCamera _fly = FlyCamera();

  final InputState _input = InputState();
  late final DesktopInput _keys =
      DesktopInput(state: _input, bindings: _bindings());
  final FocusNode _keyboard = FocusNode();

  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.06, 0.07, 0.09, 1.0),
  );

  /// The box drawn around whatever is selected.
  ///
  /// A node of its own rather than a highlight on the level's geometry, because
  /// the level is not made of one node per brush: `BrushGeometry` batches every
  /// brush of a material into a single mesh, which is what makes a level cheap
  /// to draw and impossible to point at. This is the one thing in the scene
  /// that is not the document.
  SceneNode? _marker;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// Whether the document has changed since the scene was built from it.
  bool _stale = false;
  bool _rebuilding = false;

  _Axis _axis = _Axis.x;

  /// The last thing that happened, for the strip along the bottom.
  String _said = 'W A S D fly · right-drag looks · click selects';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    unawaited(_open());
  }

  static Bindings _bindings() {
    final bindings = Bindings(<InputSource, GameAction>{});
    void bind(LogicalKeyboardKey key, GameAction action) =>
        bindings.bind(InputSource.key(key.keyId), action);

    bind(LogicalKeyboardKey.keyW, _Fly.forward);
    bind(LogicalKeyboardKey.keyS, _Fly.back);
    bind(LogicalKeyboardKey.keyA, _Fly.left);
    bind(LogicalKeyboardKey.keyD, _Fly.right);
    bind(LogicalKeyboardKey.keyQ, _Fly.down);
    bind(LogicalKeyboardKey.keyE, _Fly.up);
    bind(LogicalKeyboardKey.shiftLeft, _Fly.fast);
    bind(LogicalKeyboardKey.shiftRight, _Fly.fast);
    return bindings;
  }

  Future<void> _open() async {
    try {
      final device = await GpuRenderBackend.create();
      if (!mounted) return;
      _device = device;
      _renderer = Renderer.create(
        device: device,
        fallbackAlbedo: SolidColorTexture.white.upload(device),
        fallbackNormal: SolidColorTexture.flatNormal.upload(device),
      );

      final file = File(kLevelPath);
      final editing = Editing.parse(
        await file.readAsString(),
        path: file.absolute.path,
      );
      _editing = editing;
      await _build();
      if (!mounted) return;
      setState(() {
        _said = 'opened ${editing.level.brushes.length} brushes'
            '${editing.mayOverwrite ? '' : ' — written by ${editing.generatedBy}'}';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Draws the document again, from the document.
  ///
  /// **The whole level, every time.** A change to one brush changes the mesh
  /// its whole material is batched into, so there is nothing smaller to
  /// rebuild — and an editor that tried to patch a batch would be an editor
  /// whose picture and document disagree, which is the one thing it must never
  /// be. Scheduled at most once a frame by [_onTick] instead, so holding an
  /// arrow key down does not queue fifty of them.
  Future<void> _build() async {
    final device = _device;
    final editing = _editing;
    if (device == null || editing == null) return;
    _rebuilding = true;
    try {
      final loaded = await LevelLoader().build(
        editing.level,
        device: device,
        registry: vocabularyOf(editing.level),
      );
      if (!mounted) return;
      _scene = loaded.scene..add(_camera);
      _marker = null;
      _placeMarker();
    } finally {
      _rebuilding = false;
    }
  }

  /// Puts the selection box around whatever is selected, or takes it away.
  void _placeMarker() {
    final device = _device;
    final scene = _scene;
    final brush = _editing?.brush;
    if (device == null || scene == null) return;

    if (brush == null) {
      final marker = _marker;
      if (marker != null) scene.remove(marker);
      _marker = null;
      return;
    }

    final marker = _marker;
    if (marker != null) scene.remove(marker);
    // A little larger than the brush, or the two surfaces fight for the same
    // depth and the box appears in stripes.
    final node = MeshNode(
      SharedMeshes(device).box(brush.size * 1.02),
      engine.Material(
        name: 'selection',
        baseColor: Vector4(1.0, 0.55, 0.1, 1.0),
        emissive: Vector3(0.9, 0.4, 0.05),
      ),
      name: 'selection',
    )
      ..setPosition(brush.centre.x, brush.centre.y, brush.centre.z)
      ..castsShadow = false;
    scene.add(node);
    _marker = node;
  }

  void _changed(String said) {
    _stale = true;
    setState(() => _said = said);
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;

    _fly.step(
      dt.clamp(0.0, 0.1),
      _input,
      forward: _Fly.forward,
      back: _Fly.back,
      left: _Fly.left,
      right: _Fly.right,
      down: _Fly.down,
      up: _Fly.up,
      fast: _Fly.fast,
    );

    if (_stale && !_rebuilding) {
      _stale = false;
      unawaited(_build().then((_) {
        if (mounted) setState(() {});
      }));
    }

    if (mounted) setState(() {});
  }

  // --- what the mouse does ---------------------------------------------------

  Offset? _dragged;

  void _pointerDown(PointerDownEvent event, Size size) {
    _keyboard.requestFocus();
    if (event.buttons & kSecondaryButton != 0) {
      _dragged = event.localPosition;
      return;
    }
    if (event.buttons & kPrimaryButton == 0) return;
    _pick(event.localPosition, size);
  }

  void _pointerMove(PointerMoveEvent event) {
    final from = _dragged;
    if (from == null || event.buttons & kSecondaryButton == 0) return;
    _fly.look(Vector2(
      event.localPosition.dx - from.dx,
      event.localPosition.dy - from.dy,
    ));
    _dragged = event.localPosition;
  }

  /// Selects whatever is under [at].
  void _pick(Offset at, Size size) {
    final editing = _editing;
    if (editing == null) return;
    final projection = _camera.projection;
    final along = Picking.through(
      Vector2(at.dx, at.dy),
      size: Vector2(size.width, size.height),
      forward: _fly.forward,
      right: _fly.right,
      up: _fly.up,
      fovY: projection is PerspectiveProjection
          ? projection.fovYRadians
          : math.pi / 4,
    );
    final found = Picking.brushAt(editing.level.brushes, _fly.position, along);
    editing.select(found);
    _placeMarker();
    setState(() {
      _said = found == null
          ? 'nothing there'
          : 'brush $found, ${editing.brush!.material}';
    });
  }

  // --- what the keys do ------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return _keys.handleKeyEvent(event);
    final editing = _editing;
    if (editing == null) return _keys.handleKeyEvent(event);

    final pressed = HardwareKeyboard.instance;
    final command = pressed.isMetaPressed || pressed.isControlPressed;
    final key = event.logicalKey;

    if (command && key == LogicalKeyboardKey.keyZ) {
      editing.undo();
      _placeMarker();
      _changed(editing.canUndo ? 'undone' : 'undone — back to the start');
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyD) {
      editing.duplicate();
      _changed('duplicated as brush ${editing.selected}');
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyS) {
      unawaited(_save(copy: pressed.isShiftPressed));
      return KeyEventResult.handled;
    }

    final step = editing.grid;
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
        editing.nudge(Vector3(-step, 0.0, 0.0));
      case LogicalKeyboardKey.arrowRight:
        editing.nudge(Vector3(step, 0.0, 0.0));
      case LogicalKeyboardKey.arrowUp:
        editing.nudge(Vector3(0.0, 0.0, -step));
      case LogicalKeyboardKey.arrowDown:
        editing.nudge(Vector3(0.0, 0.0, step));
      case LogicalKeyboardKey.pageUp:
        editing.nudge(Vector3(0.0, step, 0.0));
      case LogicalKeyboardKey.pageDown:
        editing.nudge(Vector3(0.0, -step, 0.0));
      case LogicalKeyboardKey.minus:
        editing.grow(_along(-step));
      case LogicalKeyboardKey.equal:
        editing.grow(_along(step));
      case LogicalKeyboardKey.digit1:
        setState(() => _axis = _Axis.x);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit2:
        setState(() => _axis = _Axis.y);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit3:
        setState(() => _axis = _Axis.z);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyN:
        // Six metres in front, which is far enough to be looked at and near
        // enough to be flown to.
        editing.add(_fly.position + _fly.forward * 6.0);
        _placeMarker();
        _changed('added brush ${editing.selected}');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        editing.remove();
        _placeMarker();
        _changed('deleted');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG:
        setState(() {
          editing.grid = switch (editing.grid) {
            0.25 => 1.0,
            1.0 => 0.0,
            _ => 0.25,
          };
          _said = editing.grid == 0.0
              ? 'off the grid'
              : 'grid ${editing.grid}m';
        });
        return KeyEventResult.handled;
      default:
        return _keys.handleKeyEvent(event);
    }

    _placeMarker();
    _changed(_describe(editing));
    return KeyEventResult.handled;
  }

  Vector3 _along(double amount) => switch (_axis) {
        _Axis.x => Vector3(amount, 0.0, 0.0),
        _Axis.y => Vector3(0.0, amount, 0.0),
        _Axis.z => Vector3(0.0, 0.0, amount),
      };

  String _describe(Editing editing) {
    final brush = editing.brush;
    if (brush == null) return 'nothing selected';
    return 'at ${_metres(brush.centre)} · ${_metres(brush.size)}';
  }

  static String _metres(Vector3 v) => '${v.x.toStringAsFixed(2)}, '
      '${v.y.toStringAsFixed(2)}, ${v.z.toStringAsFixed(2)}';

  /// Writes the document back, or says why it will not.
  Future<void> _save({bool copy = false}) async {
    final editing = _editing;
    if (editing == null) return;

    if (!copy && !editing.mayOverwrite) {
      setState(() => _said = 'written by ${editing.generatedBy} — '
          'shift-save writes a copy instead');
      return;
    }

    final path = copy ? _besidePath(editing.path) : editing.path;
    try {
      await File(path).writeAsString(
        // A copy of a generated document takes ownership of itself. One that
        // still named the generator would invite somebody to run it again, and
        // running it again is exactly what throws the work away.
        editing.write(claiming: copy ? kAuthor : null),
      );
      editing.saved();
      setState(() => _said = 'written to $path');
    } catch (error) {
      setState(() => _said = 'could not write $path: $error');
    }
  }

  static String _besidePath(String path) =>
      path.endsWith('.json') ? '${path.substring(0, path.length - 5)}.edited.json' : '$path.edited';

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF14161A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$error',
                style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        ),
      );
    }

    final renderer = _renderer;
    final scene = _scene;
    if (renderer == null || scene == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF14161A),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final size = constraints.biggest;
            return Listener(
              onPointerDown: (PointerDownEvent event) =>
                  _pointerDown(event, size),
              onPointerMove: _pointerMove,
              onPointerUp: (_) => _dragged = null,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  SceneSurface(
                    renderer: renderer,
                    scene: scene,
                    view: _view,
                    settings: () => RenderSettings(
                      // The engine has had an outline pass since before there
                      // was anything to outline — its own doc says "typically
                      // whatever picking last selected" — and this is the first
                      // caller it has ever had.
                      highlighted: <SceneNode>[?_marker],
                    ),
                    onBeforeFrame: () => _fly.placeOn(_camera),
                  ),
                  Positioned(left: 0, right: 0, top: 0, child: _bar()),
                  Positioned(left: 0, right: 0, bottom: 0, child: _legend()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bar() {
    final editing = _editing;
    return Container(
      color: const Color(0xCC0E1013),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE6EAF0), fontSize: 13),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${editing?.path ?? ''}${editing?.isDirty ?? false ? ' •' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(_said, style: const TextStyle(color: Color(0xFFFFB74D))),
          ],
        ),
      ),
    );
  }

  Widget _legend() => Container(
        color: const Color(0xCC0E1013),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          'arrows move · page up/down raises · 1 2 3 pick an axis (${_axis.name}) '
          '· − = resize · N new · ⌘D duplicate · ⌫ delete · G grid · ⌘Z undo '
          '· ⌘S save · ⇧⌘S save a copy',
          style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
        ),
      );
}
