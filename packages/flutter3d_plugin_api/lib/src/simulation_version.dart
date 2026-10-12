/// Which simulation a run was played in, as numbers a build can compare.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show DocumentFormatException;

import 'plugin_version.dart';
import 'simulation_profile.dart';

/// Which simulation a run was played in, or a machine plays: the engine's
/// number, a genre's, and one for every simulation plugin installed.
///
/// **A tape of intents is only a run inside the simulation that recorded
/// it.** The same presses played into a body tuned a little differently
/// arrive somewhere else, and the checkpoints say so at step 300 in a way
/// that reads like a bug. This is the number that lets a build say it at
/// step 0 instead: "recorded on another simulation", before anything is
/// played. Two machines in one match compare it in their hello, and a match
/// is formed only between equal ones.
///
/// ## The promise the numbers carry
///
/// * **A patch never changes the simulation.** A fix that would move a body
///   by a bit waits for a minor, so every tape recorded on 1.2.0 still
///   replays on 1.2.7.
/// * **A minor that changes the simulation bumps the number** that owns the
///   change — [engine] for the step, the physics and the input, [genre]'s for
///   a genre's rules (and [otherGenres]' for the genres beside it), a
///   plugin's own in [plugins], a running solver's in [subsystems]. A minor
///   that leaves them alone keeps them.
/// * The numbers start at 1 with 1.0.0 and only grow.
///
/// **Here, in the plugin API**, because a simulation plugin owns a number of
/// its own (`PluginManifest.simulationVersion`) and a network hello in a
/// package with no engine dependency carries the whole of it.
final class SimulationVersion {
  const SimulationVersion({
    this.engine = engineVersion,
    this.genre,
    this.genreVersion = 1,
    this.otherGenres = const <String, int>{},
    this.plugins = const <String, int>{},
    this.profile = SimulationProfile.deterministic,
    this.subsystems = const <String, int>{},
    this.extra = const <String, Object?>{},
  });

  /// The keys [toJson] writes; [fromJson] keeps any other in [extra].
  static const Set<String> _known = <String>{
    'engine',
    'genre',
    'genreVersion',
    'otherGenres',
    'plugins',
    'profile',
    'subsystems',
  };

  /// The engine's simulation: the fixed step, the input, the physics and
  /// everything in `flutter3d_sim` that moves a body. 1 is 1.0.0's.
  static const int engineVersion = 1;

  /// A game with no genre package of its own: the engine's number alone.
  static const SimulationVersion engineOnly = SimulationVersion();

  /// [engineVersion] when this build wrote it; whatever the file says when
  /// it was read.
  final int engine;

  /// The genre whose rules the run was played by — `'platformer'`,
  /// `'racing'` — or a game's own name when its rules are its own; null for
  /// a game on the engine alone.
  final String? genre;

  /// [genre]'s own number, by the same promise. Meaningless without a genre.
  ///
  /// 0 names a genre's rules from before 1.0.0, which no 1.x build runs: what
  /// a format migrating a pre-1.0 file tags it with, so that the file opens
  /// and its tape is refused with a reason rather than the file with none.
  final int genreVersion;

  /// The genres played beside [genre], by name, each with its own number: an
  /// engine with two genres installed — a racer whose track has a shooter's
  /// turrets — runs both sets of rules, and a tape recorded there replays
  /// only where both are at the same numbers. Empty for one genre or none.
  final Map<String, int> otherGenres;

  /// Every genre the run was played by, [genre] first, with its number.
  Map<String, int> get genres => <String, int>{
    ?genre: genreVersion,
    for (final name in (otherGenres.keys.toList()..sort()))
      name: otherGenres[name]!,
  };

  /// Every simulation plugin that was on, by id, with its own simulation
  /// number. A view plugin changes nothing a step computes and is not here.
  ///
  /// Empty in a file written before plugins had numbers, which is read as
  /// "no plugin was asked about" — see [refusalOn].
  final Map<String, int> plugins;

  /// What the simulation promises about its numbers: the same engine run
  /// under another profile is another simulation, so a tape recorded on
  /// one is refused on the other ([refusalOn]) and two machines on
  /// different profiles never form a match.
  ///
  /// [SimulationProfile.deterministic] unless the loop says otherwise, and
  /// written only when it is another ([toJson]), so a run and a hello of
  /// the default simulation read as they did before there was a second
  /// profile.
  final SimulationProfile profile;

  /// Every subsystem that was running, by id, with its own simulation
  /// number: the solvers registered with the loop's `SubsystemRegistry`
  /// (`flutter3d_fields`) that run under its profile. The simulation is
  /// composed from them, so a solver a minor adds and switches on through a
  /// profile is named here only where it runs.
  ///
  /// Empty for the default simulation, and written only when it is not
  /// ([toJson]), so a run and a hello of it read as they did before there
  /// were subsystems.
  final Map<String, int> subsystems;

  /// Keys a newer build wrote that this one does not know, kept as they
  /// were read and written back.
  ///
  /// **A dimension of the simulation's identity a minor may add.** A newer
  /// build that composes the simulation from something this one has no
  /// field for writes it under a key of its own. Dropping it would read
  /// that simulation as this build's and replay or match across the two;
  /// kept, it is compared by [==] and [refusalOn], so the run or the hello
  /// is refused with the key named rather than silently changed. Empty for
  /// everything this build writes.
  final Map<String, Object?> extra;

  /// What a file written before simulations had numbers is read as: version
  /// 1 of the engine and of whatever genre is [running] — the simulation
  /// 1.0.0 shipped, which is the only one such a file can come from.
  static SimulationVersion firstOf(SimulationVersion running) =>
      SimulationVersion(
        genre: running.genre,
        engine: 1,
        otherGenres: <String, int>{
          for (final name in running.otherGenres.keys) name: 1,
        },
      );

  /// This version with [plugins] in place of its own.
  SimulationVersion withPlugins(Map<String, int> plugins) => SimulationVersion(
    engine: engine,
    genre: genre,
    genreVersion: genreVersion,
    otherGenres: otherGenres,
    plugins: Map<String, int>.unmodifiable(plugins),
    profile: profile,
    subsystems: subsystems,
    extra: extra,
  );

  /// This version run under [profile] instead of its own.
  SimulationVersion withProfile(SimulationProfile profile) => SimulationVersion(
    engine: engine,
    genre: genre,
    genreVersion: genreVersion,
    otherGenres: otherGenres,
    plugins: plugins,
    profile: profile,
    subsystems: subsystems,
    extra: extra,
  );

  /// This version with [subsystems] in place of its own.
  SimulationVersion withSubsystems(Map<String, int> subsystems) =>
      SimulationVersion(
        engine: engine,
        genre: genre,
        genreVersion: genreVersion,
        otherGenres: otherGenres,
        plugins: plugins,
        profile: profile,
        subsystems: Map<String, int>.unmodifiable(subsystems),
        extra: extra,
      );

  /// This version with [name] at [version] played beside [genre] — or as
  /// [genre] itself when there is none yet.
  ///
  /// For a game that installs a second genre into one engine: its loop's
  /// `simulationBase` is the first genre's number `withGenre` the second's,
  /// so a run file and a network hello name both.
  SimulationVersion withGenre(String name, int version) => genre == null
      ? SimulationVersion(
          engine: engine,
          genre: name,
          genreVersion: version,
          plugins: plugins,
          profile: profile,
          subsystems: subsystems,
          extra: extra,
        )
      : SimulationVersion(
          engine: engine,
          genre: genre,
          genreVersion: genreVersion,
          otherGenres: Map<String, int>.unmodifiable(<String, int>{
            ...otherGenres,
            name: version,
          }),
          plugins: plugins,
          profile: profile,
          subsystems: subsystems,
          extra: extra,
        );

  /// "engine 1, platformer 2, fire 3" — the words a refusal uses, and
  /// what a hello and the relay match on. A profile other than
  /// [SimulationProfile.deterministic] is named last ("engine 1, accurate
  /// profile").
  String describe() => <String>[
    'engine $engine',
    if (genre != null) '$genre $genreVersion',
    for (final name in (otherGenres.keys.toList()..sort()))
      '$name ${otherGenres[name]}',
    for (final id in (plugins.keys.toList()..sort())) '$id ${plugins[id]}',
    for (final id in (subsystems.keys.toList()..sort()))
      '$id ${subsystems[id]}',
    if (profile != SimulationProfile.deterministic) '${profile.name} profile',
  ].join(', ');

  Map<String, Object?> toJson() => <String, Object?>{
    'engine': engine,
    if (genre != null) 'genre': genre,
    if (genre != null) 'genreVersion': genreVersion,
    if (otherGenres.isNotEmpty)
      'otherGenres': <String, Object?>{
        for (final name in (otherGenres.keys.toList()..sort()))
          name: otherGenres[name],
      },
    if (plugins.isNotEmpty)
      'plugins': <String, Object?>{
        for (final id in (plugins.keys.toList()..sort())) id: plugins[id],
      },
    if (profile != SimulationProfile.deterministic) 'profile': profile.toJson(),
    if (subsystems.isNotEmpty)
      'subsystems': <String, Object?>{
        for (final id in (subsystems.keys.toList()..sort())) id: subsystems[id],
      },
    for (final MapEntry(:key, :value) in extra.entries)
      if (!_known.contains(key)) key: value,
  };

  /// Reads what [toJson] wrote. A number that is not one is refused with a
  /// [PluginFormatException] rather than guessed: a guessed simulation is a
  /// tape replayed into the wrong one.
  ///
  /// **A profile is read by its name among [profiles]**, this release's
  /// unless a caller adds its own (an outside package's profile). A name
  /// none of them has is a run recorded under a profile this build does not
  /// know: it is read under that name promising nothing (not bit-exact, no
  /// double precision, no adaptive steps), so the file still opens, its
  /// poses still show and nothing verifies it by replay, and it matches a
  /// simulation running a profile of that name, since the name is all the
  /// file says of it ([==], [refusalOn]).
  factory SimulationVersion.fromJson(
    Map<String, Object?> json, {
    Iterable<SimulationProfile> profiles = SimulationProfile.values,
  }) {
    final engine = json['engine'];
    final genre = json['genre'];
    final genreVersion = json['genreVersion'] ?? 1;
    final plugins = json['plugins'] ?? const <String, Object?>{};
    final others = json['otherGenres'] ?? const <String, Object?>{};
    final solvers = json['subsystems'] ?? const <String, Object?>{};
    if (engine is! int || engine < 1) {
      throw PluginFormatException('the simulation names engine $engine', json);
    }
    if (genre != null && (genre is! String || genre.isEmpty)) {
      throw PluginFormatException('the simulation names genre $genre', json);
    }
    if (genreVersion is! int || genreVersion < 0) {
      throw PluginFormatException(
        'the simulation names genre version $genreVersion',
        json,
      );
    }
    if (plugins is! Map) {
      throw PluginFormatException(
        'the simulation\'s plugins are not a map of numbers',
        json,
      );
    }
    final read = <String, int>{};
    for (final MapEntry(:key, :value) in plugins.entries) {
      if (key is! String || value is! int || value < 0) {
        throw PluginFormatException(
          'the simulation names plugin $key at version $value',
          json,
        );
      }
      read[key] = value;
    }
    if (others is! Map) {
      throw PluginFormatException(
        'the simulation\'s other genres are not a map of numbers',
        json,
      );
    }
    final alongside = <String, int>{};
    for (final MapEntry(:key, :value) in others.entries) {
      if (key is! String || key.isEmpty || value is! int || value < 0) {
        throw PluginFormatException(
          'the simulation names genre $key at version $value',
          json,
        );
      }
      alongside[key] = value;
    }
    if (solvers is! Map) {
      throw PluginFormatException(
        'the simulation\'s subsystems are not a map of numbers',
        json,
      );
    }
    final running = <String, int>{};
    for (final MapEntry(:key, :value) in solvers.entries) {
      if (key is! String || key.isEmpty || value is! int || value < 1) {
        throw PluginFormatException(
          'the simulation names subsystem $key at version $value',
          json,
        );
      }
      running[key] = value;
    }
    final SimulationProfile profile;
    try {
      profile = switch (json['profile']) {
        null => SimulationProfile.deterministic,
        final String name
            when name.isNotEmpty &&
                !profiles.any((SimulationProfile p) => p.name == name) =>
          SimulationProfile(
            name,
            isBitExact: false,
            usesDoublePrecision: false,
            allowsAdaptiveSteps: false,
          ),
        final String name => SimulationProfile.parse(name, known: profiles),
        final other => throw DocumentFormatException(
          'the simulation names profile $other',
        ),
      };
    } on DocumentFormatException catch (error) {
      throw PluginFormatException(error.message, json);
    }
    return SimulationVersion(
      engine: engine,
      genre: genre as String?,
      genreVersion: genreVersion,
      otherGenres: Map<String, int>.unmodifiable(alongside),
      plugins: Map<String, int>.unmodifiable(read),
      profile: profile,
      subsystems: Map<String, int>.unmodifiable(running),
      extra: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in json.entries)
          if (!_known.contains(entry.key)) entry.key: entry.value,
      }),
    );
  }

  /// Why a run recorded on this simulation does not replay on [running], or
  /// null when it does.
  ///
  /// Names both sides and which of them is older, because the two answers
  /// ask for different things: an older run is shown as its poses, a newer
  /// one asks for an update. A plugin missing on one side, or at another
  /// number, is named by id.
  String? refusalOn(SimulationVersion running) {
    if (profile.name != running.profile.name) {
      return 'the run was played on the ${profile.name} profile and this '
          'simulation runs the ${running.profile.name} one; the same input '
          'plays out differently here, so it is not replayed';
    }
    // A key this build does not know is a part of the simulation it has no
    // field for, which a newer build wrote: compared as written, and a
    // difference is refused with the key named.
    if (!_sameExtra(extra, running.extra)) {
      final keys = <String>[
        for (final key in <String>{...extra.keys, ...running.extra.keys})
          if (!extra.containsKey(key) ||
              !running.extra.containsKey(key) ||
              !_sameValue(extra[key], running.extra[key]))
            key,
      ]..sort();
      return 'the run and this simulation differ in ${keys.join(', ')}, a '
          'part of the simulation newer than this build — update flutter3d '
          'to replay it';
    }
    if (genre != running.genre ||
        !_sameNames(otherGenres, running.otherGenres)) {
      String rules(SimulationVersion v) =>
          v.genres.isEmpty ? 'the engine alone' : v.genres.keys.join(' and ');
      return 'the run was played by ${rules(this)} rules and '
          'this is ${rules(running)}';
    }
    if (this == running) return null;
    final sameCore =
        engine == running.engine &&
        (genre == null || genreVersion == running.genreVersion) &&
        _samePlugins(otherGenres, running.otherGenres);
    if (sameCore) {
      final missing = <String>[
        for (final id in plugins.keys)
          if (!running.plugins.containsKey(id)) id,
      ]..sort();
      final extra = <String>[
        for (final id in running.plugins.keys)
          if (!plugins.containsKey(id)) id,
      ]..sort();
      if (missing.isNotEmpty) {
        return 'the run was recorded with the simulation plugin'
            '${missing.length == 1 ? '' : 's'} ${missing.join(', ')}, which '
            '${missing.length == 1 ? 'is' : 'are'} not on here';
      }
      if (extra.isNotEmpty) {
        return 'the simulation plugin${extra.length == 1 ? '' : 's'} '
            '${extra.join(', ')} ${extra.length == 1 ? 'is' : 'are'} on here '
            'and ${extra.length == 1 ? 'was' : 'were'} not when the run was '
            'recorded';
      }
      final ids = plugins.keys.toList()..sort();
      for (final id in ids) {
        final was = plugins[id]!;
        final now = running.plugins[id]!;
        if (was == now) continue;
        return _numberRefusal(id, was, now);
      }
      return _subsystemRefusal(running);
    }
    final newer =
        engine > running.engine ||
        (engine == running.engine &&
            (genreVersion > running.genreVersion ||
                otherGenres.entries.any(
                  (e) => e.value > (running.otherGenres[e.key] ?? e.value),
                )));
    return newer
        ? 'the run was recorded on simulation ${describe()}, newer than this '
              'build\'s ${running.describe()} — update flutter3d to replay it'
        : 'the run was recorded on simulation ${describe()}, and this build '
              'runs ${running.describe()}; the same input plays out '
              'differently here, so it is not replayed';
  }

  /// Why a subsystem's number differs between this run and [running], or
  /// null when every one agrees.
  String? _subsystemRefusal(SimulationVersion running) {
    final missing = <String>[
      for (final id in subsystems.keys)
        if (!running.subsystems.containsKey(id)) id,
    ]..sort();
    final extra = <String>[
      for (final id in running.subsystems.keys)
        if (!subsystems.containsKey(id)) id,
    ]..sort();
    if (missing.isNotEmpty) {
      return 'the run was recorded with the subsystem'
          '${missing.length == 1 ? '' : 's'} ${missing.join(', ')} running, '
          'which ${missing.length == 1 ? 'is' : 'are'} not running here';
    }
    if (extra.isNotEmpty) {
      return 'the subsystem${extra.length == 1 ? '' : 's'} '
          '${extra.join(', ')} ${extra.length == 1 ? 'is' : 'are'} running '
          'here and ${extra.length == 1 ? 'was' : 'were'} not when the run '
          'was recorded';
    }
    for (final id in subsystems.keys.toList()..sort()) {
      final was = subsystems[id]!;
      final now = running.subsystems[id]!;
      if (was != now) return _numberRefusal(id, was, now);
    }
    return null;
  }

  static String _numberRefusal(String id, int was, int now) => was > now
      ? 'the run was recorded on $id $was, newer than this build\'s '
            '$now — update $id to replay it'
      : 'the run was recorded on $id $was, and this build runs $id '
            '$now; the same input plays out differently here, so it is '
            'not replayed';

  @override
  bool operator ==(Object other) =>
      other is SimulationVersion &&
      other.engine == engine &&
      // By name, as the profile is written: a run read under a profile this
      // build does not know carries its name and nothing else.
      other.profile.name == profile.name &&
      other.genre == genre &&
      (genre == null || other.genreVersion == genreVersion) &&
      _samePlugins(other.otherGenres, otherGenres) &&
      _samePlugins(other.plugins, plugins) &&
      _samePlugins(other.subsystems, subsystems) &&
      _sameExtra(other.extra, extra);

  static bool _sameExtra(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every(
        (entry) =>
            b.containsKey(entry.key) && _sameValue(entry.value, b[entry.key]),
      );

  /// Whether two values read from JSON are the same: maps by their entries,
  /// lists by their items, in order.
  static bool _sameValue(Object? a, Object? b) => switch ((a, b)) {
    (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
      a.length == b.length &&
          a.entries.every(
            (e) => b.containsKey(e.key) && _sameValue(e.value, b[e.key]),
          ),
    (final List<Object?> a, final List<Object?> b) =>
      a.length == b.length &&
          <int>[
            for (var i = 0; i < a.length; i++) i,
          ].every((i) => _sameValue(a[i], b[i])),
    _ => a == b,
  };

  static bool _sameNames(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.keys.every(b.containsKey);

  static bool _samePlugins(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);

  @override
  int get hashCode => Object.hash(
    engine,
    profile.name,
    genre,
    genre == null ? 0 : genreVersion,
    Object.hashAllUnordered(<Object>[
      for (final entry in otherGenres.entries)
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered(<Object>[
      for (final entry in plugins.entries) Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered(<Object>[
      for (final entry in subsystems.entries)
        Object.hash(entry.key, entry.value),
    ]),
    // By key only: equal versions have equal keys, and a value read from
    // JSON has no hash of its contents.
    Object.hashAllUnordered(extra.keys),
  );

  @override
  String toString() => 'SimulationVersion(${describe()})';
}
