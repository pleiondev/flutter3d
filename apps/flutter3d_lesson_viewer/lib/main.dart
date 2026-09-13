/// A read-only player for an `edu-00` lesson document.
///
///     flutter run -d macos
///     flutter run -d chrome --dart-define=level=assets/levels/tour.json
///
/// **Not a copy of `flutter3d_template_app`.** That seed puts a walking body
/// in a level; this puts a camera that only ever stands where an `edu_step`
/// says to, moved by two buttons rather than by WASD. There is no
/// `CollisionWorld` here at all — nothing in this screen ever collides with
/// anything, so building one would be state nothing reads.
///
/// `edu-02`'s own honest-scope line: this plays a step's `at`/`yaw` and its
/// `visible`/`hidden` lists (through `flutter3d_bridge`'s
/// `applyLessonStepToCamera`) and renders `widget_surface` annotations
/// through the same pipeline `flutter3d_template_app` already proved. It
/// does not apply `offsets`, does not draw an `edu_clip_plane`, does not read
/// `bindings`/`edu_data_source`, and does not ask a `check` question — see
/// `packages/flutter3d_bridge/lib/src/lesson_player.dart`'s own doc comment
/// for why each is a separate, later step.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'src/backend.dart';
import 'src/lesson_view.dart';

/// The lesson this build opens, as a bundled asset path.
///
/// Overridable two ways: `--dart-define=level=` for a local run, and
/// `?level=` in the page's own URL for a build served from the cloud
/// (`edu-02`'s own service picks a lesson this way, the same query-param
/// door `flutter3d_modeler` opens for `?model=`). Unlike that door, this one
/// needs no same-origin check: `rootBundle.loadString` only ever reads a
/// path bundled into this build, never a URL, so a `?level=` naming
/// something outside `assets/levels/` fails to load rather than fetching
/// anything.
const String kLevel = String.fromEnvironment(
  'level',
  defaultValue: 'assets/levels/tour.json',
);

void main() => runApp(const LessonViewerApp());

class LessonViewerApp extends StatelessWidget {
  const LessonViewerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A lesson',
    debugShowCheckedModeBanner: false,
    home: const LessonScreen(),
  );
}

/// A kind for a type this application has not been taught — see
/// `flutter3d_template_app`'s own `OpenKind` for why every type in the
/// document is accepted and none of them given a meaning here.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

/// [level]'s own `part` entities — `ls-e-00`'s removable pieces — as plain
/// boxed [MeshNode]s, named after their own entity so an `edu_step`'s
/// `visible`/`hidden` list has something to reach.
///
/// **Not [SpawnContext]/[FixtureVisuals].** That machinery is a game's own —
/// it wants a [CollisionWorld], an [ActorSystem], a [MechanismWorld] and a
/// [FixtureAppearance] this read-only viewer has none of (see this file's
/// own top doc comment: no `CollisionWorld` at all). A part is scenery with
/// a name, which is exactly what `LevelLoader.materialFrom` and a
/// [SharedMeshes] box already build for a brush — called directly here
/// rather than through the door built for a genre's own doors and lifts.
void _addParts(Level level, LoadedLevel loaded, GraphicsDevice device) {
  final meshes = SharedMeshes(device);
  for (final entity in level.entities) {
    if (entity.type != 'part') continue;
    final name = entity.name;
    if (name == null) continue;
    final materialName = entity.string('material');
    final source = materialName == null
        ? null
        : level.materials[materialName];
    final material = LevelLoader.materialFrom(
      source ?? LevelMaterial(),
      const <String, TextureHandle?>{},
      name: materialName,
    );
    final size = entity.vector('size') ?? Vector3.all(1.0);
    final node = MeshNode(meshes.box(size), material, name: name)
      ..setPositionFrom(entity.position);
    loaded.scene.add(node);
  }
}

sealed class LessonState {
  const LessonState();
}

final class LessonLoading extends LessonState {
  const LessonLoading();
}

final class LessonReady extends LessonState {
  const LessonReady(
    this.scene,
    this.camera,
    this.player, {
    this.widgetSurfaces,
    this.nodes = const <String, SceneNode>{},
  });

  final Scene scene;
  final CameraNode camera;
  final LessonPlayer player;
  final WidgetSurfaceVisuals? widgetSurfaces;

  /// Every fixture the level placed, by the name its own entity carries —
  /// what a step's `visible`/`hidden` list reaches through
  /// `applyLessonStepToCamera`.
  final Map<String, SceneNode> nodes;
}

final class LessonFailed extends LessonState {
  const LessonFailed(this.error);

  final Object error;
}

/// Reads [kLevel] (or [asset], for a test) and builds a [LessonPlayer] for
/// its first `edu_sequence` — an empty one when the document names none, the
/// same "no lesson, no steps" answer `orderedSteps` already gives rather
/// than a thrown error, since a level with no sequence is a level this
/// screen can still show, just with nothing for its buttons to do.
class LessonCubit extends Cubit<LessonState> {
  LessonCubit() : super(const LessonLoading());

  Future<void> open(
    GraphicsDevice device, {
    required CameraNode camera,
    String asset = kLevel,
    Map<String, WidgetBuilder> widgetRegistry = const <String, WidgetBuilder>{},
  }) async {
    try {
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
      _addParts(level, loaded, device);

      // `ls-e-00`'s own nodes map: every fixture the level placed, by the
      // name its own entity carries — `applyLessonStepToCamera`'s own doc
      // comment names this split (the engine says what a step means, an
      // application says which node that name resolves to), and nothing in
      // this repository had actually built the map yet before this row.
      final nodes = <String, SceneNode>{
        for (final mesh in loaded.scene.meshes) ?mesh.name: mesh,
      };

      String? sequenceName;
      for (final entity in level.entities) {
        if (entity.type == 'edu_sequence') {
          sequenceName = entity.name;
          break;
        }
      }
      final steps = sequenceName == null
          ? const <EntityDef>[]
          : orderedSteps(level, sequenceName);

      final widgetSurfaces = WidgetSurfaceVisuals(
        loaded.scene,
        device: device,
        registry: widgetRegistry,
      );
      for (final entity in level.entities) {
        widgetSurfaces.add(entity);
      }

      emit(
        LessonReady(
          loaded.scene..add(camera),
          camera,
          LessonPlayer(steps),
          widgetSurfaces: widgetSurfaces,
          nodes: nodes,
        ),
      );
    } catch (error) {
      emit(LessonFailed(error));
    }
  }

  @override
  Future<void> close() {
    final current = state;
    if (current is LessonReady) current.widgetSurfaces?.dispose();
    return super.close();
  }
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen>
    with SingleTickerProviderStateMixin {
  Renderer? _renderer;
  Object? _initError;

  final CameraNode _camera = CameraNode(name: 'eye');
  final LessonCubit _lesson = LessonCubit();

  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
      device = await openDevice(width: 1280, height: 720);
      if (!mounted) return;
      setState(() => _renderer = Renderer.create(device: device));
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    await _lesson.open(device, camera: _camera);
    // `widgetSurfaces.tickAll()` redraws whichever `widget_surface` this
    // lesson named, only on the frames its own pipeline marks dirty
    // (`wg-00`'s own rule) — driven by a ticker rather than only by the step
    // buttons, the same "reasserted every frame" choice
    // `flutter3d_template_app`'s own tick loop already makes.
    _ticker = createTicker((_) {
      final state = _lesson.state;
      if (state is LessonReady) unawaited(state.widgetSurfaces?.tickAll());
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    unawaited(_lesson.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) return _didNotStart(initError);

    final renderer = _renderer;
    if (renderer == null) return _loading();

    return BlocBuilder<LessonCubit, LessonState>(
      bloc: _lesson,
      builder: (BuildContext context, LessonState state) => switch (state) {
        LessonFailed(:final error) => _didNotStart(error),
        LessonLoading() => _loading(),
        LessonReady(:final scene, :final camera, :final player, :final nodes) =>
          LessonView(
            renderer: renderer,
            scene: scene,
            camera: camera,
            player: player,
            nodes: nodes,
          ),
      },
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
}
