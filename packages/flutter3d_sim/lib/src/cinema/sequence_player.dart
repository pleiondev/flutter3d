/// A cutscene played in the fixed step.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../actors/actor.dart';
import '../actors/actor_system.dart';
import '../actors/brain.dart';
import '../loop/game_event.dart';
import 'sequence.dart';

/// A cutscene's signal, fired on its step: [signal] and the document's
/// [data] for it, for the game to answer — a sound, a clip, a door.
final class SequenceSignal extends GameEvent {
  /// The signal [signal], fired with [data].
  const SequenceSignal(this.signal, this.data);

  /// The name it is declared and published under. Which signal it is, is
  /// [signal].
  static const String eventName = 'sequence.signal';

  /// Its codec: the signal's name and its data, which the document wrote as
  /// plain values and reads back as they were.
  static final EventCodec<SequenceSignal> codec = EventCodec<SequenceSignal>.of(
    encode: (SequenceSignal e) => <String, Object?>{
      'signal': e.signal,
      'data': e.data,
    },
    decode: (context) {
      final data = context.data;
      return switch (data) {
        {
          'signal': final String signal,
          'data': final Map<Object?, Object?> d,
        } =>
          SequenceSignal(signal, d.cast<String, Object?>()),
        _ => null,
      };
    },
  );

  /// The signal's name as the document wrote it, what the game answers to.
  final String signal;

  /// What the document gave the signal, as plain values; empty for none.
  final Map<String, Object?> data;

  @override
  String get name => eventName;
}

/// Where a [Sequence] has got to, stepped with the simulation.
///
/// **One integer of state**, the step, and that is what makes a cutscene
/// something a run can rewind through and a replay can play: [save] is the
/// step, [restore] puts it back, and everything a cutscene says — which
/// signals have fired, which actors it holds, and for the view where the
/// camera is and what the subtitles read — follows from it and the document.
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
///
/// **In `flutter3d_sim`, though a cutscene looks like the view's**, because
/// it is played by the step: it directs actors through [ActorDirector],
/// publishes [SequenceSignal] on the step channel, and a replay steps it as
/// it steps everything else. What only draws a cutscene is the view's: the
/// camera's pose, the fade and the subtitle of a frame are read off this
/// player by `SequenceView`, in `flutter3d_camera`, and the bars and the
/// overlay are `flutter3d_game_ui`'s.
final class SequencePlayer with ActorDirector {
  /// A player at the start of [sequence], publishing onto [events].
  SequencePlayer(this.sequence, {this.events});

  /// How near its mark counts as on it, in metres, for an actor sent to one.
  static const double onMark = 0.3;

  /// The cutscene played.
  final Sequence sequence;

  /// The bus the signals are published onto as they fire, or null for a
  /// caller that does not listen. Set by whoever steps the player — a genre's
  /// simulation sets its cutscenes' to its own bus.
  EventRegistry? events;

  int _step = 0;
  int _nextSignal = 0;

  /// The step the cutscene has reached.
  int get step => _step;

  /// Whether the last step has been played; [advance] then does nothing
  /// and no actor is directed.
  bool get isFinished => _step >= sequence.steps;

  /// How many steps are left: what a skip steps the game through.
  int get remaining => sequence.steps - _step;

  /// Plays one step: every signal whose moment this step reaches fires, in
  /// order. Nothing, once it has finished.
  void advance() {
    if (isFinished) return;
    _step++;
    final signals = sequence.signals;
    while (_nextSignal < signals.length && signals[_nextSignal].step <= _step) {
      final cue = signals[_nextSignal++];
      events?.publish(SequenceSignal(cue.name, cue.data));
    }
  }

  @override
  bool directs(Actor actor) {
    final name = actor.name;
    if (name == null || isFinished || actor.body == null) return false;
    final cue = sequence.cueFor(name, _step);
    return cue != null && cue.kind != ActorCueKind.release;
  }

  @override
  void steer(Mind it) {
    final cue = sequence.cueFor(it.actor.name!, _step)!;
    final here = it.actor.body?.position;
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
    } else if (kind == ActorCueKind.play) {
      // Once, on the cue's own step: the cue holds until the next, and a
      // gesture asked for every step would never finish.
      it.halt();
      if (cue.step == _step) it.gesture(cue.clip!);
    } else {
      // Standing, and anything this build does not know how to do.
      it.halt();
    }
  }

  /// The player's whole state: `{"step": step}`, what [restore] reads.
  Map<String, Object?> save() => <String, Object?>{'step': _step};

  /// Puts the step back; the signals up to it count as fired, so none fires
  /// twice and none after it is lost.
  void restore(Map<String, Object?> from) {
    _step = ((from['step'] as num?)?.toInt() ?? 0).clamp(0, sequence.steps);
    _nextSignal = sequence.signals.where((s) => s.step <= _step).length;
  }
}
