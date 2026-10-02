import 'dart:convert';
import 'dart:developer' as developer;

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
  });

  /// Told the step [timeline] swapped [next] in before, right after the swap
  /// and before [present]: what a [DemoRecording] needs to write the edit
  /// into the run. The step is decided inside `RunTimeline.swapLevel` — the
  /// last keyframe — so nothing outside the swap can know it otherwise.
  final void Function(Level next, int step)? swapped;

  /// Builds ahead what [rebuild] and [present] will swap in, for a game
  /// whose level cannot be made synchronously: textures to upload, meshes,
  /// a scene. Awaited by [applyWhenReady] before anything changes, so a
  /// level that will not build leaves the one being played untouched.
  final Future<void> Function(Level next)? prepare;

  /// Patches the running scene to [next]'s look. [diff] names what changed,
  /// so a presenter can touch one lamp rather than rebuild them all.
  final void Function(Level next, LevelDiff diff) present;

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
    if (change.presentationOnly) {
      swappedAt = null;
    } else if (timeline case final RunTimeline run) {
      swappedAt = run.swapLevel(
        () => rebuild(next),
        levelDigest: next.digestHex,
      );
      swapped?.call(next, swappedAt);
    } else {
      rebuild(next);
      swappedAt = null;
    }
    present(next, change);
    level = next;
    return LevelApplied(
      diff: change,
      swappedAt: swappedAt,
      rebuiltInPlace: !change.presentationOnly && swappedAt == null,
    );
  }
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
Future<({Map<String, Object?>? result, String? error})> answerLevelApply(
  LiveLevel live,
  Map<String, String> parameters,
) async {
  final document = parameters['document'];
  final hash = parameters['hash'];
  if (document == null || hash == null) {
    return (result: null, error: 'level.apply takes a document and its hash');
  }
  final Level next;
  try {
    next = Level.fromJson(jsonDecode(document) as Map<String, Object?>);
  } on Object catch (error) {
    return (result: null, error: 'the document is not a level: $error');
  }
  if (next.digestHex != hash) {
    return (
      result: null,
      error:
          'the document digests to ${next.digestHex}, not $hash; '
          'it changed on the way',
    );
  }
  try {
    return (result: (await live.applyWhenReady(next)).toJson(), error: null);
  } on Object catch (error) {
    return (result: null, error: 'the level did not build: $error');
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
Future<({Map<String, Object?>? result, String? error, bool stale})>
answerLevelPatch(LiveLevel live, Map<String, String> parameters) async {
  final text = parameters['patch'];
  if (text == null) {
    return (result: null, error: 'level.patch takes a patch', stale: false);
  }
  final LevelPatch patch;
  try {
    patch = LevelPatch.fromJson(jsonDecode(text) as Map<String, Object?>);
  } on Object catch (error) {
    return (
      result: null,
      error: 'the patch is not a level patch: $error',
      stale: false,
    );
  }
  switch (patch.applyTo(live.level)) {
    case LevelPatchRefused(:final reason):
      return (result: null, error: reason, stale: true);
    case LevelPatched(:final level, :final diff):
      try {
        final applied = await live.applyWhenReady(level, diff: diff);
        return (result: applied.toJson(), error: null, stale: false);
      } on Object catch (error) {
        return (
          result: null,
          error: 'the level did not build: $error',
          stale: false,
        );
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
  developer.registerExtension('ext.flutter3d.level.apply', (
    method,
    parameters,
  ) async {
    final (:result, :error) = await answerLevelApply(live, parameters);
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        error,
      );
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(result));
  });
  developer.registerExtension('ext.flutter3d.level.patch', (
    method,
    parameters,
  ) async {
    final (:result, :error, :stale) = await answerLevelPatch(live, parameters);
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        stale
            ? LevelPatch.staleCode
            : developer.ServiceExtensionResponse.invalidParams,
        error,
      );
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(result));
  });
}
