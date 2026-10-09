import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show Heard;
import 'package:flutter3d_particles/flutter3d_particles.dart' show Shown;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show BusEvent;

import 'reaction.dart';

/// A [Reaction] being filled: what the rules of a [ReactionTable] write into.
///
/// Mutable on purpose, and only while one step or one frame is decided:
/// [build] hands out the finished, unchanging [Reaction].
final class ReactionBuilder {
  final List<Shown> bursts = <Shown>[];
  final List<Lingering> lingering = <Lingering>[];
  final List<Felt> jolts = <Felt>[];
  final List<Heard> heard = <Heard>[];
  final List<Haptic> haptics = <Haptic>[];

  /// Set by any rule that wants the screen to flash.
  bool flash = false;

  /// What the game's own rules added — see [add].
  final List<ReactionEffect> effects = <ReactionEffect>[];

  /// Adds [effect], something a reaction does that has no field here: the
  /// way a game's rule says "slow motion" or "rumble" without this package
  /// learning the word.
  void add(ReactionEffect effect) => effects.add(effect);

  /// What was written, as a [Reaction].
  Reaction build() => Reaction(
    bursts: List<Shown>.unmodifiable(bursts),
    lingering: List<Lingering>.unmodifiable(lingering),
    jolts: List<Felt>.unmodifiable(jolts),
    heard: List<Heard>.unmodifiable(heard),
    haptics: List<Haptic>.unmodifiable(haptics),
    flash: flash,
    effects: List<ReactionEffect>.unmodifiable(effects),
  );

  /// Empties it for the next step.
  void clear() {
    bursts.clear();
    lingering.clear();
    jolts.clear();
    heard.clear();
    haptics.clear();
    effects.clear();
    flash = false;
  }
}

/// What one rule of a [ReactionTable] does with an event of type [T].
typedef ReactionRule<T extends BusEvent> =
    void Function(T event, ReactionBuilder out);

/// Reactions keyed by event type: the game's own table of what each event
/// looks and feels like.
///
/// **The game decides; this only keeps the decisions in one place.** A rule
/// is registered for an event class and is handed every event of that class
/// and its subclasses, in the order the events happened; an event no rule
/// names shows nothing. Within one event, rules run in registration order,
/// so a table written as a list reads the way a `switch` over the events did.
///
/// ```dart
/// final table = ReactionTable()
///   ..on<Landed>((e, out) => out.jolts.add(Felt.kick(Vector3(0, -0.1, 0))))
///   ..on<Exploded>((e, out) {
///     out.bursts.add(Shown(Effects.fire, e.at));
///     out.flash = true;
///   });
/// final reaction = table.react(events);
/// ```
final class ReactionTable {
  final List<_Row> _rows = <_Row>[];

  /// Adds [rule] for every event that is a [T].
  void on<T extends BusEvent>(ReactionRule<T> rule) {
    _rows.add(
      _Row(T, (BusEvent event, ReactionBuilder out) {
        if (event is T) rule(event, out);
      }),
    );
  }

  /// The event types this table has a rule for, in registration order.
  List<Type> get types => <Type>[for (final row in _rows) row.type];

  /// Writes what [events] look like into [out].
  void decide(Iterable<BusEvent> events, ReactionBuilder out) {
    for (final event in events) {
      for (final row in _rows) {
        row.apply(event, out);
      }
    }
  }

  /// What [events] look like.
  Reaction react(Iterable<BusEvent> events) {
    final out = ReactionBuilder();
    decide(events, out);
    return out.build();
  }
}

final class _Row {
  const _Row(this.type, this.apply);

  final Type type;
  final void Function(BusEvent event, ReactionBuilder out) apply;
}
