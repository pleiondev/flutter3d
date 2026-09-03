/// One circuit: a spline to drive and the scenery around it.
///
/// The two files are one document, split by the generator — see
/// `tool/make_track.py`. The names are derived rather than written twice
/// because they were written twice, as two constants at the top of `main.dart`,
/// and a game with one track can afford that exactly until it has two.
final class Circuit {
  const Circuit({required this.name, required this.title});

  /// What the generator calls it, and what the files are named after.
  final String name;

  /// What a player is told they are driving.
  final String title;

  String get track => 'assets/tracks/$name.json';

  String get level => 'assets/tracks/${name}_level.json';
}

/// The circuits, in the order they are raced.
///
/// **A chain, which this game did not have and the other two did.** The
/// platformer and the crypt both move a player from one level to the next and
/// keep where they got to; racing had a single `const` asset path and no idea
/// that anything ever ended. Two circuits is the smallest number that makes the
/// difference visible — and the second one is not a variant of the first: it is
/// tighter, hillier, narrower and raced at a different hour.
///
/// **Why this is not a `RunSession`.** The other two games load a level,
/// snapshot it, restore it and move on, and `flutter3d_session` holds that shape
/// for them. A season is the same idea with the middle taken out: nobody resumes
/// a race half a lap in, so `snapshotOf` and `restoreInto` would be two required
/// overrides returning nothing — ceremony that reads as a feature. What is
/// actually kept between launches is the best lap, one line of its own file —
/// and not which circuit: a season is one sitting, and every launch starts it
/// at the first circuit. It used to be saved, and the effect was a game that
/// opened on the second circuit for anyone who had ever won the first.
///
/// That does not mean this screen went back to `setState`. It has its own
/// cubit — see `RaceProgress` and `RaceCubit` in `race_cubit.dart` — built
/// around exactly the three transitions a season needs: a circuit is up, a
/// circuit was won and something (or nothing) comes after it, and the next one
/// is now being read. `RunSession`'s five methods and two required overrides
/// would have been three of them answering nothing, which is what this file
/// argues against above; a bespoke, three-transition class answering only what
/// a season actually asks is not that.
abstract final class Season {
  static const List<Circuit> circuits = <Circuit>[
    Circuit(name: 'ring', title: 'The Ring'),
    Circuit(name: 'gorge', title: 'The Gorge'),
  ];

  static Circuit get first => circuits.first;

  /// What is raced after [circuit], or null when the season is over.
  static Circuit? after(Circuit circuit) {
    final at = circuits.indexWhere((Circuit c) => c.name == circuit.name);
    if (at < 0 || at + 1 >= circuits.length) return null;
    return circuits[at + 1];
  }
}
