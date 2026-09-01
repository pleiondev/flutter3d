/// A level editor: open a document, move what is in it, write it back.
///
///     cd apps/flutter3d_editor
///     flutter run -d macos --dart-define=level=../flutter3d_demo_dungeon/assets/levels/crypt.json
///
/// **Desktop only, and that is not an omission.** This application exists to
/// write a file back over itself, which a browser will not do — so unlike the
/// three games there is no web build and no backend to choose between.
///
/// What is here is the shell: a window, a camera, a mouse and a keyboard. The
/// parts that can lose somebody's work are in `src/editing.dart`, which needs
/// no window and is tested without one. Which screen to show, and what the
/// strip along the bottom says, are in `src/editor_cubit.dart` — see its own
/// doc comment for why that is a `Cubit` and this is not.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_screens/native.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/documents.dart';
import 'src/editing.dart';
import 'src/editor_bar.dart';
import 'src/editor_chooser.dart';
import 'src/editor_cubit.dart';
import 'src/editor_inspector.dart';
import 'src/editor_legend.dart';
import 'src/editor_palette.dart';
import 'src/fly_camera.dart';
import 'src/gizmos.dart';
import 'src/looks.dart';
import 'src/palette_items.dart';
import 'src/picking.dart';
import 'src/scaffold.dart';
import 'src/scene_dressing.dart';
import 'src/vocabulary.dart';

/// The document opened on launch.
///
/// A define rather than a file dialogue, for now: the whole repository's levels
/// are a relative path away, and a picker is a platform channel's worth of work
/// that adds nothing to the part that is hard.
const String kLevelPath = String.fromEnvironment(
  'level',
  defaultValue: '../flutter3d_demo_dungeon/assets/levels/crypt.json',
);

/// What this editor calls itself when it takes ownership of a document.
const String kAuthor = 'apps/flutter3d_editor';

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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  /// Which document is open, why one is not, and what to say about the last
  /// thing that happened. See `EditorCubit`'s own doc comment for what stays
  /// out of it: the camera, the scene, and everything below that is read every
  /// frame rather than rebuilt on.
  final EditorCubit _cubit = EditorCubit();

  GraphicsDevice? _device;
  Renderer? _renderer;
  Scene? _scene;

  final CameraNode _camera = CameraNode(name: 'editor');
  final FlyCamera _fly = FlyCamera();

  final InputState _input = InputState();
  late final DesktopInput _keys = DesktopInput(
    state: _input,
    bindings: _bindings(),
  );
  final FocusNode _keyboard = FocusNode();

  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.06, 0.07, 0.09, 1.0),
  );

  /// Draws the selection box, the gizmos and their models. Opened once a
  /// device exists; everything it owns is the render loop's, not a screen
  /// rebuild's — see its own doc comment.
  SceneDressing? _dressing;

  Ticker? _ticker;

  /// How long since the last frame, and how long since the first.
  final FrameClock _frames = FrameClock();

  /// Whether the document has changed since the scene was built from it.
  bool _stale = false;
  bool _rebuilding = false;

  /// The editor's own light, which the level does not contain.
  ///
  /// **A level you cannot see is a level you cannot edit.** The crypt is lit by
  /// six torches and is otherwise pitch black, which is right for a game and
  /// useless here: half the rooms are a black rectangle with a mark floating in
  /// it, and every question about what you are looking at starts with "is that
  /// broken or is it just dark". So the editor carries a lamp — a point light
  /// held where the camera stands — and says so, rather than quietly changing
  /// the level's own lighting.
  ///
  /// A point light with a range rather than a directional one, and the first
  /// version of this got it wrong: a [LightNode] is directional unless told
  /// otherwise, so the "lamp" was a sun along world −Z that never moved with
  /// the camera. Every surface facing the camera's home orientation — the
  /// crypt's iron door, squarely — caught it head on, blew past white and
  /// bloomed, and was reported as a light in a doorway where the level has
  /// none. A light carried at the eye falls off with distance instead, so the
  /// room somebody is in is lit and the far end of the level is the level's
  /// own business.
  ///
  /// Off with **B**, for anybody who wants to see the room the way a player
  /// will.
  LightNode? _lamp;

  /// Bright enough to read a room by, dimmer than the crypt's own torches
  /// (6.5 over 13 m), so the lamp shows the level without outshining it.
  static const double _kLampIntensity = 3.0;
  static const double _kLampRange = 12.0;

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

  /// The document [_cubit] is open on, or null while there is none.
  Editing? get _editing => _ready?.editing;

  /// The cubit's state, narrowed to the one screen that has a document —
  /// null in every other state, which every reader here already treats
  /// [_editing] being null as standing for.
  EditorReady? get _ready {
    final state = _cubit.state;
    return state is EditorReady ? state : null;
  }

  Future<void> _open() async {
    try {
      final device = await GpuRenderBackend.create();
      if (!mounted) return;
      _device = device;
      _renderer = Renderer.create(device: device);
      _dressing = SceneDressing(device);

      // Where the document actually is — see `Documents`, and the launch that
      // found nothing because a bundle's working directory is `/`.
      final tried = Documents.searchFrom();
      final found = Documents.find(
        kLevelPath,
        from: tried,
        exists: (String path) => File(path).existsSync(),
      );
      if (found == null) {
        final templates = await _readTemplates();
        if (templates.isEmpty) {
          throw FileSystemException(
            Documents.couldNotFind(
              kLevelPath,
              Documents.candidates(kLevelPath, from: tried),
            ),
          );
        }
        if (!mounted) return;
        _cubit.nothingFound(templates, path: kLevelPath);
        return;
      }
      await _openAt(found);
    } catch (error) {
      if (mounted) _cubit.failed(error);
    }
  }

  /// Opens the document at [found], which is known to be there.
  Future<void> _openAt(String found) async {
    try {
      final editing = Editing.parse(
        await File(found).readAsString(),
        path: found,
      );
      // Where this document's own `assets/…` live. A game never has to work
      // this out; an editor always does, because the level it has open belongs
      // to another application.
      final assetRoot = Documents.assetRootFor(
        found,
        hasAssets: (String path) => Directory(path).existsSync(),
      );
      final looks = await _readLooks(assetRoot);
      _standWhereThePlayerWould(editing.level);
      if (!mounted) return;
      _cubit.opened(editing, assetRoot: assetRoot, looks: looks);
      await _build();
    } catch (error) {
      if (mounted) _cubit.failed(error);
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
    final dressing = _dressing;
    final ready = _ready;
    if (device == null || dressing == null || ready == null) return;
    final editing = ready.editing;
    _rebuilding = true;
    try {
      final loaded = await LevelLoader().build(
        editing.level,
        device: device,
        registry: vocabularyOf(editing.level),
        readAsset: _readAsset,
      );
      if (!mounted) return;
      _scene = loaded.scene..add(_camera);
      _lamp = LightNode(
        type: LightType.point,
        color: Vector3(1.0, 0.98, 0.94),
        intensity: ready.lampOn ? _kLampIntensity : 0.0,
        range: _kLampRange,
      )..setPosition(_fly.position.x, _fly.position.y, _fly.position.z);
      loaded.scene.add(_lamp!);
      if (kLevelOnly) {
        for (final light in List<LightNode>.of(loaded.scene.lights)) {
          loaded.scene.remove(light);
        }
      }
      dressing.textures = loaded.materialTextures;
      dressing.reset();
      dressing.placeGizmos(
        loaded.scene,
        editing,
        looks: ready.looks,
        hidden: ready.hidden,
      );
      dressing.placeMarker(loaded.scene, editing);
      unawaited(
        dressing
            .dressGizmos(
              loaded.scene,
              editing,
              looks: ready.looks,
              hidden: ready.hidden,
              assetRoot: ready.assetRoot,
              stillCurrent: () => mounted && identical(loaded.scene, _scene),
            )
            .then((_) {
              if (mounted) setState(() {});
            }),
      );
    } finally {
      _rebuilding = false;
    }
  }

  /// Every template this editor ships, out of its own bundle.
  ///
  /// A bundle cannot be listed, so what exists is written down: one index of
  /// the templates, one manifest each of their files.
  static Future<List<Template>> _readTemplates() async {
    try {
      final index =
          jsonDecode(await rootBundle.loadString('assets/templates/index.json'))
              as Map<String, Object?>;
      final names = (index['templates'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>();
      return <Template>[
        for (final name in names)
          Template.parse(
            name,
            await rootBundle.loadString('assets/templates/$name/index.json'),
          ),
      ];
    } catch (error) {
      debugPrint('editor: could not read the templates ($error)');
      return const <Template>[];
    }
  }

  /// Writes a new project and opens the level in it.
  Future<void> _create(Template template) async {
    final where = projectAt(
      File(kLevelPath).isAbsolute
          ? kLevelPath
          : '${Directory.current.path}/$kLevelPath',
    );
    try {
      final directory = Directory(where.root);
      if (directory.existsSync() && directory.listSync().isNotEmpty) {
        _cubit.choosingSaid('${where.root} is not empty');
        return;
      }

      final project = scaffold(
        template: template,
        project: where.root.split('/').last,
        sources: <String, Uint8List>{
          for (final name in template.files.keys)
            name: (await rootBundle.load(
              'assets/templates/${template.id}/$name',
            )).buffer.asUint8List(),
        },
      );

      for (final entry in project.entries) {
        final file = File('${where.root}/${entry.key}');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(entry.value);
      }

      if (!mounted) return;
      // Straight into the new project's level: the "made N files" moment
      // is never on screen for it to be told apart from "opened N brushes" —
      // the picture is still a spinner until `_build` finishes either way.
      await _openAt(where.level);
    } catch (error) {
      if (mounted) _cubit.choosingSaid('could not create it: $error');
    }
  }

  /// Reads the game's own `editor.json`, if it keeps one.
  ///
  /// Never throws: a game that has not written one is the ordinary case, and a
  /// game whose file will not parse should lose its marks rather than its
  /// editor.
  static Future<Looks> _readLooks(String? root) async {
    if (root == null) return Looks.none;
    final file = File('$root/$kLooksFile');
    try {
      if (!file.existsSync()) return Looks.none;
      return Looks.parse(await file.readAsString());
    } catch (error) {
      debugPrint('editor: could not read $kLooksFile ($error)');
      return Looks.none;
    }
  }

  /// Reads one of the edited application's own files.
  ///
  /// Off the disk rather than out of a bundle, because the bundle belongs to
  /// this editor and the file belongs to the game.
  Future<ByteData> _readAsset(String path) async {
    final root = _ready?.assetRoot;
    if (root == null) throw StateError('no application around $path');
    return ByteData.sublistView(await File('$root/$path').readAsBytes());
  }

  /// Puts the marker where the selection now is, or takes it away. A thin
  /// wrapper over [SceneDressing.placeMarker] that supplies the scene and the
  /// document, which is what most call sites already have to hand and none of
  /// them want to null-check twice.
  void _placeMarker() {
    final dressing = _dressing;
    final scene = _scene;
    final editing = _editing;
    if (dressing == null || scene == null || editing == null) return;
    dressing.placeMarker(scene, editing);
  }

  void _changed(String said) {
    _stale = true;
    _cubit.say(said);
  }

  void _onTick(Duration _) {
    // The ticker's argument is the frame's scheduled time, not the present;
    // `FrameClock` says why the wall is measured instead.
    final dt = _frames.tick();

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
      unawaited(
        _build().then((_) {
          if (mounted) setState(() {});
        }),
      );
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
    final placing = _ready?.placing;
    if (placing == null) {
      _pick(event.localPosition, size);
      return;
    }
    _put(placing, event.localPosition, size);
  }

  /// The wheel flies, because a trackpad has one and a corridor is long.
  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _fly.position.addScaled(_fly.forward, -event.scrollDelta.dy * 0.05);
  }

  /// Which way a click at [at] points, in the world.
  Vector3 _rayThrough(Offset at, Size size) {
    final projection = _camera.projection;
    return Picking.through(
      Vector2(at.dx, at.dy),
      size: Vector2(size.width, size.height),
      forward: _fly.forward,
      right: _fly.right,
      up: _fly.up,
      fovY: projection is PerspectiveProjection
          ? projection.fovYRadians
          : math.pi / 4,
    );
  }

  /// Puts one of whatever the palette is holding where the click landed.
  ///
  /// **On the surface that was clicked, not in the air in front of the
  /// camera.** A monster belongs on a floor and a torch on a wall, and asking
  /// somebody to place a thing in mid-air and then nudge it down to the ground
  /// is asking them to do the arithmetic a ray already did. Half a metre back
  /// along the ray, so the new thing stands on the surface rather than inside
  /// it.
  ///
  /// A click at the sky — or at nothing, in a level with a hole in it — puts it
  /// six metres ahead, which is far enough to see and near enough to walk to.
  void _put(Placeable what, Offset at, Size size) {
    final editing = _editing;
    final looks = _ready?.looks ?? Looks.none;
    if (editing == null) return;
    final along = _rayThrough(at, size);
    final hit = Picking.at(
      handlesOf(editing.level, looks: looks),
      _fly.position,
      along,
    );
    final distance = hit == null
        ? 6.0
        : math.max(
            0.5,
            (Picking.hit(hit.min, hit.max, _fly.position, along) ?? 6.0) - 0.5,
          );

    editing.place(what, _fly.position + along * distance);
    _placeMarker();
    _changed('placed ${editing.says}');
  }

  /// Selects whatever is under [at].
  void _pick(Offset at, Size size) {
    final editing = _editing;
    final looks = _ready?.looks ?? Looks.none;
    if (editing == null) return;
    final along = _rayThrough(at, size);
    final found = Picking.at(
      handlesOf(editing.level, looks: looks),
      _fly.position,
      along,
    );
    editing.selectHandle(found);
    _placeMarker();
    _cubit.say(found == null ? 'nothing there' : editing.says);
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
      // Shift-command-Z goes the other way, which is what every editor on this
      // platform does and what this one could not do at all.
      if (pressed.isShiftPressed) {
        editing.redo();
        _placeMarker();
        _changed(editing.canRedo ? 'redone' : 'redone — back to the front');
      } else {
        editing.undo();
        _placeMarker();
        _changed(editing.canUndo ? 'undone' : 'undone — back to the start');
      }
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

    // Escape puts the palette down, and then gives up the selection. Two
    // meanings for one key in the order somebody wants them: the thing you
    // most want to undo is the one you did last.
    if (key == LogicalKeyboardKey.escape) {
      if (_ready?.placing != null) {
        _cubit.setPlacing(null);
      } else {
        editing.select(null, null);
        _placeMarker();
        _cubit.say('nothing selected');
      }
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
      case LogicalKeyboardKey.keyB:
        final on = _cubit.toggleLamp();
        // The node stays in the scene either way; a lamp at nought is a lamp
        // off, and there is no add/remove pair to get out of step with _build.
        _lamp?.intensity = on ? _kLampIntensity : 0.0;
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        // Four metres in front, which is far enough to light a room and near
        // enough to be the room somebody is standing in.
        editing.addLight(_fly.position + _fly.ground * 4.0);
        _placeMarker();
        _changed('added ${editing.says}');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit1:
        _cubit.setAxis(EditorAxis.x);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit2:
        _cubit.setAxis(EditorAxis.y);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit3:
        _cubit.setAxis(EditorAxis.z);
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
        editing.grid = switch (editing.grid) {
          0.25 => 1.0,
          1.0 => 0.0,
          _ => 0.25,
        };
        _cubit.say(
          editing.grid == 0.0 ? 'off the grid' : 'grid ${editing.grid}m',
        );
        return KeyEventResult.handled;
      default:
        return _keys.handleKeyEvent(event);
    }

    _placeMarker();
    // Named rather than silent: a key that appears to do nothing is a key
    // somebody decides is broken, and the commonest reason one does nothing
    // here is that it is asking about a brush nobody has picked yet.
    final at = editing.where;
    _changed(
      at == null
          ? 'nothing selected — click something first'
          : 'at ${_metres(at)}',
    );
    return KeyEventResult.handled;
  }

  Vector3 _along(double amount) => switch (_ready?.axis ?? EditorAxis.x) {
    EditorAxis.x => Vector3(amount, 0.0, 0.0),
    EditorAxis.y => Vector3(0.0, amount, 0.0),
    EditorAxis.z => Vector3(0.0, 0.0, amount),
  };

  static String _metres(Vector3 v) =>
      '${v.x.toStringAsFixed(2)}, '
      '${v.y.toStringAsFixed(2)}, ${v.z.toStringAsFixed(2)}';

  /// Writes the document back, or says why it will not.
  Future<void> _save({bool copy = false}) async {
    final editing = _editing;
    if (editing == null) return;

    if (!copy && !editing.mayOverwrite) {
      _cubit.say(
        'written by ${editing.generatedBy} — '
        'shift-save writes a copy instead',
      );
      return;
    }

    final path = copy ? await _freePathBeside(editing.path) : editing.path;
    try {
      // **Atomically, which it was not.** This wrote a person's hand-built
      // level with a bare `writeAsString` while settings and saves — documents
      // a game can afford to lose — have gone through a temporary and a rename
      // since they were written. A crash or a full disk halfway through left a
      // truncated level where the good one had been, so one lost session
      // became every future one.
      await writeFileAtomically(
        path,
        // A copy of a generated document takes ownership of itself. One that
        // still named the generator would invite somebody to run it again, and
        // running it again is exactly what throws the work away.
        editing.write(claiming: copy ? kAuthor : null),
      );
      editing.saved();
      _cubit.say('written to $path');
    } catch (error) {
      _cubit.say('could not write $path: $error');
    }
  }

  /// A name beside [path] that nothing is using yet.
  ///
  /// **It used to be one name.** Shift-save always wrote `foo.edited.json`, so
  /// a second shift-save overwrote the first copy without asking — and the
  /// whole reason shift-save exists is that the original is generated and must
  /// not be touched, which makes the copy the only version of that work there
  /// is.
  static Future<String> _freePathBeside(String path) async {
    final stem = path.endsWith('.json')
        ? path.substring(0, path.length - 5)
        : path;
    final suffix = path.endsWith('.json') ? '.json' : '';
    var candidate = '$stem.edited$suffix';
    // Two hundred is a number nobody reaches and a loop that always ends.
    for (var n = 2; n < 200; n++) {
      if (!File(candidate).existsSync()) return candidate;
      candidate = '$stem.edited.$n$suffix';
    }
    return candidate;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
    unawaited(_keys.dispose());
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // **Closing threw the work away without a word.** The editor has tracked
    // `isDirty` and rendered "— unsaved" in its bar since it was written, and
    // then let the window go on the first ask. Nothing in this repository used
    // `PopScope` at all, and this is the one screen that holds a document
    // nothing can regenerate.
    canPop: !(_editing?.isDirty ?? false),
    onPopInvokedWithResult: (bool didPop, Object? _) {
      if (didPop) return;
      unawaited(_askBeforeLeaving());
    },
    child: BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<EditorCubit, EditorState>(
        bloc: _cubit,
        builder: (BuildContext context, EditorState state) => switch (state) {
          EditorFailed(:final error) => DidNotStart(
            error,
            // The editor's own colours: a tool sits beside other tools,
            // and black with grey text is a game's screen rather than an
            // application's.
            background: const Color(0xFF14161A),
            foreground: const Color(0xFFFF8A80),
          ),
          EditorChoosing() => EditorChooser(
            state: state,
            levelPath: kLevelPath,
            onCreate: _create,
          ),
          EditorOpening() => const _Loading(),
          EditorReady() => _editorScreen(state),
        },
      ),
    ),
  );

  /// Asks what to do about unsaved work, and does it.
  ///
  /// Three answers rather than two, because "save" is the one a person
  /// actually wants and a dialog offering only "lose it" or "stay" makes them
  /// do the saving themselves and then close again.
  Future<void> _askBeforeLeaving() async {
    final editing = _editing;
    if (editing == null || !mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('This level has unsaved changes'),
        content: Text(editing.path),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Close without saving'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save and close'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'save') {
      await _save();
      // Only if it actually landed: a save that could not write is not a
      // reason to close, and the bar has already said why.
      if (!mounted || editing.isDirty) return;
    }
    Navigator.of(context).maybePop();
  }

  /// The document is open: the scene, and the three panels around it.
  Widget _editorScreen(EditorReady state) {
    final renderer = _renderer;
    final scene = _scene;
    if (renderer == null || scene == null) return const _Loading();

    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final size = constraints.biggest;

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // **Only the picture listens.** The panels used to sit inside
                // this listener, so a click on a palette row was also a click
                // into the level behind it — picking whatever happened to be
                // under the panel, or placing a second one of whatever the row
                // had just picked up. A scroll over the list flew the camera at
                // the same time as scrolling.
                Listener(
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: (PointerUpEvent event) =>
                      _pointerUp(event, size),
                  onPointerSignal: _pointerSignal,
                  child: SceneSurface(
                    renderer: renderer,
                    scene: scene,
                    view: _view,
                    settings: () => RenderSettings(
                      // The engine has had an outline pass since before there
                      // was anything to outline — its own doc says "typically
                      // whatever picking last selected" — and this is the first
                      // caller it has ever had.
                      highlighted: <SceneNode>[?_dressing?.marker],
                      // **No shadows, and not for speed.** With them on this
                      // editor flickers: the picture alternates between the
                      // scene and a nearly black one, on a camera nobody is
                      // touching.
                      //
                      // Two separate faults were behind that, and only one of
                      // them is fixed. The first was the finished frame being
                      // drawn into while the compositor still had it — see
                      // `Renderer`'s finished-frame textures, which now come
                      // back when the backend says the GPU is done rather than
                      // after a guessed number of frames. Switching shadows
                      // back on after that fix brought the flicker straight
                      // back, so the second one is real and is somewhere in the
                      // shadow path.
                      //
                      // What is known about it, so the next person starts here
                      // rather than where this started:
                      //
                      //  * It needs the hardware backend. The same scene
                      //    rendered ten times through `CpuDevice`, shadows and
                      //    all, is byte for byte the same picture.
                      //  * It needs a still camera, which is why no game shows
                      //    it: a frame that differs from its neighbour by a
                      //    millimetre of camera hides anything.
                      //  * The tile scheduler is not redrawing anything —
                      //    instrumented, zero tiles scheduled per frame in the
                      //    steady state — so whatever changes is not the atlas
                      //    being refreshed with different content.
                      //  * Both atlases are `devicePrivate` and stored, so it
                      //    is not tile memory losing its contents.
                      //
                      // An editor loses nothing by it. What it is for is where
                      // things *are*: a shadow under a crate says nothing a
                      // wireframe does not, and the crypt's own torches light
                      // the rooms either way.
                      shadows: const ShadowSettings(enabled: false),
                    ),
                    onBeforeFrame: () {
                      _fly.placeOn(_camera);
                      // The lamp travels with the eye rather than hanging where
                      // the last rebuild happened to leave it.
                      _lamp?.setPosition(
                        _fly.position.x,
                        _fly.position.y,
                        _fly.position.z,
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: EditorBar(state: state),
                ),
                // Below the bar and above the legend, so nothing it covers is
                // anything the other two are saying.
                Positioned(
                  left: 0,
                  top: 64,
                  bottom: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: EditorPalette(state: state),
                  ),
                ),
                // The right-hand side, opposite the palette: what a level can
                // be made of on the left, what the selected piece *is* on the
                // right. Nothing when nothing is selected, so the picture is
                // not narrowed by a panel with nothing in it.
                Positioned(
                  right: 0,
                  top: 64,
                  bottom: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: EditorInspector(
                      state: state,
                      onChanged: (String what) =>
                          _changed('$what — ${state.editing.says}'),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EditorLegend(state: state),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Shown while the device is opening and while a document is being read —
/// nothing has gone wrong, there is simply nothing to draw yet.
final class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF14161A),
    body: Center(child: CircularProgressIndicator()),
  );
}
