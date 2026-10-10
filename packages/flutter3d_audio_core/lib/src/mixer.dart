import 'bus_effect.dart';
import 'mix_snapshot.dart';
import 'units.dart';

/// A group of sounds that a player can turn down as one.
///
/// Open the same way `GameAction` is, and for the same reason: the three below
/// are what every settings screen has ever shown, and a game with dialogue or
/// with a separate slider for footsteps declares its own without asking.
final class AudioBus {
  const AudioBus(this.name);

  final String name;

  /// Everything, and the slider labelled "volume".
  static const AudioBus master = AudioBus('master');

  static const AudioBus music = AudioBus('music');

  /// Everything that is not music. The default for a [SoundDef].
  static const AudioBus sfx = AudioBus('sfx');

  @override
  bool operator ==(Object other) => other is AudioBus && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'AudioBus($name)';
}

/// What each bus is turned to, and the one place a volume setting lives.
///
/// ## Why a bus is not part of being audible
///
/// The gain here is applied when a voice is handed to the backend, and
/// **deliberately not** when the mixer decides which sounds get voices at all.
/// Those are two different questions wearing one word:
///
/// * *Can it be heard from there* — distance, occlusion, priority. That decides
///   who gets one of the few voices a device has.
/// * *How loud has the player asked for this kind of thing to be* — this.
///
/// Fold the second into the first and turning the music down lets a distant
/// footstep take the voice the music was holding; turn it back up and the track
/// restarts from the beginning, because its voice was stopped while nobody was
/// listening. Keeping them apart means a muted bus is silent and still playing,
/// which is what a player expects from a slider.
///
/// ## The mix beside the sliders
///
/// A bus has three things on it, applied in this order, and only the first
/// is a setting:
///
/// * **its volume** — the player's slider, linear, in `[0, 1]`, saved with
///   [toJson];
/// * **its level** — decibels the game's mix adds while it runs: the
///   [MixSnapshot]s it is in and the [DuckRule]s that fire ([levelOf]);
/// * **its effects** — up to [effectSlots] a game puts on it with
///   [setEffect], and those its snapshots bring ([effectsOf]).
///
/// **Buses form a tree.** Each routes into a parent, [AudioBus.master] by
/// default, and a sound is played at the product of its bus's gain and every
/// ancestor's ([setParent]). Nothing of this is in the way of a game that
/// uses none of it: with no parents set, no snapshot in, no rule and no
/// effect, [gainFor] is exactly what it was — bus times master.
///
/// Snapshots blend and ducks move only when [advance] is called with the
/// seconds that passed; `AudioScene.update` does it once a mix.
final class Mixer {
  Mixer([Map<AudioBus, double>? volumes]) {
    if (volumes != null) {
      for (final entry in volumes.entries) {
        setVolume(entry.key, entry.value);
      }
    }
  }

  factory Mixer.fromJson(Map<String, Object?> json) {
    final mixer = Mixer();
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is num) mixer.setVolume(AudioBus(entry.key), value.toDouble());
    }
    return mixer;
  }

  final Map<AudioBus, double> _volumes = <AudioBus, double>{};

  /// What [bus] is set to, in `[0, 1]`. Unset buses are full.
  ///
  /// Full rather than silent, so that a game which declares a `dialogue` bus
  /// and forgets to configure it can still be heard. A settings file that has
  /// never been written must not mute anything.
  double volumeOf(AudioBus bus) => _volumes[bus] ?? 1.0;

  void setVolume(AudioBus bus, double volume) =>
      _volumes[bus] = volume.clamp(0.0, 1.0);

  /// The gain a sound on [bus] is actually played at, linear.
  ///
  /// The bus and every bus it routes into multiplied — by default the bus
  /// and the master. Master is not a special case in the table — it is an
  /// ordinary bus that everything is also on. Each bus's [levelOf] is
  /// applied with its volume; with no snapshot in and no duck firing, that
  /// is exactly one.
  double gainFor(AudioBus bus) {
    var gain = 1.0;
    // A loop rather than [_chain]: this runs for every voice every mix.
    for (AudioBus? at = bus; at != null; at = parentOf(at)) {
      gain *= ownGainOf(at);
    }
    return gain;
  }

  /// The gain [bus] applies itself, linear: its volume and its level, and
  /// none of its parents'. What a backend that mixes the tree itself is
  /// handed for each bus.
  double ownGainOf(AudioBus bus) {
    final level = _levels[bus];
    final volume = volumeOf(bus);
    return level == null ? volume : volume * decibelsToGain(level);
  }

  /// The buses somebody has actually set, for a settings screen to list.
  Iterable<AudioBus> get configured => _volumes.keys;

  // ---------------------------------------------------------------- routing

  final Map<AudioBus, AudioBus> _parents = <AudioBus, AudioBus>{};

  /// The bus [bus] routes into: [AudioBus.master] unless [setParent] said
  /// otherwise, and null for the master itself.
  AudioBus? parentOf(AudioBus bus) =>
      bus == AudioBus.master ? null : (_parents[bus] ?? AudioBus.master);

  /// Routes [bus] into [parent], so that turning [parent] down turns [bus]
  /// down with it: a `dialogue` bus under `sfx`, footsteps under `foley`.
  ///
  /// Throws an [ArgumentError] for the master, which routes nowhere, and for
  /// a route that would make a loop.
  void setParent(AudioBus bus, AudioBus parent) {
    if (bus == AudioBus.master) {
      throw ArgumentError.value(bus, 'bus', 'the master routes nowhere');
    }
    for (AudioBus? at = parent; at != null; at = parentOf(at)) {
      if (at == bus) {
        throw ArgumentError.value(
          parent,
          'parent',
          '${bus.name} would route into itself',
        );
      }
    }
    _parents[bus] = parent;
  }

  /// [bus], then each bus it routes into, ending at the master.
  Iterable<AudioBus> _chain(AudioBus bus) sync* {
    for (AudioBus? at = bus; at != null; at = parentOf(at)) {
      yield at;
    }
  }

  /// Whether sound on [bus] passes through [through] on its way out —
  /// including when they are the same bus.
  bool routesThrough(AudioBus bus, AudioBus through) =>
      _chain(bus).contains(through);

  // ---------------------------------------------------------------- effects

  /// How many effects a game may put on one bus. Snapshots bring their own
  /// beside these and take none of them.
  static const int effectSlots = 4;

  final Map<AudioBus, List<BusEffect?>> _slots = <AudioBus, List<BusEffect?>>{};

  /// Puts [effect] in [slot] of [bus], or clears the slot with null.
  ///
  /// Throws a [RangeError] for a slot outside `[0, effectSlots)`.
  void setEffect(AudioBus bus, int slot, BusEffect? effect) {
    RangeError.checkValidIndex(slot, null, 'slot', effectSlots);
    (_slots[bus] ??= List<BusEffect?>.filled(effectSlots, null))[slot] = effect;
  }

  /// What is in [slot] of [bus], or null.
  BusEffect? effectIn(AudioBus bus, int slot) {
    RangeError.checkValidIndex(slot, null, 'slot', effectSlots);
    return _slots[bus]?[slot];
  }

  /// Every effect on [bus] now: its slots in order, then what the snapshots
  /// in bring, each at the weight its snapshot has reached. Not its
  /// parents'.
  List<BusEffect> effectsOf(AudioBus bus) => <BusEffect>[
    ...?_slots[bus]?.whereType<BusEffect>(),
    ...?_snapshotEffects[bus],
  ];

  /// How dull a voice on [bus] is made by the low-pass effects on it and on
  /// every bus it routes through, from 0 (clear) to 1: the strongest of
  /// them. Nought when there are none.
  double muffleFor(AudioBus bus) {
    var muffle = 0.0;
    if (_slots.isEmpty && _snapshotEffects.isEmpty) return muffle;
    for (final through in _chain(bus)) {
      for (final effect in effectsOf(through)) {
        if (effect is LowPassEffect && effect.muffle > muffle) {
          muffle = effect.muffle;
        }
      }
    }
    return muffle;
  }

  // -------------------------------------------------------------- snapshots

  final List<_InSnapshot> _snapshots = <_InSnapshot>[];

  /// Begins blending [snapshot] in over its [MixSnapshot.blendInSeconds].
  ///
  /// Entering one already in, or on its way out, turns it round from where
  /// it is, with this definition replacing the old one; one with no blend
  /// time is in at once, before the next [advance].
  void enterSnapshot(MixSnapshot snapshot) {
    final at = _snapshots.indexWhere((s) => s.snapshot.name == snapshot.name);
    final entry = at < 0 ? _InSnapshot(snapshot) : _snapshots[at];
    if (at < 0) _snapshots.add(entry);
    entry
      ..snapshot = snapshot
      ..entering = true;
    if (snapshot.blendInSeconds <= 0.0) entry.weight = 1.0;
    _recompute();
  }

  /// Begins blending the snapshot called [name] out over its
  /// [MixSnapshot.blendOutSeconds]. A name not in is ignored.
  void leaveSnapshot(String name) {
    for (final entry in _snapshots) {
      if (entry.snapshot.name != name) continue;
      entry.entering = false;
      if (entry.snapshot.blendOutSeconds <= 0.0) entry.weight = 0.0;
    }
    _snapshots.removeWhere((s) => !s.entering && s.weight <= 0.0);
    _recompute();
  }

  /// The names of the snapshots in, or on their way in or out, in the order
  /// they were entered.
  List<String> get snapshots => <String>[
    for (final entry in _snapshots) entry.snapshot.name,
  ];

  /// How far the snapshot called [name] is in, from 0 (not at all) to 1.
  double snapshotWeight(String name) {
    for (final entry in _snapshots) {
      if (entry.snapshot.name == name) return entry.weight;
    }
    return 0.0;
  }

  // ---------------------------------------------------------------- ducking

  final List<_Duck> _ducks = <_Duck>[];

  /// Adds [rule]. The same rule added twice ducks twice.
  void addDucking(DuckRule rule) => _ducks.add(_Duck(rule));

  /// Removes [rule]; its duck is let go at once.
  void removeDucking(DuckRule rule) {
    final at = _ducks.indexWhere((d) => identical(d.rule, rule));
    if (at >= 0) _ducks.removeAt(at);
    _recompute();
  }

  /// The rules added, in order.
  List<DuckRule> get duckings => <DuckRule>[
    for (final duck in _ducks) duck.rule,
  ];

  /// How far [rule] is ducking its target now, from 0 to 1 of its depth.
  double duckingOf(DuckRule rule) {
    for (final duck in _ducks) {
      if (identical(duck.rule, rule)) return duck.amount;
    }
    return 0.0;
  }

  // -------------------------------------------------------------- the clock

  final Map<AudioBus, double> _levels = <AudioBus, double>{};
  final Map<AudioBus, List<BusEffect>> _snapshotEffects =
      <AudioBus, List<BusEffect>>{};

  /// The decibels the mix adds to [bus] now, from its snapshots and the
  /// ducks on it: nought when nothing does. Not its parents'.
  double levelOf(AudioBus bus) => _levels[bus] ?? 0.0;

  /// Moves the mix on by [seconds]: snapshots blend, ducks attack and
  /// release.
  ///
  /// [activity] is how loud each bus's loudest voice was in the last mix,
  /// as linear audible gain, which is what a [DuckRule] listens to;
  /// `AudioScene.update` hands over its own. Seconds that are not a positive
  /// finite number move nothing.
  void advance(
    double seconds, {
    Map<AudioBus, double> activity = const <AudioBus, double>{},
  }) {
    final dt = seconds.isFinite && seconds > 0.0 ? seconds : 0.0;
    for (final entry in _snapshots) {
      entry.weight = _toward(
        entry.weight,
        entry.entering ? 1.0 : 0.0,
        dt,
        entry.entering
            ? entry.snapshot.blendInSeconds
            : entry.snapshot.blendOutSeconds,
      );
    }
    _snapshots.removeWhere((s) => !s.entering && s.weight <= 0.0);
    for (final duck in _ducks) {
      final rule = duck.rule;
      final threshold = decibelsToGain(rule.thresholdDecibels);
      final heard = activity.entries.any(
        (e) => e.value > threshold && routesThrough(e.key, rule.trigger),
      );
      duck.amount = _toward(
        duck.amount,
        heard ? 1.0 : 0.0,
        dt,
        heard ? rule.attackSeconds : rule.releaseSeconds,
      );
    }
    _recompute();
  }

  /// [from] moved toward [to] at a whole unit per [over] seconds.
  static double _toward(double from, double to, double dt, double over) {
    if (over <= 0.0) return to;
    final step = dt / over;
    return from < to
        ? (from + step > to ? to : from + step)
        : (from - step < to ? to : from - step);
  }

  void _recompute() {
    _levels.clear();
    _snapshotEffects.clear();
    for (final entry in _snapshots) {
      final weight = entry.weight;
      if (weight <= 0.0) continue;
      for (final level in entry.snapshot.levels.entries) {
        // Floored so that a fade to silence passes through every level on
        // the way rather than being −∞ from its first frame.
        final db = level.value < silenceDecibels
            ? silenceDecibels
            : level.value;
        _levels[level.key] = (_levels[level.key] ?? 0.0) + db * weight;
      }
      for (final bus in entry.snapshot.effects.entries) {
        for (final effect in bus.value) {
          final weighted = effect.atWeight(weight);
          if (weighted != null) {
            (_snapshotEffects[bus.key] ??= <BusEffect>[]).add(weighted);
          }
        }
      }
    }
    for (final duck in _ducks) {
      if (duck.amount <= 0.0) continue;
      final target = duck.rule.target;
      _levels[target] =
          (_levels[target] ?? 0.0) + duck.rule.depthDecibels * duck.amount;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    for (final name
        in _volumes.keys.map((AudioBus b) => b.name).toList()..sort())
      name: volumeOf(AudioBus(name)),
  };
}

/// A snapshot in the mix: how far in it is, and which way it is going.
final class _InSnapshot {
  _InSnapshot(this.snapshot);

  MixSnapshot snapshot;

  /// How far in it is, a 0..1 fraction of the full snapshot.
  double weight = 0.0;
  bool entering = true;
}

/// A rule and how far it is ducking, from 0 to 1 of its depth.
final class _Duck {
  _Duck(this.rule);

  final DuckRule rule;

  /// How far it is ducking, a 0..1 fraction of the rule's depth.
  double amount = 0.0;
}
