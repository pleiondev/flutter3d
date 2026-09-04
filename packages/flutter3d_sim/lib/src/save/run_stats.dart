import '../loop/game_event.dart';
import 'tally.dart';

/// What a run came to, counted off the events it produced.
///
/// **The results screen every game wrote by hand.** Three applications counted
/// kills, coins and laps, each in its own field, each cleared in its own place
/// and each wrong in its own way — a count that carried between levels, a
/// count reset by a restart that should have survived, a count nothing ever
/// showed. What they had in common was that every one of them was reading the
/// same thing: how many of a kind of moment happened.
///
/// So this counts events. A genre hands it what a step reported and it adds up
/// what it recognises — which is nothing until a game says what to recognise,
/// because a template that knew `ShotFired` would be a template that knew about
/// weapons.
///
/// **Named counters rather than fields**, which is the same reading [Tally]
/// takes: a game that counts something this package never heard of adds a line
/// rather than a class.
final class RunStats {
  RunStats({Map<String, bool Function(GameEvent)>? counting})
    : _counting = <String, bool Function(GameEvent)>{...?counting};

  /// What each counter is looking for, by the name it counts under.
  final Map<String, bool Function(GameEvent)> _counting;

  /// The counts themselves, which are also what a results screen reads.
  final Tally tally = Tally();

  /// How long the run has been going, in simulated seconds.
  ///
  /// **Simulated rather than wall clock**, for the reason every clock in this
  /// repository is: a run timed against the wall is a run whose record depends
  /// on the machine it was set on.
  double elapsed = 0.0;

  /// Starts counting [name] whenever [matches] answers yes.
  ///
  /// ```dart
  /// stats.count('kills', (GameEvent e) => e is ActorDied);
  /// ```
  ///
  /// A game may add counters mid-run; what has already been counted stays.
  void count(String name, bool Function(GameEvent) matches) =>
      _counting[name] = matches;

  /// Adds up [events] and advances the clock by [dt].
  ///
  /// Called once a step with what that step reported, which is the same list
  /// everything else reads — so a counter cannot disagree with a sound about
  /// whether something happened.
  void advance(double dt, List<GameEvent> events) {
    elapsed += dt;
    if (events.isEmpty || _counting.isEmpty) return;
    for (final GameEvent event in events) {
      for (final MapEntry<String, bool Function(GameEvent)> counter
          in _counting.entries) {
        if (counter.value(event)) tally.add(counter.key);
      }
    }
  }

  /// Forgets the counts and the clock, for a run starting over.
  ///
  /// **Not the counters themselves**, which are how a game is configured
  /// rather than what it has done — clearing those would be a results screen
  /// that stops counting after the first restart.
  void clear() {
    tally.clear();
    elapsed = 0.0;
  }

  Map<String, Object?> save() => <String, Object?>{
    'elapsed': elapsed,
    'tally': tally.save(),
  };

  void restore(Map<String, Object?> from) {
    elapsed = (from['elapsed'] as num?)?.toDouble() ?? 0.0;
    final counts = from['tally'];
    if (counts is Map) tally.restore(counts.cast<String, Object?>());
  }
}
