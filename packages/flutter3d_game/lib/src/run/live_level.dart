import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'demo_recording.dart';
import 'run_timeline.dart';

/// The level a running game is playing, and how to change it under the game.
///
/// **The game says how; this says when.** Only the game knows what its level
/// became once loaded — which scene nodes are its lights, which colliders
/// its brushes, what its entities spawned — so it hands over two functions:
/// [present] patches what only the picture reads, [rebuild] replaces what the
/// simulation reads. [apply] asks [diffLevel] which of the two an edit needs
/// and calls them in the order that keeps the run honest: the simulation's
/// half through [timeline] when there is one, so the run is replayed under
/// the new level rather than jumping, then the picture's.
///
/// Without a [timeline] the simulation's half is rebuilt in place, which is
/// what a game with no rewind buffer can do and what it then gets: a run no
/// replay can reach. The report says which happened.
final class LiveLevel {
  LiveLevel({
    required this.level,
    required this.present,
    required this.rebuild,
    this.timeline,
    this.prepare,
    this.swapped,
    this.collision,
    this.gameWorld,
  });

  /// The run's collision world, whose properties (`CollisionWorld.properties`)
  /// an edit of the level's `world` changes: set to the next level's world
  /// laid over [gameWorld] before [rebuild] runs, inside the timeline's swap
  /// when there is one, so a run replayed under a level moved to the Moon
  /// falls by the Moon from the step it branched at. Null for a game that
  /// sets its world in [rebuild] itself.
  final CollisionWorld? collision;

  /// The game's own world, which every level it plays is laid over: the
  /// world it stages its runs in. The standard world when null.
  final WorldProperties? gameWorld;

  /// [next]'s world on [collision], then [rebuild].
  void _rebuild(Level next) {
    final world = collision;
    if (world != null) {
      world.properties = next.worldOver(
        gameWorld ?? WorldProperties.standard,
        materials: world.materials,
      );
    }
    rebuild(next);
  }

  /// Told the step [timeline] swapped the next level in before, right after
  /// the swap and before [present]: what a [DemoRecording] needs to write
  /// the edit into the run. The step is decided inside
  /// `RunTimeline.swapLevel` — the last keyframe — so nothing outside the
  /// swap can know it otherwise.
  final void Function(LevelSwapped swap)? swapped;

  /// Builds ahead what [rebuild] and [present] will swap in, for a game
  /// whose level cannot be made synchronously: textures to upload, meshes,
  /// a scene. Awaited by [applyWhenReady] before anything changes, so a
  /// level that will not build leaves the one being played untouched.
  final Future<void> Function(Level next)? prepare;

  /// Patches the running scene to the next level's look. Its
  /// [LevelPresent.diff] names what changed, so a presenter can touch one
  /// lamp rather than rebuild them all.
  final void Function(LevelPresent change) present;

  /// Replaces what the simulation reads — colliders, spawns, the ground —
  /// with [next]'s. Called inside `RunTimeline.swapLevel` when there is a
  /// [timeline], so it must leave to the snapshot restore what snapshots
  /// carry.
  final void Function(Level next) rebuild;

  /// The run to branch when an edit reaches the simulation.
  final RunTimeline? timeline;

  /// The level being played now.
  ///
  /// Set by a game that moved on by its own means — the next level, a
  /// restart — so the next edit is compared with what is on screen.
  Level level;

  /// [prepare], then [apply]: what the extension does with a level that
  /// arrived. An edit that changes nothing prepares nothing.
  Future<LevelApplied> applyWhenReady(Level next, {LevelDiff? diff}) async {
    final change = diff ?? diffLevel(level, next);
    if (!change.isEmpty) await prepare?.call(next);
    return apply(next, diff: change);
  }

  /// Makes [next] the level being played, as little disturbed as the change
  /// allows.
  ///
  /// [diff] is what a `LevelPatch` already said changed; without one the two
  /// levels are compared by [diffLevel].
  LevelApplied apply(Level next, {LevelDiff? diff}) {
    final change = diff ?? diffLevel(level, next);
    if (change.isEmpty) {
      level = next;
      return LevelApplied(diff: change);
    }
    final int? swappedAt;
    if (change.isPresentationOnly) {
      swappedAt = null;
    } else if (timeline case final RunTimeline run) {
      swappedAt = run.swapLevel(
        () => _rebuild(next),
        levelDigest: next.digestHex,
      );
      swapped?.call(LevelSwapped(next: next, step: swappedAt));
    } else {
      _rebuild(next);
      swappedAt = null;
    }
    present(LevelPresent(next: next, diff: change));
    level = next;
    return LevelApplied(
      diff: change,
      swappedAt: swappedAt,
      rebuiltInPlace: !change.isPresentationOnly && swappedAt == null,
    );
  }
}

/// What [LiveLevel.present] is handed: the level to show, and what changed.
///
/// **One object, so a minor can say more** (the step the picture catches up
/// at) without breaking a presenter written against 1.0.
final class LevelPresent {
  /// [next], changed from the level before as [diff] says.
  const LevelPresent({required this.next, required this.diff});

  /// The level being swapped in.
  final Level next;

  /// What changed from the level being played.
  final LevelDiff diff;
}

/// What [LiveLevel.swapped] is told: the level the timeline swapped in, and
/// the step it swapped it in before.
///
/// **One object, so a minor can say more** without breaking a listener
/// written against 1.0.
final class LevelSwapped {
  /// [next], swapped in before [step].
  const LevelSwapped({required this.next, required this.step});

  /// The level swapped in.
  final Level next;

  /// The step the timeline branched at.
  final int step;
}

/// What one [LiveLevel.apply] did.
final class LevelApplied {
  const LevelApplied({
    required this.diff,
    this.swappedAt,
    this.rebuiltInPlace = false,
  });

  final LevelDiff diff;

  /// The step the timeline branched at, when the edit reached the
  /// simulation and there was a timeline to branch.
  final int? swappedAt;

  /// The edit reached the simulation and there was no timeline: the run
  /// carries on from a state a replay cannot reach.
  final bool rebuiltInPlace;

  Map<String, Object?> toJson() => <String, Object?>{
    'diff': diff.toJson(),
    'swappedAt': ?swappedAt,
    'rebuiltInPlace': rebuiltInPlace,
  };
}

/// What [answerLevelApply] and [answerLevelPatch] answered: the result to
/// send back, or why the level was not taken.
///
/// **A class, not a record**, so an answer can say more in a minor release
/// without breaking a caller that reads it.
final class LevelExtensionAnswer {
  /// The edit was taken: [result] is what `LevelApplied.toJson` wrote.
  const LevelExtensionAnswer.applied(Map<String, Object?> this.result)
    : error = null,
      isStale = false;

  /// The edit was refused, for [error]; [isStale] when it was a patch made
  /// against a level the game no longer has, which the sender can answer by
  /// sending the whole document.
  const LevelExtensionAnswer.refused(String this.error, {this.isStale = false})
    : result = null;

  /// What the extension answers when the edit was taken; null when refused.
  final Map<String, Object?>? result;

  /// Why the edit was refused; null when it was taken.
  final String? error;

  /// Whether a refused patch was made against another version of the level.
  final bool isStale;
}

/// Answers `ext.flutter3d.level.apply` for [live]: [parameters] carry the
/// level's whole `document`, as JSON, and its `hash`, `Level.digestHex`.
///
/// **The hash is checked, not trusted.** It is what the editor computed from
/// the level it saved; the document is what arrived. When the two disagree,
/// something between them changed the bytes — an encoding, a truncation —
/// and applying the document would put a level under the run that the editor
/// never showed anybody. So a mismatch is refused, naming both.
///
/// A level whose [LiveLevel.prepare] throws is refused the same way, with
/// what it threw: the game keeps the level it had.
///
/// A plain function over the parameters, and [registerLevelExtension] a thin
/// door onto it, so the answers are tested without a VM service.
Future<LevelExtensionAnswer> answerLevelApply(
  LiveLevel live,
  Map<String, String> parameters,
) async {
  final document = parameters['document'];
  final hash = parameters['hash'];
  if (document == null || hash == null) {
    return const LevelExtensionAnswer.refused(
      'level.apply takes a document and its hash',
    );
  }
  final Level next;
  try {
    next = Level.fromJson(jsonDecode(document) as Map<String, Object?>);
  } on Object catch (error) {
    return LevelExtensionAnswer.refused('the document is not a level: $error');
  }
  if (next.digestHex != hash) {
    return LevelExtensionAnswer.refused(
      'the document digests to ${next.digestHex}, not $hash; '
      'it changed on the way',
    );
  }
  try {
    return LevelExtensionAnswer.applied(
      (await live.applyWhenReady(next)).toJson(),
    );
  } on Object catch (error) {
    return LevelExtensionAnswer.refused('the level did not build: $error');
  }
}

/// Answers `ext.flutter3d.level.patch` for [live]: [parameters] carry a
/// `LevelPatch` as JSON, made against the level the editor last saved.
///
/// **Two kinds of no, because the sender does different things with them.**
/// A patch that does not apply to what the game has — another version, a
/// row that is not the one it names — is [stale]: the editor sends the whole
/// document, which the game can take whatever it had. A patch that applies
/// to a level that will not build is refused like a document that will not
/// build, and is not stale: sent whole, it would be refused again.
Future<LevelExtensionAnswer> answerLevelPatch(
  LiveLevel live,
  Map<String, String> parameters,
) async {
  final text = parameters['patch'];
  if (text == null) {
    return const LevelExtensionAnswer.refused('level.patch takes a patch');
  }
  final LevelPatch patch;
  try {
    patch = LevelPatch.fromJson(jsonDecode(text) as Map<String, Object?>);
  } on Object catch (error) {
    return LevelExtensionAnswer.refused(
      'the patch is not a level patch: $error',
    );
  }
  switch (patch.applyTo(live.level)) {
    case LevelPatchRefused(:final reason):
      return LevelExtensionAnswer.refused(reason, isStale: true);
    case LevelPatched(:final level, :final diff):
      try {
        final applied = await live.applyWhenReady(level, diff: diff);
        return LevelExtensionAnswer.applied(applied.toJson());
      } on Object catch (error) {
        return LevelExtensionAnswer.refused('the level did not build: $error');
      }
  }
}

/// Puts [live] on the VM service as `ext.flutter3d.level.apply` and
/// `ext.flutter3d.level.patch`, beside the timeline's own extensions: the
/// editor that saved a level sends it here, to a game on this machine or on
/// a phone, and the running game takes it.
///
/// A stale patch is answered with `LevelPatch.staleCode` rather than
/// `invalidParams`, so the editor can tell "send it whole" from "no".
void registerLevelExtension(LiveLevel live) {
  registerFlutter3dExtension('ext.flutter3d.level.apply', (
    method,
    parameters,
  ) async {
    final LevelExtensionAnswer(:result, :error) = await answerLevelApply(
      live,
      parameters,
    );
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        error,
      );
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(result));
  }, answers: const <String>{'diff', 'swappedAt', 'rebuiltInPlace'});
  registerFlutter3dExtension('ext.flutter3d.level.patch', (
    method,
    parameters,
  ) async {
    final LevelExtensionAnswer(:result, :error, :isStale) =
        await answerLevelPatch(live, parameters);
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        isStale
            ? LevelPatch.staleCode
            : developer.ServiceExtensionResponse.invalidParams,
        error,
      );
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(result));
  }, answers: const <String>{'diff', 'swappedAt', 'rebuiltInPlace'});
}
