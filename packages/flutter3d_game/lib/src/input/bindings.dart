import 'game_action.dart';

/// Something on a device that can be bound: a key, a mouse button, a pad's face
/// button.
///
/// A string rather than a type per device, and the reason is the file it gets
/// saved to. A rebinding a player made has to survive being written down and
/// read back a week later on a different build, so what is written down must be
/// stable and self-describing — `key:107` and `pad:a`, not an index into
/// whatever order a device happened to enumerate in.
///
/// The prefix is a convention, not a rule this class enforces: it has no idea
/// what devices exist, and adding one is a backend translating its own events
/// into ids rather than an edit here.
final class InputSource {
  const InputSource(this.id);

  /// A keyboard key, by Flutter's stable `LogicalKeyboardKey.keyId`.
  ///
  /// The id and not the debug name: names are for people and have changed
  /// between SDK versions, which would silently unbind everything.
  factory InputSource.key(int keyId) => InputSource('key:$keyId');

  /// A mouse button, by its usual number: 0 primary, 1 secondary.
  factory InputSource.pointer(int button) => InputSource('pointer:$button');

  /// A gamepad button, by a name the backend chooses and keeps.
  factory InputSource.pad(String button) => InputSource('$padPrefix$button');

  /// What a gamepad's ids start with.
  ///
  /// Named because two places have to agree on it: what [InputSource.pad]
  /// writes, and how a game asks whether a saved table mentions a pad at all —
  /// see `PadInput.knowsPad`. Spelling it twice is how one of them drifts.
  static const String padPrefix = 'pad:';

  final String id;

  @override
  bool operator ==(Object other) => other is InputSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'InputSource($id)';
}

/// What each thing on a device does, and the only place that answers it.
///
/// Two properties it has to have, and both come from the same requirement —
/// that a player can change this and keep the change:
///
/// * **Many sources, one action.** `W` and the up arrow both walk forward, and
///   a pad's stick and the keyboard have to coexist rather than replace each
///   other.
/// * **Round-trips as text.** [toJson] and [Bindings.fromJson] are how the
///   change survives the process, and they name actions and sources rather
///   than numbering them, so a saved file read by a later build with more
///   actions in it still means what it said.
///
/// Unknown names read back are **kept, not dropped**. A config written by a
/// build that had a `grapple` and read by one that does not should still have
/// its grapple when the feature comes back, and a reader that silently prunes
/// what it does not recognise is a reader that quietly destroys the file every
/// time it loads it.
final class Bindings {
  Bindings([Map<InputSource, GameAction>? initial]) {
    if (initial != null) _sources.addAll(initial);
  }

  /// Reads a table written by [toJson].
  ///
  /// Shaped as action name to a list of source ids, because that is the shape a
  /// rebinding screen reads — "what is jump bound to" — and a file a person may
  /// open should be arranged the way a person would ask.
  factory Bindings.fromJson(Map<String, Object?> json) {
    final bindings = Bindings();
    for (final entry in json.entries) {
      final sources = entry.value;
      if (sources is! List) continue;
      final action = GameAction(entry.key);
      for (final source in sources) {
        if (source is String) bindings.bind(InputSource(source), action);
      }
    }
    return bindings;
  }

  final Map<InputSource, GameAction> _sources = <InputSource, GameAction>{};

  /// What [source] does, or null if it does nothing.
  GameAction? operator [](InputSource source) => _sources[source];

  /// Points [source] at [action], replacing whatever it did before.
  void bind(InputSource source, GameAction action) =>
      _sources[source] = action;

  void unbind(InputSource source) => _sources.remove(source);

  /// Every source bound to anything.
  ///
  /// For asking what kind of device a saved table knows about, which is how a
  /// config written before a device existed gets that device's defaults added
  /// without throwing away the player's own rebindings.
  Iterable<InputSource> get sources => _sources.keys;

  /// Everything currently bound to [action], for a screen that lists them.
  Iterable<InputSource> sourcesFor(GameAction action) => _sources.entries
      .where((MapEntry<InputSource, GameAction> e) => e.value == action)
      .map((MapEntry<InputSource, GameAction> e) => e.key);

  /// Frees every source pointing at [action].
  ///
  /// What a rebinding screen calls before binding the key the player just
  /// pressed, when it means "use this instead" rather than "use this as well".
  void clearAction(GameAction action) =>
      _sources.removeWhere((_, GameAction bound) => bound == action);

  int get length => _sources.length;

  Bindings copy() => Bindings(Map<InputSource, GameAction>.of(_sources));

  Map<String, Object?> toJson() {
    final byAction = <String, List<String>>{};
    for (final entry in _sources.entries) {
      (byAction[entry.value.name] ??= <String>[]).add(entry.key.id);
    }
    // Sorted so that saving twice without touching anything produces the same
    // bytes; a config file whose diff is noise is a config file nobody reviews.
    for (final list in byAction.values) {
      list.sort();
    }
    return <String, Object?>{
      for (final name in byAction.keys.toList()..sort()) name: byAction[name],
    };
  }
}
