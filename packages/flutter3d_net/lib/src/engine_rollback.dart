/// Rollback over the engine's loop: the one rollback, handed an
/// `EngineLoop`'s snapshots and steps.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'peer_wire.dart';
import 'rollback_session.dart';

/// A state an [EngineRollback] keeps of its loop: the step count and every
/// part of the state the loop's snapshots hold.
typedef LoopState = ({int step, Snapshot state});

/// An [EngineLoop] kept in step on two machines or a party of them over a
/// [PeerWire]: [RollbackSession] with the loop's snapshots as its state and
/// the loop's steps as its step.
///
/// **The one rollback, on the one loop.** The session does the input delay,
/// the guess of the others' hands, the rollback when a guess was wrong and
/// the window; this hands it [EngineLoop.capture] and [EngineLoop.rewindTo]
/// — the snapshot path every rewind takes, which covers the world and every
/// plugin's own part — and runs each step through [EngineLoop.runSteps],
/// marked `resimulated` when it is a step run again, so the frame channel
/// reconciles what it already showed rather than playing a sound twice.
///
/// **What a game hands it.** [captureLocalFrame] reads this machine's
/// hands; [applyFrames] writes every slot's frame into the loop's input
/// before the step runs — by slot, the same player on every machine.
///
/// ```dart
/// final rollback = EngineRollback(
///   loop: loop,
///   wire: seat.wire,
///   players: seat.size,
///   captureLocalFrame: () => {'move': stick.x.round()},
///   applyFrames: (frames) => game.applyHands(frames),
/// );
/// // once a fixed step, in place of loop.frame:
/// rollback.advance();
/// ```
final class EngineRollback {
  EngineRollback({
    required this.loop,
    required PeerWire wire,
    required Map<String, Object?> Function() captureLocalFrame,
    required this.applyFrames,
    int? localSlot,
    int players = 2,
    int inputDelay = 2,
    int maxRollbackFrames = 8,
    int redundancy = 8,
    bool Function(LoopState after)? endsAt,
    void Function(int step, LoopState after, Map<int, Map<String, Object?>>)?
    onSettled,
    void Function(int from, Map<String, Object?> message)? onMessage,
  }) {
    session = RollbackSession<LoopState>(
      wire: wire,
      localSlot: localSlot,
      players: players,
      captureLocalFrame: captureLocalFrame,
      applyAndStep: _step,
      save: () => (step: loop.step, state: loop.capture()),
      restore: (saved) => loop.rewindTo(saved.step, state: saved.state),
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      redundancy: redundancy,
      endsAt: endsAt,
      onSettled: onSettled,
      onMessage: onMessage,
    );
  }

  /// The loop kept in step.
  final EngineLoop loop;

  /// Writes every slot's frame into the loop's input for the step about to
  /// run.
  final void Function(Map<int, Map<String, Object?>> frames) applyFrames;

  /// The rollback itself: its window, its counters, its agreed ending.
  late final RollbackSession<LoopState> session;

  /// Captures this machine's hands, sends them, and runs one step of the
  /// loop. Once a fixed step.
  void advance() => session.advance();

  void _step(Map<int, Map<String, Object?>> frames) {
    applyFrames(frames);
    loop.runSteps(1, resimulated: session.isResimulating);
  }
}
