/// What a body of a material is like right now: its temperature, its
/// pressure, its phase and whatever else a law or a plugin follows.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Quantity, Unit, UnitFormatException;

import '../standard_world.dart';
import 'material_json.dart';
import 'physical_material.dart';

/// The state one body of a material is in: an open set of quantities, each
/// under a namespaced id, and the phase it is in.
///
/// **The material is the reference; this is the body.** A
/// [PhysicalMaterial] is `const` and says what a substance is at its
/// reference state. What a particular plank or puddle is like now — hot,
/// wet, half charred — is a `MatterState`, which a property's law reads
/// (`PropertyLaw.at`) to give the value there.
///
/// **An open map, not a list of fields.** Each quantity is a [Quantity]
/// under an id `<namespace>.<name>`: `f3d.temperature`, `f3d.pressure`,
/// `f3d.wetness` for the engine's, `<pluginId>.charring` for a plugin's. A
/// quantity a later minor or a plugin adds is one more key, and a state that
/// holds one this build does not know keeps it through [toJson] and
/// [MatterState.fromJson] untouched, as a format keeps unknown fields.
///
/// **Immutable, and compared by value**, so a component can hold one and a
/// snapshot can compare two.
final class MatterState {
  /// A state holding [quantities], in [phase] when one is given.
  ///
  /// The ids are not checked here, so a `const` state can be written; a
  /// state read from a document is ([MatterState.fromJson]).
  const MatterState({this.quantities = const <String, Quantity>{}, this.phase});

  /// A state at [temperature], K, and [pressure], Pa, in [phase], with
  /// [also] beside them.
  ///
  /// Throws a [MaterialFormatException] for an id in [also] that is not
  /// `<namespace>.<name>`, which [MatterState.fromJson] would refuse: a
  /// state that saves is one that loads.
  factory MatterState.at({
    double temperature = standardAirTemperature,
    double pressure = standardAtmosphere,
    MaterialPhase? phase,
    Map<String, Quantity> also = const <String, Quantity>{},
  }) => MatterState(
    quantities: Map<String, Quantity>.unmodifiable(<String, Quantity>{
      for (final MapEntry(:key, :value) in also.entries)
        checkedQuantityId(key): value,
      temperatureId: Quantity(temperature, Unit.kelvin),
      pressureId: Quantity(pressure, Unit.pascal),
    }),
    phase: phase,
  );

  /// 20 °C and one standard atmosphere, the state the catalogue's numbers
  /// are quoted at unless an entry says otherwise.
  static const MatterState standard = MatterState(
    quantities: <String, Quantity>{
      temperatureId: Quantity(standardAirTemperature, Unit.kelvin),
      pressureId: Quantity(standardAtmosphere, Unit.pascal),
    },
  );

  /// The id of a body's temperature.
  static const String temperatureId = 'f3d.temperature';

  /// The id of the pressure a body is under.
  static const String pressureId = 'f3d.pressure';

  /// The id of how wet a body's surface is: a share of a fully wetted one,
  /// no unit, nought to one.
  static const String wetnessId = 'f3d.wetness';

  /// Every quantity this state holds, by id.
  final Map<String, Quantity> quantities;

  /// The phase it is in, or null to take the material's.
  final MaterialPhase? phase;

  /// The quantity under [id], or null when this state does not hold it.
  Quantity? operator [](String id) => quantities[id];

  /// Its temperature, K: [standardAirTemperature] when it holds none.
  double get temperature =>
      quantities[temperatureId]?.valueIn(Unit.kelvin) ?? standardAirTemperature;

  /// The pressure it is under, Pa: [standardAtmosphere] when it holds none.
  double get pressure =>
      quantities[pressureId]?.valueIn(Unit.pascal) ?? standardAtmosphere;

  /// This state with [id] holding [value], every other quantity as it was.
  ///
  /// Throws a [MaterialFormatException] for an [id] that is not
  /// `<namespace>.<name>`, as [MatterState.fromJson] does.
  MatterState withQuantity(String id, Quantity value) => MatterState(
    quantities: Map<String, Quantity>.unmodifiable(<String, Quantity>{
      ...quantities,
      checkedQuantityId(id): value,
    }),
    phase: phase,
  );

  /// This state without [id].
  MatterState without(String id) => MatterState(
    quantities: Map<String, Quantity>.unmodifiable(<String, Quantity>{
      for (final MapEntry(:key, :value) in quantities.entries)
        if (key != id) key: value,
    }),
    phase: phase,
  );

  /// This state in [phase].
  MatterState inPhase(MaterialPhase phase) =>
      MatterState(quantities: quantities, phase: phase);

  /// The state as a document holds it: `{"quantities": {"f3d.temperature":
  /// {"value": 300.0, "unit": "K"}, …}, "phase": "liquid"}`, the ids in
  /// sorted order so two equal states write the same text.
  Map<String, Object?> toJson() => <String, Object?>{
    'quantities': <String, Object?>{
      for (final id in quantities.keys.toList()..sort())
        id: quantities[id]!.toJson(),
    },
    'phase': ?phase?.name,
  };

  /// The state [json] holds, as [toJson] writes it. Every quantity is kept,
  /// the ones this build does not know included.
  ///
  /// Throws a [MaterialFormatException] for an id that is not
  /// `<namespace>.<name>`, a quantity that is not one, or a phase that is
  /// not a word.
  factory MatterState.fromJson(Map<String, Object?> json) {
    final quantities = switch (json['quantities']) {
      null => const <String, Object?>{},
      final Map<String, Object?> map => map,
      final other => throw MaterialFormatException(
        'a material state\'s "quantities" must be an object, not $other',
      ),
    };
    return MatterState(
      quantities: Map<String, Quantity>.unmodifiable(<String, Quantity>{
        for (final MapEntry(:key, :value) in quantities.entries)
          checkedQuantityId(key): _quantity(key, value),
      }),
      phase: switch (json['phase']) {
        null => null,
        final String name when name.isNotEmpty => MaterialPhase.named(name),
        final other => throw MaterialFormatException(
          'a material state\'s "phase" must be a word, not $other',
        ),
      },
    );
  }

  static Quantity _quantity(String id, Object? json) {
    try {
      return Quantity.fromJson(json);
    } on UnitFormatException catch (e) {
      throw MaterialFormatException('material state "$id": ${e.message}');
    }
  }

  /// [id] when it is `<namespace>.<name>`; a [MaterialFormatException]
  /// otherwise.
  static String checkedQuantityId(String id) => _idShape.hasMatch(id)
      ? id
      : throw MaterialFormatException(
          'a quantity\'s id is "<namespace>.<name>", as "f3d.temperature" '
          'is, not "$id"',
        );

  static final RegExp _idShape = RegExp(
    r'^[a-z][a-z0-9_.\-]*\.[a-zA-Z][A-Za-z0-9_]*$',
  );

  @override
  bool operator ==(Object other) {
    if (other is! MatterState ||
        other.phase != phase ||
        other.quantities.length != quantities.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in quantities.entries) {
      if (other.quantities[key] != value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    Object.hashAllUnordered(<int>[
      for (final MapEntry(:key, :value) in quantities.entries)
        Object.hash(key, value),
    ]),
  );

  @override
  String toString() =>
      'MatterState(${[for (final MapEntry(:key, :value) in quantities.entries) '$key: $value', if (phase case final phase?) 'phase: ${phase.name}'].join(', ')})';
}
