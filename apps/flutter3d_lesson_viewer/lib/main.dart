/// A read-only player for an `edu-00` lesson document.
///
///     flutter run -d macos
///     flutter run -d chrome --dart-define=level=assets/levels/tour.json
///
/// **Not a copy of `flutter3d_game`'s example.** That seed puts a walking body
/// in a level; this puts a camera that only ever stands where an `edu_step`
/// says to, moved by two buttons rather than by WASD. There is no
/// `CollisionWorld` here at all — nothing in this screen ever collides with
/// anything, so building one would be state nothing reads.
///
/// `edu-02`'s own honest-scope line: this plays a step's `at`/`yaw` and its
/// `visible`/`hidden` lists (through `flutter3d_stereo`'s
/// `applyLessonStepTo`, the one lesson player for a flat screen and a
/// holder) and renders `widget_surface` annotations through the same
/// pipeline the dungeon's terminal (`wg-02`) already proved. It does not
/// draw an `edu_clip_plane` and does not read `bindings`/`edu_data_source`:
/// each is a separate, later step.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_education/lesson.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart' show LessonPlayer;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src/lesson_loading_screen.dart';
import 'src/lesson_theme.dart';
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
/// `flutter3d_game`'s own `OpenKind` for why every type in the document is
/// accepted and none of them given a meaning here. A copy rather than an
/// import, because this viewer stands on `flutter3d_app` and not on the game
/// layer.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

/// `tour.json`'s own `view-caption` `widget_surface` — authored alongside the
/// level's steps, never resolved by any registry until now: `_open` (below)
/// called `LessonCubit.open` with no `widgetRegistry` at all, so the panel
/// only ever reported "this application's widget registry does not have"
/// `viewer-caption` and drew nothing. A static caption rather than one that
/// tracks the current step live: the panel sits behind the pedestal, in view
/// through most of the tour, and `ls-e-04`'s own "danger" panel — a step-local
/// warning, not a running caption — is the row a *reactive* widget_surface
/// belongs to, once one is written.
Widget _viewerCaption(BuildContext context) => const ColoredBox(
  color: LessonTheme.scrim,
  child: Center(
    child: Padding(
      padding: EdgeInsets.all(16.0),
      child: Text(
        'Обойти изделие',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: LessonTheme.text,
          fontSize: 20.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  ),
);

/// Every widget a `widget_surface` entity in this application's own levels
/// may name.
///
/// **The student's reduced-motion flag, carried in.** A surface is built in
/// a pipeline of its own, under a `MediaQuery` that knows the texture's size
/// and nothing of the system's settings, so a widget hosted there would
/// animate whatever the student asked for. With [reduceMotion], each one
/// reads `MediaQuery.disableAnimationsOf` as the screen around it does.
Map<String, WidgetBuilder> widgetRegistry({
  ValueListenable<bool>? reduceMotion,
}) {
  WidgetBuilder carried(WidgetBuilder build) => reduceMotion == null
      ? build
      : (BuildContext context) => ValueListenableBuilder<bool>(
          valueListenable: reduceMotion,
          builder: (BuildContext context, bool reduce, Widget? child) =>
              MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduce),
                child: child!,
              ),
          child: Builder(builder: build),
        );
  return <String, WidgetBuilder>{'viewer-caption': carried(_viewerCaption)};
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
    final source = materialName == null ? null : level.materials[materialName];
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
  /// `applyLessonStepTo`.
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

      // `ls-e-00`'s own nodes map: every fixture the level placed, by the
      // name its own entity carries — `applyLessonStepTo`'s own doc
      // comment names this split (the engine says what a step means, an
      // application says which node that name resolves to). Built *after*
      // `widgetSurfaces` rather than before: a `widget_surface`'s own
      // `MeshNode` (`ls-e-04`'s own "danger" panel, or any annotation a step
      // wants to show only while it is current) is added to the scene by
      // that loop, and a snapshot taken before it ran would leave a step's
      // `visible`/`hidden` list naming that panel a silent no-op — `nodes[
      // name]?.visible = visible` finding no entry rather than the surface
      // it meant.
      final nodes = <String, SceneNode>{
        for (final mesh in loaded.scene.meshes) ?mesh.name: mesh,
      };

      // The screen went while the level was loading: nobody will show these
      // surfaces, and a closed cubit cannot be handed them.
      if (isClosed) {
        widgetSurfaces.dispose();
        return;
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
      if (!isClosed) emit(LessonFailed(error));
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
  GraphicsDevice? _device;
  Renderer? _renderer;
  Object? _initError;

  final CameraNode _camera = CameraNode(name: 'eye');
  final LessonCubit _lesson = LessonCubit();

  Ticker? _ticker;

  /// The system's reduced-motion flag, handed to the widgets the lesson's
  /// surfaces host ([widgetRegistry]), which cannot read it themselves.
  final ValueNotifier<bool> _reduceMotion = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion.value = MediaQuery.disableAnimationsOf(context);
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
      device = await openDevice(width: 1280, height: 720);
      if (!mounted) {
        device.dispose();
        return;
      }
      setState(() {
        _device = device;
        _renderer = Renderer.create(device: device);
      });
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    await _lesson.open(
      device,
      camera: _camera,
      widgetRegistry: widgetRegistry(reduceMotion: _reduceMotion),
    );
    // Gone while the lesson loaded: a ticker cannot be made for a disposed
    // state.
    if (!mounted) return;
    // `widgetSurfaces.tickAll()` redraws whichever `widget_surface` this
    // lesson named, only on the frames its own pipeline marks dirty
    // (`wg-00`'s own rule) — driven by a ticker rather than only by the step
    // buttons, the same "reasserted every frame" choice
    // `packages/flutter3d_game/example`'s own tick loop already makes.
    _ticker = createTicker((_) {
      final state = _lesson.state;
      if (state is LessonReady) unawaited(state.widgetSurfaces?.tickAll());
    })..start();
  }

  /// The device and the renderer are this screen's: `SceneSurface` only
  /// borrows them, so they are given back here — after `close`, which
  /// disposes the lesson's widget surfaces before it awaits anything, since
  /// those surfaces release their meshes and textures to this same device.
  @override
  void dispose() {
    _ticker?.dispose();
    unawaited(_lesson.close());
    _renderer?.dispose();
    _device?.dispose();
    _reduceMotion.dispose();
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
    background: LessonTheme.background,
    foreground: LessonTheme.error,
  );

  Widget _loading() => const LessonLoadingScreen();
}
