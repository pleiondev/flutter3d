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
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart' hide LessonPlayer;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart' show DidNotStart;
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
/// `flutter3d_template_app`'s own `OpenKind` for why every type in the
/// document is accepted and none of them given a meaning here.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

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
  const LessonReady(this.scene, this.rig, this.player, {this.nodes = const <String, SceneNode>{}});

  final Scene scene;
  final StereoRig rig;
  final LessonPlayer player;

  /// Every fixture the level placed, by the name its own entity carries —
  /// what a step's `visible`/`hidden` list reaches through
  /// `applyLessonStep`.
  final Map<String, SceneNode> nodes;
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

      emit(LessonReady(loaded.scene, rig, LessonPlayer(steps), nodes: nodes));
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
        LessonReady(:final scene, :final rig, :final player, :final nodes) =>
          LessonStereoView(
            renderer: renderer,
            scene: scene,
            rig: rig,
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
