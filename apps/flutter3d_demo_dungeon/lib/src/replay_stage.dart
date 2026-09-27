/// The crypt, loaded to replay a run into and drawn the way the game draws
/// it — `N3`'s pacing harness, and whatever else wants a `.f3drun` played
/// through the renderer rather than only through the simulation.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'run_cubit.dart';
import 'staging.dart';

final class _MemoryStorage implements Storage {
  final Map<String, String> _documents = <String, String>{};
  @override
  String? read(String name) => _documents[name];
  @override
  bool write(String name, String contents) {
    _documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => _documents.remove(name);
}

/// A level loaded through the game's own run, a player's camera, and the
/// renderer that draws them.
///
/// The same assembly `test/replay_video_test.dart` uses, with the device
/// and renderer handed in, so a run replays onto the software rasteriser in
/// a test and onto Impeller in `integration_test/pacing_test.dart` through
/// the same code. What it leaves out is the game's presentation: monsters
/// are drawn where their bodies are rather than interpolated and animated,
/// and there is no held weapon, no particles and no HUD.
final class CryptReplay {
  CryptReplay._(this.level, this.input, this.renderer, this.camera);

  /// Loads [levelAsset] the way the game's first level is loaded.
  static Future<CryptReplay> open({
    required GraphicsDevice device,
    required Renderer renderer,
    String levelAsset = 'assets/levels/crypt.json',
  }) async {
    final input = InputState();
    final run = RunCubit(
      DungeonRun(
        firstLevel: levelAsset,
        registry: sampleRegistry(
          extra: const <EntityKind>[WidgetSurfaceKind()],
        ),
        input: input,
        inventory: startingInventory(),
        saves: SaveFile(appName: 'dungeon-replay', storage: _MemoryStorage()),
        device: device,
      ),
    );
    await run.begin();
    final state = run.state;
    if (state is! RunPlaying<LevelReady>) {
      throw StateError('$levelAsset did not load: $state');
    }
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.2,
        near: 0.05,
        far: 200.0,
      ),
    );
    state.level.loaded.scene.add(camera);
    return CryptReplay._(state.level, input, renderer, camera);
  }

  final LevelReady level;

  /// What the tape is played into.
  final InputState input;

  final Renderer renderer;

  /// The player's eye, placed by [draw].
  final CameraNode camera;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  /// Completes once the level's monsters and props wear the models they were
  /// loading — what a loading screen waits for before `Renderer.warmUp`, so
  /// the warm-up sees every mesh play will draw.
  Future<void> settled() => Future.wait(<Future<void>>[
    level.actorVisuals.settled,
    level.fixtureVisuals.settled,
  ]);

  /// Puts the simulation back where [demo] starts.
  void rewind(Demo demo) => level.staged.sim.restore(demo.start);

  /// One fixed step of the simulation.
  void step(double dt) => level.staged.sim.step(dt);

  /// The settings the game draws the crypt with: the level's fog and a
  /// metered exposure. [frameWorkBudget] is `RenderSettings.frameWorkBudget`.
  RenderSettings settings({int frameWorkBudget = 0}) => RenderSettings(
    fog: FogSettings(
      color: level.loaded.level.fogColor,
      density: level.loaded.level.fogDensity,
    ),
    autoExposure: const AutoExposureSettings(enabled: true),
    frameWorkBudget: frameWorkBudget,
  );

  /// Puts [camera] where the player's eyes are, looking where they look.
  void placeCamera() {
    level.staged.player
      ..eye(_eye)
      ..aim(_aim);
    camera
      ..setPositionFrom(_eye)
      ..lookAt(_eye + _aim);
  }

  /// Draws one frame from where the player stands.
  FrameResult draw({
    required int width,
    required int height,
    RenderSettings? settings,
  }) {
    placeCamera();
    return renderer.render(
      width: width,
      height: height,
      scene: level.loaded.scene,
      views: views(),
      settings: settings ?? this.settings(),
    );
  }

  /// The views [draw] draws: the player's eye, clearing to black. Also what
  /// a warm-up is handed, since a probe captures against the first view's
  /// clear colour.
  List<RenderView> views() => <RenderView>[
    RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
  ];
}
