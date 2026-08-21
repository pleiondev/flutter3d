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
import 'dart:convert';
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
import 'src/looks.dart';
import 'src/picking.dart';
import 'src/scaffold.dart';
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

  /// The directory this document's `assets/…` paths are relative to, if it has
  /// one. Null for a level with no application around it, which draws in the
  /// flat colours its materials name and is a perfectly good way to edit.
  String? _assetRoot;

  /// What this game says its own words look like, if it says anything.
  Looks _looks = Looks.none;

  /// The templates on offer, while there is nothing open.
  ///
  /// **A path that does not exist is a request to make one.** The editor used
  /// to say "no level document at …" and list where it had looked, which is the
  /// right answer for a typo and the wrong one for somebody starting a game.
  List<Template>? _choosing;

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
  /// How long since the last frame, and how long since the first.
  final FrameClock _frames = FrameClock();

  /// Whether the document has changed since the scene was built from it.
  bool _stale = false;
  bool _rebuilding = false;

  _Axis _axis = _Axis.x;

  /// What the next click in the scene puts down, or null to select instead.
  ///
  /// The row itself rather than its name: a row carries which of the three
  /// lists it adds to, and a name alone cannot — a material called `light`
  /// would be a level that could never place a lamp again.
  ///
  /// **A palette rather than a key per kind**, which is what this was first.
  /// Two keys for the two things an engine defines is a rule that stops at
  /// two: a game with lifts, doors and six kinds of monster cannot have a key
  /// each, and a key that only somebody who has read the source knows about is
  /// not a way to place anything. The palette is built from the document, so it
  /// lists exactly what this level is made of.
  Placeable? _placing;

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
      _renderer = Renderer.create(device: device);

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
          throw FileSystemException(Documents.couldNotFind(
            kLevelPath,
            Documents.candidates(kLevelPath, from: tried),
          ));
        }
        if (!mounted) return;
        setState(() {
          _choosing = templates;
          _said = 'nothing at $kLevelPath yet';
        });
        return;
      }
      await _openAt(found);
      return;
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Opens the document at [found], which is known to be there.
  Future<void> _openAt(String found) async {
    try {
      final editing = Editing.parse(await File(found).readAsString(),
          path: found);
      // Where this document's own `assets/…` live. A game never has to work
      // this out; an editor always does, because the level it has open belongs
      // to another application.
      _assetRoot = Documents.assetRootFor(
        found,
        hasAssets: (String path) => Directory(path).existsSync(),
      );
      _looks = await _readLooks(_assetRoot);
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
        readAsset: _readAsset,
      );
      if (!mounted) return;
      _scene = loaded.scene..add(_camera);
      _textures = loaded.materialTextures;
      _marker = null;
      _gizmos.clear();
      _placeGizmos();
      _placeMarker();
      unawaited(_dressGizmos());
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
      final index = jsonDecode(
        await rootBundle.loadString('assets/templates/index.json'),
      ) as Map<String, Object?>;
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
        setState(() => _said = '${where.root} is not empty');
        return;
      }

      final project = scaffold(
        template: template,
        project: where.root.split('/').last,
        sources: <String, Uint8List>{
          for (final name in template.files.keys)
            name: (await rootBundle.load('assets/templates/${template.id}/$name'))
                .buffer
                .asUint8List(),
        },
        packagesAt: _packagesAt() ?? '../../packages',
      );

      for (final entry in project.entries) {
        final file = File('${where.root}/${entry.key}');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(entry.value);
      }

      if (!mounted) return;
      setState(() {
        _choosing = null;
        _said = 'made ${project.length} files in ${where.root}';
      });
      await _openAt(where.level);
    } catch (error) {
      if (mounted) setState(() => _said = 'could not create it: $error');
    }
  }

  /// Where this checkout keeps its packages, for a new project to point at.
  ///
  /// The same climb `Documents` does, looking for the one directory a project's
  /// path dependencies have to name. Null when the editor is running somewhere
  /// that is not a checkout, and then the project says so in its own pubspec
  /// rather than pretending.
  static String? _packagesAt() {
    for (final directory in Documents.searchFrom()) {
      if (Directory('$directory/packages/flutter3d').existsSync()) {
        return '$directory/packages';
      }
    }
    return null;
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
    final root = _assetRoot;
    if (root == null) throw StateError('no application around $path');
    return ByteData.sublistView(await File('$root/$path').readAsBytes());
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

    for (final handle in handlesOf(editing.level, looks: _looks)) {
      if (handle.kind == Piece.brush) continue;
      final entity =
          handle.kind == Piece.entity ? editing.level.entities[handle.index] : null;

      // **Drawn as what it is, when the document says what it is.** A door
      // names a material the level already loaded, and a lift names the size it
      // moves at — so the editor can show the iron door as an iron door rather
      // than as a coloured box where an iron door goes. What has neither gets
      // the mark, which is the only thing a coordinate and a word can be shown
      // as.
      final named = entity?.string('material');
      final isLight = handle.kind == Piece.light;
      final material = named == null
          ? null
          : editing.level.materials[named];

      // A silhouette the game described: a torch's plate, shaft, cup and
      // flame, built out of the engine's own primitives. Drawn instead of the
      // mark, not beside it.
      final parts = entity == null
          ? const <Part>[]
          : _looks.partsFor(entity);
      if (parts.isNotEmpty) {
        _buildParts(device, scene, parts, handle, entity!);
        continue;
      }

      final node = MeshNode(
        // **A light is a ball, everything else is a box**, because a lamp drawn
        // as a cube beside a torch drawn as a cube is two cubes, and the
        // question somebody asks at that point is which of them is which.
        isLight
            ? SharedMeshes(device).shape(
                'gizmo-light',
                () => SphereShape(radius: kGizmoSize * 0.45),
              )
            : SharedMeshes(device).box(handle.size),
        material == null
            ? engine.Material(
                name: 'gizmo',
                baseColor: Vector4(
                  handle.tint.x,
                  handle.tint.y,
                  handle.tint.z,
                  1.0,
                ),
                // Lit by itself, or a mark in an unlit corner is a mark nobody
                // can find — and an unlit corner is where somebody is most
                // likely to be looking for the light they meant to put there.
                emissive: handle.tint * 0.9,
              )
            : LevelLoader.materialFrom(material, _textures, name: named),
        name: 'gizmo',
      )
        ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
        ..castsShadow = false;
      if (entity != null && entity.yaw != 0.0) {
        node.setRotation(
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw),
        );
      }
      scene.add(node);
      _gizmos.add(node);
    }
  }

  /// Puts one described silhouette into the scene.
  ///
  /// Under a holder at the entity's place, turned by its yaw, so a part's
  /// position is written the way the game writes it: local +Z into the wall.
  void _buildParts(
    GraphicsDevice device,
    Scene scene,
    List<Part> parts,
    Handle handle,
    EntityDef entity,
  ) {
    final holder = SceneNode(name: 'gizmo')
      ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw));
    scene.add(holder);
    _gizmos.add(holder);

    final meshes = SharedMeshes(device);
    for (final part in parts) {
      final node = MeshNode(
        _meshFor(meshes, part),
        engine.Material(
          name: part.glows ? 'flame' : 'part',
          baseColor: Vector4(
            part.colour.x,
            part.colour.y,
            part.colour.z,
            1.0,
          ),
          // A flame is the light rather than the thing holding it, and a dark
          // corridor would otherwise swallow the one part that is the point.
          emissive: part.glows ? part.colour * 1.4 : null,
        ),
        name: part.shape,
      )..setPosition(part.at.x, part.at.y, part.at.z);
      if (part.pitch != 0.0) {
        node.setRotation(
          Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), part.pitch),
        );
      }
      node.castsShadow = false;
      holder.add(node);
    }
  }

  static DeviceMesh _meshFor(SharedMeshes meshes, Part part) => switch (part.shape) {
        'cylinder' => meshes.shape(
            'part-cyl-${part.radius}-${part.height}',
            () => CylinderShape(
              radiusTop: part.radius,
              radiusBottom: part.radius,
              height: part.height,
            ),
          ),
        'cone' => meshes.shape(
            'part-cone-${part.radius}-${part.height}',
            () => ConeShape(radius: part.radius, height: part.height),
          ),
        'sphere' => meshes.shape(
            'part-ball-${part.radius}',
            () => SphereShape(radius: part.radius),
          ),
        _ => meshes.box(part.size),
      };

  /// Replaces the marks of everything that names a model with the model.
  ///
  /// **After the boxes rather than instead of them**, and the reason is that a
  /// glTF takes long enough to read that a level would appear empty while it
  /// happened. The box goes down first, the model replaces it when it arrives,
  /// and a model that will not read leaves the box — which is exactly what
  /// somebody wants to see when a path in their document is wrong.
  Future<void> _dressGizmos() async {
    final device = _device;
    final editing = _editing;
    final root = _assetRoot;
    if (device == null || editing == null || root == null) return;

    final scene = _scene;
    for (final handle in handlesOf(editing.level, looks: _looks)) {
      if (handle.kind != Piece.entity) continue;
      final entity = editing.level.entities[handle.index];
      // What the entity says, else what the game says this type is.
      final path = _looks.modelFor(entity);
      if (path == null) continue;

      final asset = await _models.putIfAbsent(
        path,
        () => _loadModel(device, '$root/$path'),
      );
      // The level may have been rebuilt while this was reading — a keypress is
      // faster than a glTF — and putting a model into a scene nobody draws is
      // the platformer's own bug, written down in its `_dressRunner`.
      if (!mounted || asset == null || !identical(scene, _scene)) return;

      final instance = asset.instantiate(_scene!, name: 'model');
      instance.root
        ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
        ..setRotation(
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw),
        );
      _gizmos.add(instance.root);
      // The mark it stands in for. Found by where it is, because that is what
      // the two have in common and the list is short.
      for (final gizmo in _gizmos) {
        if (gizmo.name != 'gizmo') continue;
        final at = gizmo.localMatrix.getTranslation();
        if ((at - handle.centre).length2 < 1e-6) {
          gizmo.visible = false;
          break;
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<ModelAsset?> _loadModel(GraphicsDevice device, String path) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: FileAssetSource(path)),
      );
      return await ModelAsset.fromDocument(
        document,
        device: device,
        fallbackAlbedo: SolidColorTexture.white.upload(device),
        name: path,
      );
    } catch (error) {
      debugPrint('editor: could not read the model "$path" ($error)');
      return null;
    }
  }

  final List<SceneNode> _gizmos = <SceneNode>[];

  /// Every map the level named, already uploaded by the loader. What lets a
  /// door be drawn in the iron the document says it is made of.
  Map<String, TextureHandle?> _textures = const <String, TextureHandle?>{};

  /// Models named by entities, loaded once each.
  ///
  /// **Keyed by the path the document wrote**, so two hundred and sixty-one
  /// coins are one file read and one upload — the platformer's own level says
  /// `assets/models/coin.glb` two hundred and sixty-one times.
  final Map<String, Future<ModelAsset?>> _models =
      <String, Future<ModelAsset?>>{};

  void _changed(String said) {
    _stale = true;
    setState(() => _said = said);
  }

  void _onTick(Duration now) {
    final dt = _frames.secondsSince(now);

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
    final placing = _placing;
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
    if (editing == null) return;
    final along = _rayThrough(at, size);
    final hit = Picking.at(handlesOf(editing.level, looks: _looks), _fly.position, along);
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
    if (editing == null) return;
    final along = _rayThrough(at, size);
    final found = Picking.at(handlesOf(editing.level, looks: _looks), _fly.position, along);
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

    // Escape puts the palette down, and then gives up the selection. Two
    // meanings for one key in the order somebody wants them: the thing you
    // most want to undo is the one you did last.
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        if (_placing != null) {
          _placing = null;
          _said = 'nothing to place';
        } else {
          editing.select(null, null);
          _placeMarker();
          _said = 'nothing selected';
        }
      });
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

    final choosing = _choosing;
    if (choosing != null) return _chooser(choosing);

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
                      highlighted: <SceneNode>[?_marker],
                    ),
                    onBeforeFrame: () => _fly.placeOn(_camera),
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, child: _bar()),
                // Below the bar and above the legend, so nothing it covers is
                // anything the other two are saying.
                Positioned(
                  left: 0,
                  top: 64,
                  bottom: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _palette(),
                  ),
                ),
                Positioned(left: 0, right: 0, bottom: 0, child: _legend()),
              ],
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

  /// The screen for a level that does not exist yet.
  ///
  /// **A path that is not there is a request to make one**, and answering it
  /// with "no such file" and a list of the places looked is the right answer
  /// for a typo and the wrong one for somebody starting a game. Both, then: the
  /// templates, and underneath them the path that will be written.
  Widget _chooser(List<Template> templates) {
    final where = projectAt(
      File(kLevelPath).isAbsolute
          ? kLevelPath
          : '${Directory.current.path}/$kLevelPath',
    );
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Start a game',
                style: TextStyle(
                  color: Color(0xFFE6EAF0),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'There is nothing at ${where.level} yet. A template writes a '
                'project there: a vocabulary, a first level and a model for '
                'each kind of thing.',
                style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 13),
              ),
              const SizedBox(height: 18),
              for (final template in templates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => unawaited(_create(template)),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1F26),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            template.name,
                            style: const TextStyle(
                              color: Color(0xFFFFB74D),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            template.about,
                            style: const TextStyle(
                              color: Color(0xFFCBD3DD),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                _said,
                style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What can be put into this level, and what is holding.
  ///
  /// Down the left, always there, and built from the document — so it lists
  /// exactly what this level is made of and nothing a different game would
  /// have. The count beside each is worth its space: a level with no exit and a
  /// level with three are both worth noticing before playing it.
  Widget _palette() {
    final editing = _editing;
    if (editing == null) return const SizedBox.shrink();
    return Container(
      width: 168,
      color: const Color(0xCC0E1013),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              'PLACE',
              style: TextStyle(
                color: Color(0xFF6F7885),
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // **Scrolls, because a level decides how long this is.** The crypt
          // has nine kinds in it and the platformer's ascent has more than fit
          // on the screen — the first version of this was a plain column and
          // the second level anybody opened overflowed it by a hundred and
          // sixty-nine pixels, which in Flutter means the rows past the bottom
          // simply do not exist.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final it in paletteOf(editing.level, declared: _looks.types))
                    _PaletteRow(
                      it: it,
                      held: _placing?.what == it.what,
                      onTap: () => setState(() {
                        // Tapping what is already held puts it down, which is
                        // the only way out somebody will guess at before they
                        // find Escape.
                        _placing =
                            _placing?.what == it.what ? null : it;
                        _said = _placing == null
                            ? 'nothing to place'
                            : 'click in the level to place a ${it.label}';
                      }),
                    ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              'click a row, then click in the level · esc puts it down',
              style: TextStyle(color: Color(0xFF6F7885), fontSize: 10),
            ),
          ),
        ],
      ),
    );
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
              '· ⌘D copy · ⌫ delete '
              '· G grid ($_gridSaid) · ⌘Z undo · ⌘S save · ⇧⌘S save a copy',
              style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
            ),
          ],
        ),
      );
}

/// One row of the palette: a swatch, a word, and how many the level has.
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.it, required this.held, required this.onTap});

  final Placeable it;

  /// Whether this is what the next click will put down.
  final bool held;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: held ? const Color(0x33FFB74D) : null,
          child: Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    (it.tint.x * 255).round().clamp(0, 255),
                    (it.tint.y * 255).round().clamp(0, 255),
                    (it.tint.z * 255).round().clamp(0, 255),
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  it.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: held
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE6EAF0),
                    fontSize: 12,
                    fontWeight: held ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                '${it.count}',
                style: const TextStyle(color: Color(0xFF6F7885), fontSize: 11),
              ),
            ],
          ),
        ),
      );
}
