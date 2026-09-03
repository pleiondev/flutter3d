import 'package:flutter3d_app/flutter3d_app.dart'; // Storage, from flutter3d_screens

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
/// that anything ever ended. Two circuits was the smallest number that made
/// the difference visible; five is a season. None of them is a variant of
/// another — see the notes on each in `tool/make_track.py` — and they are
/// ordered so that the last is the hardest, which is what a season is for.
///
/// **Why this is not a `RunSession`.** The other two games load a level,
/// snapshot it, restore it and move on, and `flutter3d_session` holds that shape
/// for them. A season is the same idea with the middle taken out: nobody resumes
/// a race half a lap in, so `snapshotOf` and `restoreInto` would be two required
/// overrides returning nothing — ceremony that reads as a feature. What is
/// actually kept between launches is which circuit and which best lap, and both
/// are one line of their own file.
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
    Circuit(name: 'flats', title: 'The Flats'),
    Circuit(name: 'quarry', title: 'The Quarry'),
    Circuit(name: 'ridge', title: 'The Ridge'),
  ];

  static Circuit get first => circuits.first;

  /// What is raced after [circuit], or null when the season is over.
  static Circuit? after(Circuit circuit) {
    final at = circuits.indexWhere((Circuit c) => c.name == circuit.name);
    if (at < 0 || at + 1 >= circuits.length) return null;
    return circuits[at + 1];
  }

  /// The circuit called [name], or null — which is what a saved progress file
  /// naming a circuit this build no longer ships resolves to.
  static Circuit? named(String name) {
    for (final circuit in circuits) {
      if (circuit.name == name) return circuit;
    }
    return null;
  }
}

/// How far into the season somebody has got, kept between launches.
///
/// One line of a document rather than a field of a bigger one, for the same
/// reason the ghost is its own file: a run is lost when the game cannot read
/// its own save, and the less each file has to say the less there is to lose.
final class SeasonProgress {
  SeasonProgress({required this.storage});

  final Storage storage;

  static const String _name = 'season.json';

  /// Where to start. The first circuit when there is nothing saved, when the
  /// file is unreadable, or when it names a circuit this build does not have.
  Circuit read() {
    final text = storage.read(_name);
    if (text == null) return Season.first;
    return Season.named(text.trim()) ?? Season.first;
  }

  /// Remembers that [circuit] is where the player is now.
  void reached(Circuit circuit) => storage.write(_name, circuit.name);

  /// Forgets it. The season starts again.
  void clear() => storage.remove(_name);
}
