/// `ls-x-00`: the same `edu-00` lesson `flutter3d_lesson_viewer` plays flat,
/// drawn as a stereo pair for a Cardboard viewer instead.
///
///     flutter run -d chrome --dart-define=level=assets/levels/teardown.json
///
/// **Not a copy of `flutter3d_lesson_viewer` by accident.** It is one on
/// purpose: `LevelCubit`/`OpenKind`/`_addParts` below are the same three
/// pieces that file already proved, with `CameraNode` swapped for
/// `StereoRig` and `LessonView` swapped for `LessonStereoView` — `edu-06`'s
/// own row names this as the whole of the difference between a flat screen
/// and a headset, and nothing here found a reason to disagree.
///
/// `edu-06`'s own honest-scope line, inherited from the flat viewer's:
/// this plays a step's `at`/`yaw` and its `visible`/`hidden` lists. It does
/// not apply `offsets`, does not draw an `edu_clip_plane`, does not read
/// `bindings`/`edu_data_source`, and does not ask a `check` question.
///
/// **`ls-x-01`'s own real prerequisite, proven here first: `WidgetSurface`
/// (`wg-01`) draws correctly in a stereo view.** `LessonStereoView` and
/// `StereoSurface` draw whatever `Scene` they are handed with no node-type
/// special-casing, so a `WidgetSurface` — a `MeshNode` with a texture a
/// Flutter widget paints — needed nothing new in the rendering path; the gap
/// was that nothing in this application ever resolved a `widget_surface`
/// entity into one, or called `WidgetSurface.tick()` so its texture ever
/// updated. Both are wired now, proven with a real one in `teardown.json`
/// (`title-card`, a static caption). **Left honestly undone**: `ls-x-01`'s
/// own configurator needs a tap on a `WidgetSurface` to actually change
/// anything, and no ray from a stereo view has ever been cast at one here —
/// `wg-00`'s own "ray → uvAt → dispatchAtUv → a tap" chain is proven flat,
/// not through a stereo camera pair, and that is separate work this file
/// does not attempt.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart' hide LessonPlayer;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_session/flutter3d_session.dart' show DidNotStart;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'src/backend.dart';

/// The lesson this build opens, as a bundled asset path — the same two
/// override doors `flutter3d_lesson_viewer`'s own `kLevel` gives.
const String kLevel = String.fromEnvironment(
  'level',
  defaultValue: 'assets/levels/teardown.json',
);

void main() => runApp(const StereoLessonApp());

class StereoLessonApp extends StatelessWidget {
  const StereoLessonApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A lesson, in stereo',
    debugShowCheckedModeBanner: false,
    home: const LessonScreen(),
  );
}

/// A kind for a type this application has not been taught — see
/// `packages/flutter3d_game/example`'s own `OpenKind` for why every type in the
/// document is accepted and none of them given a meaning here.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

/// `title-card`: a static caption, the one widget this application's own
/// registry offers — `WidgetSurfaceVisuals` reports an issue rather than
/// crashing for any `widget_surface` naming anything else, the same way an
/// unrecognised `part` material would.
Widget _titleCard(BuildContext context) => const ColoredBox(
  color: Color(0xFF0B0F0C),
  child: Center(
    child: Padding(
      padding: EdgeInsets.all(16.0),
      child: Text(
        'Разборка двигателя',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFFE8E6E1), fontSize: 22),
      ),
    ),
  ),
);

/// The one widget `widget_surface` entities in this application's own
/// levels may name.
Map<String, WidgetBuilder> widgetRegistry() => <String, WidgetBuilder>{
  'title-card': _titleCard,
};

/// [level]'s own `part` entities — `ls-e-00`'s removable pieces, the same
/// concept `flutter3d_lesson_viewer`'s own `_addParts` already proved — as
/// plain boxed [MeshNode]s, named after their own entity.
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
    this.rig,
    this.player, {
    this.nodes = const <String, SceneNode>{},
    required this.widgetSurfaces,
  });

  final Scene scene;
  final StereoRig rig;
  final LessonPlayer player;

  /// Every fixture the level placed, by the name its own entity carries —
  /// what a step's `visible`/`hidden` list reaches through
  /// `applyLessonStep`.
  final Map<String, SceneNode> nodes;

  /// Every `widget_surface` this level's own entities resolved —
  /// `LessonStereoView.onTick` calls `tickAll()` on it once a frame, the
  /// same way `flutter3d_demo_dungeon`'s own `run_cubit.dart` does for a
  /// flat screen.
  final WidgetSurfaceVisuals widgetSurfaces;
}

final class LessonFailed extends LessonState {
  const LessonFailed(this.error);

  final Object error;
}

/// Reads [kLevel] (or [asset], for a test) and builds a [LessonPlayer] for
/// its first `edu_sequence` — an empty one when the document names none.
class LessonCubit extends Cubit<LessonState> {
  LessonCubit() : super(const LessonLoading());

  Future<void> open(GraphicsDevice device, {String asset = kLevel}) async {
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

      final nodes = <String, SceneNode>{
        for (final mesh in loaded.scene.meshes) ?mesh.name: mesh,
      };

      // `wg-02`: every `widget_surface` entity, resolved against
      // `widgetRegistry` — see this library's own doc comment for what
      // proving this here closes towards `ls-x-01`.
      final widgets = WidgetSurfaceVisuals(
        loaded.scene,
        device: device,
        registry: widgetRegistry(),
      );
      for (final entity in level.entities) {
        widgets.add(entity);
      }

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

      final rig = StereoRig();
      loaded.scene.add(rig.stage);

      emit(
        LessonReady(
          loaded.scene,
          rig,
          LessonPlayer(steps),
          nodes: nodes,
          widgetSurfaces: widgets,
        ),
      );
    } catch (error) {
      emit(LessonFailed(error));
    }
  }
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  Renderer? _renderer;
  Object? _initError;

  final LessonCubit _lesson = LessonCubit();

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
    await _lesson.open(device);
  }

  @override
  void dispose() {
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
        LessonReady(
          :final scene,
          :final rig,
          :final player,
          :final nodes,
          :final widgetSurfaces,
        ) =>
          LessonStereoView(
            renderer: renderer,
            scene: scene,
            rig: rig,
            player: player,
            nodes: nodes,
            onTick: widgetSurfaces.tickAll,
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
