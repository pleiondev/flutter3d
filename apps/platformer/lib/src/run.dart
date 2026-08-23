import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_session/flutter3d_session.dart';

import 'looks.dart';
import 'staging.dart';

/// A level, loaded and playable.
///
/// The live objects rather than copies of their numbers: a scene and a
/// simulation are read sixty times a second, and a state class holding their
/// contents would be a state class emitted sixty times a second.
final class LevelReady {
  const LevelReady({
    required this.loaded,
    required this.staged,
    required this.fixtures,
  });

  final LoadedLevel loaded;
  final Staged staged;
  final FixtureVisuals fixtures;

  Scene get scene => loaded.scene;
  Runner get runner => staged.runner;
  PlatformerSimulation get sim => staged.sim;
}

/// What a run has come to so far, carried from one level into the next.
///
/// **Three lives used to mean three lives per level**, and the clock on the
/// summit read as the time for the last climb: every level built a fresh
/// simulation from the constant, and the tally of the run before it went
/// nowhere. A run spans levels and a simulation does not.
typedef Carried = ({int lives, int deaths, double elapsed, int coins});

/// Reads a level document and builds the half of it that draws.
///
/// **A named function rather than four lines inside [PlatformerRun.open],
/// because `frame_test.dart` was the second copy of them.** Its copy happened
/// to be right; the crypt's equivalent copy had lost `bindLights()`, so every
/// torch in that harness lit nothing. A frame test is only worth having if the
/// frame is the game's, and that means calling what the game calls rather than
/// writing it out again beside it.
///
/// Deliberately *not* in `staging.dart`: everything here needs a
/// [GraphicsDevice], and that file exists to be callable without one.
Future<
    ({
      EntityRegistry kinds,
      LoadedLevel loaded,
      FixtureVisuals fixtures,
    })> openLevel(
  String asset, {
  required GraphicsDevice device,
}) async {
  final kinds = platformerRegistry();
  final loaded = await LevelLoader().load(
    asset,
    device: device,
    registry: kinds,
    rules: platformerRules(),
  );
  final fixtures = FixtureVisuals(
    loaded.scene,
    loaded,
    appearance: const PlatformerLooks(),
    device: device,
    // Before spawning, so a light-bearing fixture can find the light it drives.
  )..bindLights();

  return (kinds: kinds, loaded: loaded, fixtures: fixtures);
}

/// This game's answers to the five questions a run asks.
///
/// Starting, restarting, moving on, saving, resuming and the guards around them
/// are `RunSession`'s, shared with the other two games. What is here is what
/// only a platformer can answer — including the two places it disagrees with
/// the crypt, which are both about having lives.
final class PlatformerRun extends RunSession<LevelReady> {
  PlatformerRun({
    required super.firstLevel,
    required super.saves,
    required this.input,
    required this.openDevice,
    required this.onLevelBuilt,
    this.startingLives = 3,
    this.pauseBetweenLevels = const Duration(milliseconds: 1400),
  });

  final InputState input;

  /// The device to upload through, waited for rather than given up on: the
  /// first level is asked for before the renderer has finished opening.
  final Future<GraphicsDevice> Function() openDevice;

  /// Everything the widget has to do with a level once it exists — the runner's
  /// node, the camera, the interpolators. Handed in because it touches the
  /// widget's own fields, which a run has no business holding.
  final void Function(LevelReady level, GraphicsDevice device) onLevelBuilt;

  final int startingLives;

  /// A beat on the results screen before the next level: arriving somewhere new
  /// in the same frame the last place ended reads as a glitch.
  final Duration pauseBetweenLevels;

  Carried? _carried;

  @override
  Future<LevelReady> open(String asset) async {
    final device = await openDevice();
    final (:kinds, :loaded, :fixtures) = await openLevel(asset, device: device);

    final staged = stage(
      loaded.level,
      loaded.collision,
      input: input,
      registry: kinds,
      onFixture: fixtures.add,
      coins: _carried?.coins ?? 0,
      lives: _carried?.lives ?? startingLives,
      deaths: _carried?.deaths ?? 0,
      elapsed: _carried?.elapsed ?? 0.0,
    );

    final level = LevelReady(loaded: loaded, staged: staged, fixtures: fixtures);
    onLevelBuilt(level, device);
    return level;
  }

  @override
  RunOutcome outcomeOf(LevelReady level) => level.sim.state.outcome;

  @override
  String? nextOf(LevelReady level) => level.sim.nextLevel;

  @override
  Snapshot snapshotOf(LevelReady level) => level.sim.save();

  @override
  void restoreInto(LevelReady level, Snapshot snapshot) =>
      level.sim.restore(snapshot);

  /// The tally of the run so far. Only this side knows what the level after
  /// this one is, so only this side can carry anything into it.
  @override
  void carryFrom(LevelReady level, String next) => _carried = (
        lives: level.sim.lives,
        deaths: level.sim.deaths,
        elapsed: level.sim.elapsed,
        coins: level.runner.purse['coin'],
      );

  @override
  void startFresh() => _carried = null;

  /// **A platformer has lives, so losing ends the run** — and a save from
  /// before the last life would undo the loss. The crypt disagrees, and is
  /// right for itself: it has no lives, so dying is a setback rather than an
  /// ending.
  @override
  void onLost(LevelReady level) {
    _carried = null;
    saves.clear();
  }

  @override
  Future<void> beforeNext(String next) =>
      Future<void>.delayed(pauseBetweenLevels);
}
