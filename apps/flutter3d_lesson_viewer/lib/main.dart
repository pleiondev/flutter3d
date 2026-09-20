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
/// `edu-02`'s own honest-scope line: this plays a step's `at`/`yaw`, its
/// `visible`/`hidden` lists and its `offsets` (through `flutter3d_bridge`'s
/// `applyLessonStepToCamera`), renders `widget_surface`/`edu_annotation`
/// through the same pipeline `flutter3d_template_app` already proved,
/// resolves `type: "prop"` and `type: "model"` entities into real nodes
/// (`PropVisuals`/`ModelVisuals`), asks a `check` question
/// (`src/check_prompt.dart`), and writes every `edu_data_source`/`bindings`
/// pair a step names onto a real node, every frame
/// (`applyLessonStepBindings`, `edu-05b`) — for `kind: "sampler"` only; a
/// `mqtt`/`websocket` source has no adapter in this generic player, so its
/// bindings resolve to nothing rather than to a value nobody can name
/// honestly here. It does not draw an `edu_clip_plane` — see
/// `packages/flutter3d_bridge/lib/src/lesson_player.dart`'s own doc comment
/// for why that one is a separate, later step.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart' as stereo;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
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

sealed class LessonState {
  const LessonState();
}

final class LessonLoading extends LessonState {
  const LessonLoading();
}

final class LessonReady extends LessonState {
  const LessonReady(
    this.scene, {
    this.camera,
    this.player,
    this.rig,
    this.stereoPlayer,
    this.widgetSurfaces,
    this.props,
    this.models,
    this.dataSources,
    this.nodes = const <String, SceneNode>{},
  }) : assert(
         (camera == null) != (rig == null),
         'exactly one of camera (flat) or rig (stereo) is built, never '
         'both or neither',
       );

  final Scene scene;

  /// The flat screen's own stage — null exactly when [rig] is not, `?stereo=1`
  /// having asked for `ls-x-00`/`ls-x-01`/`ls-x-03`'s own viewport instead.
  final CameraNode? camera;
  final LessonPlayer? player;

  /// `flutter3d_stereo`'s own stage — a different render primitive from
  /// [camera] (`flutter3d_bridge/lib/src/lesson_player.dart`'s own doc
  /// comment gives the reason `LessonPlayer` is duplicated rather than
  /// shared), not a second copy of the same one.
  final stereo.StereoRig? rig;
  final stereo.LessonPlayer? stereoPlayer;
  final WidgetSurfaceVisuals? widgetSurfaces;

  /// `edu-07a`'s named, individually addressable geometry — null exactly when
  /// the document names no `prop` entity, the same "nothing to build, so
  /// nothing built" contract [widgetSurfaces] already keeps for a document
  /// with no `widget_surface`.
  final PropVisuals? props;

  /// `edu-07b`'s real, decoded models — a document naming no `model` entity
  /// leaves this null, [props]'s own contract.
  final ModelVisuals? models;

  /// `edu-05b`'s registry, built from this document's own `edu_data_source`
  /// entities — null when the document names none, [props]'s own contract.
  final DataSourceRegistry? dataSources;

  /// [props] and [models], merged — kept here rather than recomputed by
  /// every caller, since both `LessonView`'s own `nodes`/`restPositions` and
  /// this screen's own per-frame `applyLessonStepBindings` need the same
  /// map.
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
    CameraNode? camera,
    bool asStereo = false,
    String asset = kLevel,
    Map<String, WidgetBuilder> widgetRegistry = const <String, WidgetBuilder>{},
    IssueSink? onIssue,
  }) async {
    assert(
      asStereo == (camera == null),
      'pass a camera for the flat screen, or asStereo: true for '
      '`ls-x-00`\'s own viewport — never both, never neither',
    );
    final reportIssue = onIssue ?? printIssue;
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

      // Props and models first, models awaited — an `edu_annotation`'s
      // `attachTo` may name either, read later in the document, so both are
      // built (and every model actually decoded, not merely started) before
      // a single `widget_surface`/`edu_annotation` is resolved against
      // either's nodes.
      final props = PropVisuals(loaded.scene, device: device, level: level);
      final models = ModelVisuals(loaded.scene, device: device);
      for (final entity in level.entities) {
        props.add(entity);
      }
      await Future.wait(<Future<void>>[
        for (final entity in level.entities) models.add(entity),
      ]);

      final nodes = <String, SceneNode>{...props.nodes, ...models.nodes};

      final widgetSurfaces = WidgetSurfaceVisuals(
        loaded.scene,
        device: device,
        registry: widgetRegistry,
      );
      for (final entity in level.entities) {
        widgetSurfaces.add(entity, nodes: nodes);
      }

      // `edu-05b`: a `kind: "sampler"` source is a synthetic demo/test
      // stream by its own definition (`doc/edu-00-interactive-format.md`
      // §9 — "синтетический источник для демо и тестов без реального
      // брокера"), so a generic viewer that knows nothing about what any
      // given source represents can still give it *a* honestly-labelled
      // synthetic waveform, the same shape (`{"value": <number>}`) the one
      // real document in this tree already binds against
      // (`apps/flutter3d_template_app/assets/levels/twin.json`). A
      // `mqtt`/`websocket` source has no adapter here at all — reported,
      // not silently starved.
      DataSourceRegistry? dataSources;
      final sourceEntities = level.entities.where(
        (e) => e.type == 'edu_data_source',
      );
      if (sourceEntities.isNotEmpty) {
        final built = <String, EduDataSource>{};
        for (final entity in sourceEntities) {
          final name = entity.name;
          if (name == null) continue;
          switch (entity.string('kind')) {
            case 'sampler':
              built[name] = SamplerDataSource(
                (step) => <String, Object?>{
                  'value': 50.0 + 10.0 * math.sin(step * 0.05),
                },
              );
            case final other:
              reportIssue(
                Issue(
                  'edu_data_source "$name" names kind "$other", which this '
                  'generic viewer has no adapter for — its bindings resolve '
                  'to nothing',
                ),
              );
          }
        }
        dataSources = DataSourceRegistry(built);
      }

      if (asStereo) {
        final rig = stereo.StereoRig();
        loaded.scene.add(rig.stage);
        emit(
          LessonReady(
            loaded.scene,
            rig: rig,
            stereoPlayer: stereo.LessonPlayer(steps),
            widgetSurfaces: widgetSurfaces,
            props: props,
            models: models,
            dataSources: dataSources,
            nodes: nodes,
          ),
        );
        return;
      }

      loaded.scene.add(camera!);
      emit(
        LessonReady(
          loaded.scene,
          camera: camera,
          player: LessonPlayer(steps),
          widgetSurfaces: widgetSurfaces,
          props: props,
          models: models,
          dataSources: dataSources,
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
    if (current is LessonReady) {
      current.widgetSurfaces?.dispose();
      current.props?.dispose();
      current.models?.dispose();
    }
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

  /// `cloud/lti`'s own `/launch` handler redirects here with `?launch=`
  /// naming the session `check-result` reports against — null on every
  /// other way this screen opens (`--dart-define=level=`, or no query at
  /// all), the same "not every launch is an LTI one" absence
  /// `LessonView.onCheckResult` already keeps.
  String? _launchToken;

  /// `edu-05b`'s own step counter for `applyLessonStepBindings` — separate
  /// from [LessonPlayer.index] on purpose: a live source keeps sampling
  /// while the student sits on one step of the tour, the same distinction
  /// `flutter3d_template_app`'s own `_twinStep` already draws against its
  /// tour's own step index.
  int _dataTick = 0;

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
    final query = Uri.base.queryParameters;
    _launchToken = query['launch'];
    final asset = switch (query['level']) {
      final String level when level.isNotEmpty => level,
      _ => kLevel,
    };
    // `ls-x-00`/`ls-x-01`/`ls-x-03`: the same document, opened in
    // `StereoViewer` — `?stereo=1` next to the `?level=` door this screen
    // already answers, for a build served from the cloud the same way.
    final asStereo = query['stereo'] == '1' || query['stereo'] == 'true';
    await _lesson.open(
      device,
      camera: asStereo ? null : _camera,
      asStereo: asStereo,
      asset: asset,
    );
    // `widgetSurfaces.tickAll()` redraws whichever `widget_surface` this
    // lesson named, only on the frames its own pipeline marks dirty
    // (`wg-00`'s own rule) — driven by a ticker rather than only by the step
    // buttons, the same "reasserted every frame" choice
    // `flutter3d_template_app`'s own tick loop already makes.
    _ticker = createTicker((_) {
      final state = _lesson.state;
      if (state is! LessonReady) return;
      unawaited(state.widgetSurfaces?.tickAll());

      // `edu-05b`: a step's own `bindings`, re-resolved and rewritten every
      // frame — a live source's value is meant to keep moving while its
      // step is on screen, the same "still ticking" contract
      // `flutter3d_template_app`'s own twin dashboard already keeps for its
      // one hardcoded target, generalised here to whatever a document's own
      // `bindings` name.
      final dataSources = state.dataSources;
      final currentStep = state.player?.current ?? state.stereoPlayer?.current;
      if (dataSources != null && currentStep != null) {
        _dataTick++;
        applyLessonStepBindings(
          currentStep,
          _dataTick,
          dataSources,
          nodes: state.nodes,
        );
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    unawaited(_lesson.close());
    super.dispose();
  }

  /// `lti-04`'s own wire, the client half: posts to `cloud/lti`'s
  /// `/launch/<token>/check-result`, same-origin (this build was served by
  /// that same service under `/app/`, so `Uri.base` already names it).
  /// Fire-and-forget — a `check`'s own UI already told the student whether
  /// they were right; a report that fails to reach the platform's
  /// gradebook should not additionally interrupt the lesson they are
  /// still reading.
  void _reportCheckResult(EntityDef step, bool correct) {
    final token = _launchToken;
    if (token == null) return;
    unawaited(_postCheckResult(token, step, correct));
  }

  Future<void> _postCheckResult(
    String token,
    EntityDef step,
    bool correct,
  ) async {
    final uri = Uri.base.resolve('/launch/$token/check-result');
    try {
      await http.post(
        uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'step': step.name ?? step.type, 'correct': correct}),
      );
    } catch (error) {
      debugPrint('check-result: could not reach $uri: $error');
    }
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
          rig: final stereo.StereoRig rig,
          stereoPlayer: final stereo.LessonPlayer stereoPlayer,
          :final scene,
          :final props,
          :final models,
          :final nodes,
        ) =>
          // `ls-x-00`/`ls-x-01`/`ls-x-03`'s own viewport. No `check` prompt
          // here yet — none of the three scenarios this opens for names one
          // in its own acceptance line, and a prompt drawn where there is no
          // flat screen to read it on is a UI question this document does
          // not answer by itself.
          stereo.LessonStereoView(
            renderer: renderer,
            scene: scene,
            rig: rig,
            player: stereoPlayer,
            nodes: nodes,
            restPositions: <String, Vector3>{
              ...?props?.restPositions,
              ...?models?.restPositions,
            },
          ),
        LessonReady(
          :final scene,
          :final camera,
          :final player,
          :final props,
          :final models,
          :final nodes,
        ) =>
          LessonView(
            renderer: renderer,
            scene: scene,
            camera: camera!,
            player: player!,
            nodes: nodes,
            restPositions: <String, Vector3>{
              ...?props?.restPositions,
              ...?models?.restPositions,
            },
            onCheckResult: _launchToken == null ? null : _reportCheckResult,
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
