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

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
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
import 'src/documents.dart';
import 'src/editing.dart';
import 'src/fly_camera.dart';
import 'src/gizmos.dart';
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

      // Where the document actually is — see `Documents`, and the launch that
      // found nothing because a bundle's working directory is `/`.
      final tried = Documents.searchFrom();
      final found = Documents.find(
        kLevelPath,
        from: tried,
        exists: (String path) => File(path).existsSync(),
      );
      if (found == null) {
        throw FileSystemException(Documents.couldNotFind(
          kLevelPath,
          Documents.candidates(kLevelPath, from: tried),
        ));
      }
      final editing = Editing.parse(await File(found).readAsString(),
          path: found);
      _editing = editing;
      _standWhereThePlayerWould(editing.level);
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

  /// Puts the camera where somebody would be standing.
  ///
  /// **A level opened from above the ceiling is a level nobody can find their
  /// way around.** The camera used to start at four metres up looking down;
  /// four metres in a crypt is inside the ceiling, so the first thing anybody
  /// saw was the floor from inside the stonework.
  ///
  /// The spawn point if the document has one, because that is the one place in
  /// a level somebody has already decided is worth standing — and it is where
  /// whatever is being edited will be seen from. Otherwise the middle of what
  /// the brushes cover, backed off far enough to see some of it.
  void _standWhereThePlayerWould(Level level) {
    const eye = 1.7;
    for (final entity in level.entities) {
      if (!entity.type.contains('spawn')) continue;
      _fly.position.setValues(
        entity.position.x,
        entity.position.y + eye,
        entity.position.z,
      );
      _fly.yaw = 0.0;
      _fly.pitch = 0.0;
      return;
    }

    if (level.brushes.isEmpty) return;
    var minX = double.infinity, minZ = double.infinity, floor = double.infinity;
    var maxX = -double.infinity, maxZ = -double.infinity;
    for (final brush in level.brushes) {
      minX = math.min(minX, brush.min.x);
      maxX = math.max(maxX, brush.max.x);
      minZ = math.min(minZ, brush.min.z);
      maxZ = math.max(maxZ, brush.max.z);
      floor = math.min(floor, brush.max.y);
    }
    _fly.position.setValues(
      (minX + maxX) / 2,
      floor + eye,
      maxZ + math.max(maxX - minX, 8.0) * 0.25,
    );
    _fly.yaw = 0.0;
    _fly.pitch = 0.0;
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
      _gizmos.clear();
      _placeGizmos();
      _placeMarker();
    } finally {
      _rebuilding = false;
    }
  }

  /// Puts the selection box around whatever is selected, or takes it away.
  ///
  /// **Two marks, because one of them is useless half the time.** The engine
  /// draws twelve lines around anything handed to `RenderSettings.highlighted`,
  /// which is right for a brush somebody is standing inside — a wall, a floor,
  /// a ceiling, and that is most of a level. It is nearly invisible for a small
  /// brush across a dark room, which is the other half. So the node is also
  /// drawn, in a colour nothing in a crypt is and lit by itself so a dark
  /// corridor cannot swallow it.
  ///
  /// A hair larger than the thing, or the two surfaces fight for the same depth
  /// and the mark appears in stripes. Seen from inside it disappears — a box's
  /// inside faces are culled — and that is exactly when the twelve lines are
  /// the ones doing the work.
  void _placeMarker() {
    final device = _device;
    final scene = _scene;
    final editing = _editing;
    if (device == null || scene == null || editing == null) return;

    final marker = _marker;
    if (marker != null) scene.remove(marker);
    _marker = null;

    final at = editing.where;
    if (at == null) return;
    final size = editing.brush?.size ?? Vector3.all(kGizmoSize);

    final node = MeshNode(
      SharedMeshes(device).box(size * 1.06),
      engine.Material(
        name: 'selection',
        baseColor: Vector4(1.0, 0.45, 0.05, 1.0),
        emissive: Vector3(1.2, 0.5, 0.05),
      ),
      name: 'selection',
    )
      ..setPosition(at.x, at.y, at.z)
      ..castsShadow = false;
    scene.add(node);
    _marker = node;
  }

  /// Draws a mark for everything the renderer does not.
  ///
  /// **Half a level is invisible to a level editor, and it is the half that
  /// makes it a level.** Geometry draws itself; a monster, a lift, a door, a
  /// trigger and the point the player starts at are coordinates in a document,
  /// and a light is a coordinate that changes other things and shows nothing of
  /// itself. Before these marks the editor could open the crypt and show a
  /// corridor with nothing in it, which is exactly what the game shows before
  /// it spawns anything.
  ///
  /// Their colours come from the type's own name — see [tintFor] — because this
  /// application is not allowed to know what a `monster` is.
  void _placeGizmos() {
    final device = _device;
    final scene = _scene;
    final editing = _editing;
    if (device == null || scene == null || editing == null) return;

    for (final gizmo in _gizmos) {
      scene.remove(gizmo);
    }
    _gizmos.clear();

    for (final handle in handlesOf(editing.level)) {
      if (handle.kind == Piece.brush) continue;
      final node = MeshNode(
        SharedMeshes(device).box(handle.size),
        engine.Material(
          name: 'gizmo',
          baseColor: Vector4(
            handle.tint.x,
            handle.tint.y,
            handle.tint.z,
            1.0,
          ),
          // Lit by itself, or a mark in an unlit corner is a mark nobody can
          // find — and an unlit corner is where somebody is most likely to be
          // looking for the light they meant to put there.
          emissive: handle.tint * 0.9,
        ),
        name: 'gizmo',
      )
        ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
        ..castsShadow = false;
      scene.add(node);
      _gizmos.add(node);
    }
  }

  final List<SceneNode> _gizmos = <SceneNode>[];

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

  /// Where the pointer went down, and how far it has travelled since.
  ///
  /// **One button, and the difference between looking and selecting is the
  /// drag.** The first version put looking on the right button, which is a
  /// two-finger press-and-drag on a trackpad and was undiscoverable enough that
  /// the person it was built for could not get down the first corridor. A click
  /// that does not move is a click; a click that moves is a look. Nothing to
  /// hold, nothing to know.
  Offset? _dragged;
  double _travelled = 0.0;

  /// How far a pointer may move and still count as a click, in pixels.
  static const double _slop = 4.0;

  void _pointerDown(PointerDownEvent event) {
    _keyboard.requestFocus();
    _dragged = event.localPosition;
    _travelled = 0.0;
  }

  void _pointerMove(PointerMoveEvent event) {
    final from = _dragged;
    if (from == null) return;
    final by = event.localPosition - from;
    _travelled += by.distance;
    _dragged = event.localPosition;
    if (_travelled < _slop) return;
    _fly.look(Vector2(by.dx, by.dy));
  }

  void _pointerUp(PointerUpEvent event, Size size) {
    final from = _dragged;
    _dragged = null;
    if (from == null || _travelled >= _slop) return;
    _pick(event.localPosition, size);
  }

  /// The wheel flies, because a trackpad has one and a corridor is long.
  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _fly.position.addScaled(_fly.forward, -event.scrollDelta.dy * 0.05);
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
    final found = Picking.at(handlesOf(editing.level), _fly.position, along);
    editing.selectHandle(found);
    _placeMarker();
    setState(() => _said = found == null ? 'nothing there' : editing.says);
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
      // **R and F as well as the page keys**, because on the keyboard this is
      // being used on, Page Up is Fn and an arrow — a two-handed way to say
      // "up" while the other hand is on the mouse. The page keys stay: a
      // desktop keyboard has them, and taking a binding away from somebody who
      // has learnt it is worse than having two.
      case LogicalKeyboardKey.pageUp:
      case LogicalKeyboardKey.keyR:
        editing.nudge(Vector3(0.0, step, 0.0));
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.keyF:
        editing.nudge(Vector3(0.0, -step, 0.0));
      // **The same two keys, and what they mean depends on what is selected.**
      // A brush has a size; a light has a strength and no size at all. Giving
      // each its own pair would be two more keys to learn for one idea, which
      // is "more of this, less of this".
      case LogicalKeyboardKey.minus:
        editing.kind == Piece.light
            ? editing.brighten(0.8)
            : editing.grow(_along(-step));
      case LogicalKeyboardKey.equal:
        editing.kind == Piece.light
            ? editing.brighten(1.25)
            : editing.grow(_along(step));
      case LogicalKeyboardKey.comma:
        editing.turn(-math.pi / 8);
      case LogicalKeyboardKey.period:
        editing.turn(math.pi / 8);
      case LogicalKeyboardKey.keyL:
        // Four metres in front, which is far enough to light a room and near
        // enough to be the room somebody is standing in.
        editing.addLight(_fly.position + _fly.ground * 4.0);
        _placeMarker();
        _changed('added ${editing.says}');
        return KeyEventResult.handled;
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
    // Named rather than silent: a key that appears to do nothing is a key
    // somebody decides is broken, and the commonest reason one does nothing
    // here is that it is asking about a brush nobody has picked yet.
    final at = editing.where;
    _changed(at == null
        ? 'nothing selected — click something first'
        : 'at ${_metres(at)}');
    return KeyEventResult.handled;
  }

  Vector3 _along(double amount) => switch (_axis) {
        _Axis.x => Vector3(amount, 0.0, 0.0),
        _Axis.y => Vector3(0.0, amount, 0.0),
        _Axis.z => Vector3(0.0, 0.0, amount),
      };

  /// What is selected, for the strip that always says it.
  ///
  /// **Separate from the message**, because the two answer different questions
  /// and one used to overwrite the other: after pressing G the corner said "off
  /// the grid" and the fact that a brush was selected at all had scrolled away.
  String get _selection {
    final editing = _editing;
    if (editing == null) return '';
    final at = editing.where;
    if (at == null) return editing.says;
    return '${editing.says} · at ${_metres(at)}'
        '${editing.brush == null ? '' : ' · ${_metres(editing.brush!.size)}'}';
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
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: (PointerUpEvent event) => _pointerUp(event, size),
              onPointerSignal: _pointerSignal,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${editing?.path ?? ''}'
                    '${(editing?.isDirty ?? false) ? '  — unsaved' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _selection,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: editing?.piece == null
                          ? const Color(0xFF9AA4B2)
                          : const Color(0xFF7ED957),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(_said, style: const TextStyle(color: Color(0xFFFFB74D))),
          ],
        ),
      ),
    );
  }

  String get _gridSaid {
    final grid = _editing?.grid ?? 0.0;
    return grid == 0.0 ? 'off' : '$grid m';
  }

  Widget _legend() => Container(
        color: const Color(0xCC0E1013),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // **Getting about comes first and never leaves the screen.** It was
            // said once, in the message line, and the first thing anybody does
            // replaced it — so the one thing somebody needs before they can do
            // anything at all was the one thing they could not read.
            const Text(
              'W A S D fly · Q E down and up · shift faster · '
              'scroll forward · drag to look · click to select',
              style: TextStyle(color: Color(0xFFCBD3DD), fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              'arrows move · R F raise · 1 2 3 axis (${_axis.name}) '
              '· − = size or brightness · , . turn '
              '· N brush · L light · ⌘D copy (a monster too) · ⌫ delete '
              '· G grid ($_gridSaid) · ⌘Z undo · ⌘S save · ⇧⌘S save a copy',
              style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
            ),
          ],
        ),
      );
}
