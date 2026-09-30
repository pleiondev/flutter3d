import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_transport.dart';
import 'net_transport_wire.dart';

/// Two players' worth of a fixed-step simulation, kept in step across an
/// unreliable [NetTransport] — input frames, delay, prediction, and rollback
/// on a confirmation that disagreed, in the order `doc/tooling-plan.md`'s
/// `net-01` names them.
///
/// **`flame_multiplayer`'s [RollbackSession], over a [NetTransport].** The
/// rollback itself lives there, in a package with no dependencies, and runs
/// here on a [Snapshot] through [NetTransportWire]; this class keeps the
/// constructor and the messages on the wire every game and relay already
/// used, so a peer on either side of the move still plays with the other.
///
/// **What this does not know.** Which genre is playing, how many actions a
/// controller has, or what a frame's fields mean — [captureLocalFrame] reads
/// them out of whatever the caller's own input representation is, and
/// [applyAndStep] writes them back into it before calling that genre's own
/// `sim.step`. This is `net-01`'s entire claim: a game hands over four
/// functions and gets rollback, rather than teaching this package a second
/// genre's vocabulary the way `flutter3d_app`'s level loader was built not to.
///
/// ## Fixed input delay, and why it is not the whole answer
///
/// A step's own input is captured the moment [advance] is called, but is not
/// *applied* to this side's own simulation until [inputDelay] steps later —
/// which gives it that many steps, plus however long the wire takes, to
/// reach the peer before their simulation needs it. Set [inputDelay] high
/// enough for the connection and a correction almost never has to reach far
/// back; set it to zero and every step not yet confirmed runs on a guess.
/// Neither number removes the need for the other half:
///
/// ## Prediction, and the rollback that corrects it
///
/// A step whose remote frame has not arrived yet runs on the last one that
/// had — "predicted by the last frame", the same way a controller that
/// stopped reporting keeps [InputTapePlayback] holding its last known state
/// rather than snapping to neutral. When the true frame for that step
/// arrives — [receive] delivers it, from whatever [NetTransport.listen]
/// handed to the session at construction — one of two things happens: it
/// matches what was guessed, and nothing more is done; or it does not, and
/// [restore] puts the state back to the moment before that step, [applyAndStep]
/// redoes it and every step since with the now-known-true value in the
/// remote's place, and this side's present is a step it has already lived
/// once corrected under it rather than a step it visibly rewinds through —
/// there is no camera here to notice the difference, only [applyAndStep]
/// being called again for steps that already happened.
///
/// ## The window, and what falls out of it
///
/// Only the last [maxRollbackFrames] steps keep the snapshot a correction
/// needs. A confirmation for a step older than that arrives too late to
/// redo — [droppedCorrections] counts it rather than pretending the guess
/// was confirmed — and the fix for seeing that counter move is the same one
/// GGPO-style netcode always has: raise [inputDelay], or the window, or both,
/// for a connection this slow.
///
/// ## Redundancy, for the loss [NetTransport] does not promise around
///
/// Every message carries not just the step it was captured for but the
/// [redundancy] steps before it too — the same frame is sent again, riding
/// along with each of the next few, so one lost message costs nothing as
/// long as a later one carrying the same step's data gets through. Without
/// this a lost message is a step that never confirms: the prediction for it
/// stands forever, unremarked, and a side that guessed wrong there diverges
/// with nothing in this class ever noticing — [NetSession] has no way to ask
/// a transport to resend what it already told it to drop.
final class NetSession {
  NetSession({
    required this.transport,
    required this.captureLocalFrame,
    required this.applyAndStep,
    required this.save,
    required this.restore,
    this.inputDelay = 2,
    this.maxRollbackFrames = 8,
    this.redundancy = 8,
    this.onSettled,
  }) : assert(inputDelay >= 0, 'a negative delay would apply input early'),
       assert(
         maxRollbackFrames > 0,
         'a window of zero could never correct anything',
       ),
       assert(redundancy >= 0, 'negative redundancy resends nothing extra') {
    _session = RollbackSession<Snapshot>(
      wire: NetTransportWire(transport),
      captureLocalFrame: captureLocalFrame,
      applyAndStep: applyAndStep,
      save: save,
      restore: restore,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      redundancy: redundancy,
      onSettled: onSettled,
    );
  }

  final NetTransport transport;

  /// Reads this side's own input for the step about to be captured — called
  /// once per [advance], before that step is due to run.
  final Map<String, Object?> Function() captureLocalFrame;

  /// Writes [local] and [remote] into whatever this game's own input
  /// representation is, then runs one fixed step of it. Called once for
  /// every step this session ever runs — including, for a step being
  /// corrected, a second or third time with a different [remote].
  final void Function(Map<String, Object?> local, Map<String, Object?> remote)
  applyAndStep;

  final Snapshot Function() save;
  final void Function(Snapshot snapshot) restore;

  /// How many steps a captured local frame waits before [applyAndStep] uses
  /// it — see the class doc's "Fixed input delay" section.
  final int inputDelay;

  /// How many past steps keep the snapshot a correction would restore —
  /// see the class doc's "The window" section.
  final int maxRollbackFrames;

  /// How many steps back each outgoing message repeats — see the class
  /// doc's "Redundancy" section.
  final int redundancy;

  /// Called once for a step that has just aged out of the rollback window —
  /// which is also the first moment this session can promise no later
  /// correction will ever touch it again. [after] is the state once that
  /// step had finished running.
  ///
  /// **The right moment to take a checkpoint digest, and the only one.** A
  /// step just run is still a guess about the far side until its
  /// confirmation lands, and a digest taken before then is a digest of a
  /// guess — two honest peers holding different guesses is not a desync,
  /// only two people who have not compared notes yet. This fires once that
  /// comparison can no longer change, so `DigestTrace.observe` called from
  /// here answers "did the two sides actually disagree", not "did they
  /// happen to still be guessing differently this instant".
  final void Function(int step, Snapshot after)? onSettled;

  late final RollbackSession<Snapshot> _session;

  /// The step about to run.
  int get step => _session.step;

  /// A confirmation arrived for a step no longer in the window — see the
  /// class doc. Zero on a connection [inputDelay] and [maxRollbackFrames]
  /// are actually sized for.
  int get droppedCorrections => _session.droppedCorrections;

  /// Captures this side's input, sends it, and runs one fixed step —
  /// call once per fixed step, the same one [applyAndStep] steps by.
  void advance() => _session.advance();

  /// A batch of frames the transport delivered, each named by the step it
  /// describes — what the session listens with, open for a test or a
  /// transport that hands messages in some other way.
  void receive(Map<String, Object?> message) => _session.receive(message);
}
