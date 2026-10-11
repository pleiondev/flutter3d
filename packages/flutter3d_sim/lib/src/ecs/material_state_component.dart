import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// What the material of one entity's body is like now — hot, wet, half
/// charred — as a component: a [MaterialState] on the entity.
///
/// **The material stays the reference.** A `PhysicalMaterial` is `const`
/// and says what oak is; this says what this plank of it is, and a
/// property's law reads it (`PropertyLaw.at`). A body with no component is
/// at the material's reference state.
///
/// **Every quantity is kept, the ones nobody here knows included.** A
/// plugin's quantity (`<pluginId>.charring`) goes through a save, a
/// snapshot and the wire to a view whether or not the plugin is installed
/// where it is read, as a format keeps the fields it does not know. One
/// this build cannot even read — a unit it has no name for, a shape a later
/// version writes — is kept as it was written ([unread]) and written back
/// untouched, beside the ones it could. Setting a quantity of that id
/// ([withState]) replaces it.
///
/// Registered on every `EngineLoop`'s world, and published to the view, as
/// [codec].
final class MaterialStateComponent {
  /// [state] on an entity.
  const MaterialStateComponent(this.state)
    : unread = const <String, Object?>{},
      _unknownFields = const <String, Object?>{};

  const MaterialStateComponent._(this.state, this.unread, this._unknownFields);

  /// What the body's material is like now.
  final MaterialState state;

  /// The quantities this build could not read, by id, as they were
  /// written: kept and written back so a later version's or a plugin's
  /// survive a build that does not understand them.
  final Map<String, Object?> unread;

  /// Fields beside `quantities` and `phase` that a later version wrote,
  /// kept for the same reason.
  final Map<String, Object?> _unknownFields;

  /// This component holding [state] instead, with what it could not read
  /// kept but for the ids [state] now gives values to.
  MaterialStateComponent withState(MaterialState state) =>
      MaterialStateComponent._(
        state,
        Map<String, Object?>.unmodifiable(<String, Object?>{
          for (final MapEntry(:key, :value) in unread.entries)
            if (!state.quantities.containsKey(key)) key: value,
        }),
        _unknownFields,
      );

  /// The component's codec: `{"quantities": {id: {"value", "unit"}, …},
  /// "phase": …}`, as `MaterialState.toJson` writes it, ids in sorted order
  /// with the [unread] ones among them where they sort.
  static final ComponentCodec<MaterialStateComponent> codec =
      ComponentCodec<MaterialStateComponent>.of(
        id: 'flutter3d.materialState',
        encode: (component) => component._toJson(),
        decode: (data, _) => switch (data) {
          final Map<Object?, Object?> json => _fromJson(json),
          _ => null,
        },
      );

  Map<String, Object?> _toJson() {
    final known = state.toJson();
    final quantities = <String, Object?>{
      ...known['quantities']! as Map<String, Object?>,
      ...unread,
    };
    return <String, Object?>{
      ..._unknownFields,
      'quantities': <String, Object?>{
        for (final id in quantities.keys.toList()..sort()) id: quantities[id],
      },
      if (known['phase'] case final Object phase) 'phase': phase,
    };
  }

  /// Reads [json] a quantity at a time, so one this build cannot read is
  /// kept as written rather than costing the rest. Null for a document that
  /// is not a state at all: an id that is not `<namespace>.<name>`, or a
  /// phase that is not a word.
  static MaterialStateComponent? _fromJson(Map<Object?, Object?> json) {
    final quantities = switch (json['quantities']) {
      null => const <Object?, Object?>{},
      final Map<Object?, Object?> map => map,
      _ => null,
    };
    if (quantities == null) return null;
    final read = <String, Object?>{};
    final unread = <String, Object?>{};
    for (final MapEntry(:key, :value) in quantities.entries) {
      if (key is! String) return null;
      try {
        MaterialState.fromJson(<String, Object?>{
          'quantities': <String, Object?>{key: value},
        });
        read[key] = value;
      } on MaterialFormatException {
        try {
          MaterialState.checkedQuantityId(key);
        } on MaterialFormatException {
          return null;
        }
        unread[key] = value;
      }
    }
    final MaterialState state;
    try {
      state = MaterialState.fromJson(<String, Object?>{
        'quantities': read,
        'phase': ?json['phase'],
      });
    } on MaterialFormatException {
      return null;
    }
    return MaterialStateComponent._(
      state,
      Map<String, Object?>.unmodifiable(unread),
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && key != 'quantities' && key != 'phase')
            key: value,
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MaterialStateComponent &&
      other.state == state &&
      _sameJson(other.unread, unread) &&
      _sameJson(other._unknownFields, _unknownFields);

  @override
  int get hashCode => Object.hash(state, Object.hashAllUnordered(unread.keys));

  static bool _sameJson(Object? a, Object? b) => switch ((a, b)) {
    (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
      x.length == y.length &&
          x.keys.every((k) => y.containsKey(k) && _sameJson(x[k], y[k])),
    (final List<Object?> x, final List<Object?> y) =>
      x.length == y.length &&
          <int>[
            for (var i = 0; i < x.length; i++) i,
          ].every((i) => _sameJson(x[i], y[i])),
    _ => a == b,
  };

  @override
  String toString() => unread.isEmpty
      ? 'MaterialStateComponent($state)'
      : 'MaterialStateComponent($state, unread: ${unread.keys.join(', ')})';
}
