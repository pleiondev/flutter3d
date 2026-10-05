/// A cutscene played in the fixed step.
library;

import 'package:vector_math/vector_math.dart';

import '../actors/actor.dart';
import '../actors/actor_system.dart';
import '../actors/brain.dart';
import '../loop/game_event.dart';
import 'sequence.dart';

/// A cutscene's signal, fired on its step: [signal] and the document's
/// [data] for it, for the game to answer — a sound, a clip, a door.
final class SequenceSignal extends GameEvent {
  const SequenceSignal(this.signal, this.data);

  final String signal;
  final Map<String, Object?> data;

  @override
  String get name => signal;
}

/// Where a [Sequence] has got to, stepped with the simulation.
///
/// **One integer of state**, the step, and that is what makes a cutscene
/// something a run can rewind through and a replay can play: [save] is the
/// step, [restore] puts it back, and everything a cutscene says — which
/// signals have fired, where the camera is, what the subtitles read — follows
/// from it and the document.
///
/// **Skipped by being played.** A cutscene that moves anything the game
/// steps — a door its signal opens, an actor its signal sends walking — is
/// only skipped to the same state by stepping the game through what is left
/// of it, faster than it is drawn. [remaining] is how many steps that is; a
/// skip that jumped the step to the end would leave the world where the
/// cutscene started and the cutscene where it finished.
///
/// **And the actors' director**, given to `ActorSystem.director` for as long
/// as it plays: an actor the cutscene has told something is walked to its
/// mark, turned or held, and handed back to its brain when it is released
/// or the cutscene ends. Which cue an actor is under follows from the step
/// as everything else does, so the directing is saved by saving the step.
final class SequencePlayer implements ActorDirector {
  SequencePlayer(this.sequence, {this.events});

  /// How near its mark counts as on it, in metres, for an actor sent to one.
  static const double onMark = 0.3;

  final Sequence sequence;

  /// Where the signals go, or null for a caller that does not listen.
  final GameEvents? events;

  int _step = 0;
  int _nextSignal = 0;

  /// The step the cutscene has reached.
  int get step => _step;

  bool get finished => _step >= sequence.steps;

  /// How many steps are left: what a skip steps the game through.
  int get remaining => sequence.steps - _step;

  /// Plays one step: every signal whose moment this step reaches fires, in
  /// order. Nothing, once it has finished.
  void advance() {
    if (finished) return;
    _step++;
    final signals = sequence.signals;
    while (_nextSignal < signals.length && signals[_nextSignal].step <= _step) {
      final cue = signals[_nextSignal++];
      events?.add(SequenceSignal(cue.name, cue.data));
    }
  }

  /// The moment to draw: [alpha] of the way from the step before this one
  /// to this one, as a frame between two steps is drawn.
  double _drawn(double alpha) =>
      (_step - 1 + alpha).clamp(0.0, sequence.steps.toDouble());

  /// Where the camera is to be drawn from — see [Sequence.cameraAt] — or
  /// null when the cutscene leaves the camera to the game.
  double? cameraAt(Vector3 at, Vector3 look, {double alpha = 1.0}) =>
      sequence.hasCamera ? sequence.cameraAt(_drawn(alpha), at, look) : null;

  /// What the subtitles say now, or null.
  String? get subtitle => sequence.subtitleAt(_step);

  /// How dark the screen is to be drawn, nought to one.
  double fade({double alpha = 1.0}) => sequence.fadeAt(_drawn(alpha));

  @override
  bool directs(Actor actor) {
    final name = actor.name;
    if (name == null || finished || actor.position == null) return false;
    final cue = sequence.cueFor(name, _step);
    return cue != null && cue.kind != ActorCueKind.release;
  }

  @override
  void steer(Mind it) {
    final cue = sequence.cueFor(it.actor.name!, _step)!;
    final here = it.actor.position;
    final at = cue.at;
    final kind = cue.kind;
    if (kind == ActorCueKind.goTo) {
      final dx = at!.x - here!.x;
      final dz = at.z - here.z;
      if (dx * dx + dz * dz <= onMark * onMark) {
        it.halt();
        return;
      }
      it.steerTowards(at);
      final heading = it.system.heading;
      it.turnTowards(heading.x, heading.z);
    } else if (kind == ActorCueKind.face) {
      it
        ..halt()
        ..turnTowards(at!.x - here!.x, at.z - here.z);
    } else {
      // Standing, and anything this build does not know how to do.
      it.halt();
    }
  }

  Map<String, Object?> save() => <String, Object?>{'step': _step};

  /// Puts the step back; the signals up to it count as fired, so none fires
  /// twice and none after it is lost.
  void restore(Map<String, Object?> from) {
    _step = ((from['step'] as num?)?.toInt() ?? 0).clamp(0, sequence.steps);
    _nextSignal = sequence.signals.where((s) => s.step <= _step).length;
  }
}
