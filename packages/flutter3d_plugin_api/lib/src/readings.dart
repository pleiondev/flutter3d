/// What the simulation is told from outside and what it reads off itself:
/// [ExternalStateInput] and [ProbeReading], with the [ReadingKind] and
/// [ReadingQuality] both carry.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'plugin_version.dart' show PluginFormatException;

/// How a reading came to be: measured by an instrument, estimated by a
/// model, predicted ahead of its time, or read off the simulation itself.
///
/// **An open set by wire name.** A twin's data contract will grow kinds
/// (`interpolated`, `replayed`), so this is a class with constants rather
/// than an enum, and a name this build does not know is kept as it was
/// written ([parse]) rather than refused: the reading still says what its
/// source called it.
final class ReadingKind {
  const ReadingKind._(this.name);

  /// Read by an instrument: a sensor, a gauge, a person with a ruler.
  static const ReadingKind measured = ReadingKind._('measured');

  /// Worked out by a model from what was measured: an observer, a filter.
  static const ReadingKind estimated = ReadingKind._('estimated');

  /// Worked out ahead of the time it is for: a forecast, a schedule.
  static const ReadingKind predicted = ReadingKind._('predicted');

  /// Read off the simulation by a probe: what the model says, not the
  /// world.
  static const ReadingKind simulated = ReadingKind._('simulated');

  /// The kinds this release names, in the order they were added.
  static const List<ReadingKind> values = <ReadingKind>[
    measured,
    estimated,
    predicted,
    simulated,
  ];

  /// The kind [name] writes: one of [values], or a kind of that name this
  /// build does not know, kept so it is written back the same.
  static ReadingKind parse(String name) =>
      values.where((k) => k.name == name).firstOrNull ?? ReadingKind._(name);

  /// The wire name.
  final String name;

  @override
  bool operator ==(Object other) => other is ReadingKind && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// How far a reading can be trusted, as its source says.
///
/// **An open set by wire name**, for the reason [ReadingKind] is one: the
/// names an industrial source sends (OPC UA's status codes) are more than
/// these four, and a name this build does not know is kept ([parse]).
final class ReadingQuality {
  const ReadingQuality._(this.name);

  /// Trusted.
  static const ReadingQuality good = ReadingQuality._('good');

  /// Usable with care: a sensor out of calibration, a value at a limit.
  static const ReadingQuality uncertain = ReadingQuality._('uncertain');

  /// Not to be used: a broken wire, a value out of range.
  static const ReadingQuality bad = ReadingQuality._('bad');

  /// Once good and not renewed when it should have been.
  static const ReadingQuality stale = ReadingQuality._('stale');

  /// The qualities this release names, in the order they were added.
  static const List<ReadingQuality> values = <ReadingQuality>[
    good,
    uncertain,
    bad,
    stale,
  ];

  /// The quality [name] writes: one of [values], or one of that name this
  /// build does not know, kept so it is written back the same.
  static ReadingQuality parse(String name) =>
      values.where((q) => q.name == name).firstOrNull ?? ReadingQuality._(name);

  /// The wire name.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ReadingQuality && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// One piece of state that arrived from outside the simulation for one
/// step: a temperature from a plant's sensor, a valve's position from a
/// log, a headset's pose.
///
/// **Input, not an override.** It enters with the step's other input (an
/// `InputFrame`'s `external`), goes on the tape with the step it was fed
/// in, and replays with it; what the simulation makes of it is the
/// business of an [Assimilation] inside the step, which decides between the
/// sensor and the model. So a run fed by telemetry replays bit for bit and
/// a server can verify it, as a run fed by a keyboard does.
///
/// **Fed on a live step, or lost.** `InputState.feedExternal` drops a
/// reading while the input is muted, as it is during a replay, so one that
/// arrives then would otherwise never reach the run. A source on its own
/// clock queues its readings and drains the queue in `EngineLoop.onStepInput`,
/// which runs at the start of every live step and never during a replay.
///
/// **Numbers with a unit.** [value] is the reading's components (one for a
/// temperature, seven for a pose: position and a quaternion) in [unit], or
/// unitless where [unit] is null. Times are seconds, on the clocks their
/// names say.
final class ExternalStateInput {
  /// A reading from [source] of [value] in [unit].
  ExternalStateInput({
    required this.source,
    required List<double> value,
    this.unit,
    this.sourceTime,
    this.receivedTime,
    this.quality,
    this.kind,
    this.tag,
    Map<String, Object?> unknown = const <String, Object?>{},
  }) : value = List<double>.unmodifiable(value),
       unknown = Map<String, Object?>.unmodifiable(unknown) {
    if (source.isEmpty) throw ArgumentError.value(source, 'source', 'empty');
  }

  /// One quantity from [source]: its value in its unit.
  factory ExternalStateInput.quantity(
    String source,
    Quantity quantity, {
    double? sourceTime,
    double? receivedTime,
    ReadingQuality? quality,
    ReadingKind? kind,
    String? tag,
  }) => ExternalStateInput(
    source: source,
    value: <double>[quantity.value],
    unit: quantity.unit,
    sourceTime: sourceTime,
    receivedTime: receivedTime,
    quality: quality,
    kind: kind,
    tag: tag,
  );

  /// Where it comes from, by the name the simulation knows it under: a
  /// sensor's tag, a channel, `xr.head`.
  final String source;

  /// Its components, in [unit].
  final List<double> value;

  /// The unit of [value], or null for a number with none.
  final Unit? unit;

  /// When the source took it, seconds on the source's clock; null when it
  /// does not say.
  final double? sourceTime;

  /// When the engine received it, seconds on the receiving machine's clock;
  /// null when not recorded.
  final double? receivedTime;

  /// How far its source trusts it; null when it does not say.
  final ReadingQuality? quality;

  /// How it came to be; null when its source does not say.
  final ReadingKind? kind;

  /// Free text its source attaches: a batch, a line, a device's serial.
  final String? tag;

  /// Fields a later build wrote that this one does not know, kept and
  /// written back as they were.
  final Map<String, Object?> unknown;

  /// [value] as a [Quantity], for a reading of one component with a unit.
  /// Throws a [StateError] for any other.
  Quantity get quantity {
    final unit = this.unit;
    if (value.length != 1 || unit == null) {
      throw StateError(
        'the reading from $source has ${value.length} components'
        '${unit == null ? ' and no unit' : ''}, not one quantity',
      );
    }
    return Quantity(value.single, unit);
  }

  static const Set<String> _known = <String>{
    'step',
    'source',
    'value',
    'unit',
    'sourceTime',
    'receivedTime',
    'quality',
    'kind',
    'tag',
  };

  /// The reading as plain values: what the tape's `externalInputs` and the
  /// wire hold, beside the step the tape adds.
  Map<String, Object?> toJson() => <String, Object?>{
    ...unknown,
    'source': source,
    'value': value,
    if (unit case final unit?) 'unit': unit.toJson(),
    'sourceTime': ?sourceTime,
    'receivedTime': ?receivedTime,
    if (quality case final quality?) 'quality': quality.name,
    if (kind case final kind?) 'kind': kind.name,
    'tag': ?tag,
  };

  /// Reads what [toJson] wrote; a `step` beside it is the tape's and is
  /// passed over. Throws a [PluginFormatException] naming the field that is
  /// not what it says.
  factory ExternalStateInput.fromJson(Object? json) {
    Never wrong(String what) =>
        throw PluginFormatException('an external input $what', json);
    if (json is! Map) wrong('is not an object');
    final source = json['source'];
    if (source is! String || source.isEmpty) wrong('names no source');
    final value = switch (json['value']) {
      final num single => <double>[single.toDouble()],
      final List<Object?> list when list.every((v) => v is num) => <double>[
        for (final v in list) (v! as num).toDouble(),
      ],
      final other => wrong('from $source has the value $other, not numbers'),
    };
    double? seconds(String key) => switch (json[key]) {
      null => null,
      final num t when t.isFinite => t.toDouble(),
      final other => wrong('from $source gives "$key" as $other'),
    };
    String? text(String key) => switch (json[key]) {
      null => null,
      final String t => t,
      final other => wrong('from $source gives "$key" as $other, not text'),
    };
    final Unit? unit;
    try {
      unit = json['unit'] == null ? null : Unit.fromJson(json['unit']);
    } on Flutter3dFormatException catch (error) {
      wrong('from $source has a unit this build cannot read: $error');
    }
    return ExternalStateInput(
      source: source,
      value: value,
      unit: unit,
      sourceTime: seconds('sourceTime'),
      receivedTime: seconds('receivedTime'),
      quality: switch (text('quality')) {
        null => null,
        final name => ReadingQuality.parse(name),
      },
      kind: switch (text('kind')) {
        null => null,
        final name => ReadingKind.parse(name),
      },
      tag: text('tag'),
      unknown: <String, Object?>{
        for (final MapEntry(:key, :value) in json.entries)
          if (!_known.contains(key)) '$key': value,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExternalStateInput &&
      other.source == source &&
      _sameNumbers(other.value, value) &&
      other.unit == unit &&
      other.sourceTime == sourceTime &&
      other.receivedTime == receivedTime &&
      other.quality == quality &&
      other.kind == kind &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(
    source,
    Object.hashAll(value),
    unit,
    sourceTime,
    receivedTime,
    quality,
    kind,
    tag,
  );

  @override
  String toString() =>
      'ExternalStateInput($source: $value${unit == null ? '' : ' $unit'})';
}

/// A grid of values a probe read at once: a section's temperatures, a
/// volume's concentrations. [values] in row-major order over [shape], each
/// in [unit].
///
/// **Float32, packed.** A grid is the one reading large enough for its
/// encoding to matter, so it is a [Float32List] and travels as one: its
/// bytes cross an isolate's port without a list of boxed doubles being
/// built.
final class ProbeField {
  /// [values] over [shape], which must hold exactly as many.
  ProbeField({
    required List<int> shape,
    required this.values,
    required this.unit,
  }) : shape = List<int>.unmodifiable(shape) {
    final count = shape.fold(1, (int n, int side) => n * side);
    if (shape.isEmpty || shape.any((side) => side < 1)) {
      throw ArgumentError.value(shape, 'shape', 'not a grid');
    }
    if (count != values.length) {
      throw ArgumentError(
        'a field of shape $shape holds $count values, not ${values.length}',
      );
    }
  }

  /// The size of each axis, outermost first.
  final List<int> shape;

  /// The values, row-major, in [unit].
  final Float32List values;

  /// The unit of every value.
  final Unit unit;

  Map<String, Object?> toJson() => <String, Object?>{
    'shape': shape,
    'values': values,
    'unit': unit.toJson(),
  };

  /// Reads what [toJson] wrote, the values as a [Float32List] or as a list
  /// of numbers. Throws a [PluginFormatException] for anything else.
  factory ProbeField.fromJson(Object? json) {
    Never wrong(String what) =>
        throw PluginFormatException('a probe field $what', json);
    if (json is! Map) wrong('is not an object');
    final shape = switch (json['shape']) {
      final List<Object?> s when s.isNotEmpty && s.every((v) => v is int) =>
        s.cast<int>(),
      final other => wrong('has the shape $other'),
    };
    final values = switch (json['values']) {
      final Float32List packed => packed,
      final List<Object?> list when list.every((v) => v is num) =>
        Float32List.fromList(<double>[
          for (final v in list) (v! as num).toDouble(),
        ]),
      _ => wrong('has values that are not numbers'),
    };
    try {
      return ProbeField(
        shape: shape,
        values: values,
        unit: Unit.fromJson(json['unit']),
      );
    } on ArgumentError catch (error) {
      wrong('does not fit its shape: ${error.message}');
    } on Flutter3dFormatException catch (error) {
      wrong('has a unit this build cannot read: $error');
    }
  }
}

/// What one probe read at the end of one step: published to the view
/// (`PublishedState.probes`) and written on the run's tape.
///
/// **What views and charts read** in place of the world: a probe is
/// declared in the simulation, read in the `publish` phase, and this is all
/// that leaves it, so a chart of a twin's boiler works the same when the
/// simulation runs in another isolate or on a server.
final class ProbeReading {
  /// [value] in [unit], read by the probe [probe] at [step].
  ProbeReading({
    required this.probe,
    required this.step,
    required List<double> value,
    required this.unit,
    this.kind = ReadingKind.simulated,
    this.quality,
    this.field,
  }) : value = List<double>.unmodifiable(value);

  /// The probe's id, unique in its simulation.
  final String probe;

  /// The step it was read at the end of.
  final int step;

  /// Its components, in [unit]: one for a quantity, three for a vector.
  final List<double> value;

  /// The unit of [value].
  final Unit unit;

  /// How it came to be: [ReadingKind.simulated] for a probe's own reading.
  final ReadingKind kind;

  /// How far it can be trusted; null when nothing says.
  final ReadingQuality? quality;

  /// A grid read at once, beside [value]; null for a reading of one place.
  final ProbeField? field;

  /// [value] as a [Quantity], for a reading of one component. Throws a
  /// [StateError] for a vector.
  Quantity get quantity => value.length == 1
      ? Quantity(value.single, unit)
      : throw StateError(
          'probe $probe read ${value.length} components, not one quantity',
        );

  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    'probe': probe,
    'value': value,
    'unit': unit.toJson(),
    if (kind != ReadingKind.simulated) 'kind': kind.name,
    if (quality case final quality?) 'quality': quality.name,
    if (field case final field?) 'field': field.toJson(),
  };

  /// Reads what [toJson] wrote. Throws a [PluginFormatException] naming the
  /// field that is not what it says.
  factory ProbeReading.fromJson(Object? json) {
    Never wrong(String what) =>
        throw PluginFormatException('a probe reading $what', json);
    if (json is! Map) wrong('is not an object');
    final probe = json['probe'];
    final step = json['step'];
    if (probe is! String || probe.isEmpty) wrong('names no probe');
    if (step is! int || step < 0) wrong('of $probe names no step');
    final value = switch (json['value']) {
      final List<Object?> list when list.every((v) => v is num) => <double>[
        for (final v in list) (v! as num).toDouble(),
      ],
      final other => wrong('of $probe has the value $other'),
    };
    final Unit unit;
    try {
      unit = Unit.fromJson(json['unit']);
    } on Flutter3dFormatException catch (error) {
      wrong('of $probe has a unit this build cannot read: $error');
    }
    return ProbeReading(
      probe: probe,
      step: step,
      value: value,
      unit: unit,
      kind: switch (json['kind']) {
        null => ReadingKind.simulated,
        final String name => ReadingKind.parse(name),
        final other => wrong('of $probe has the kind $other'),
      },
      quality: switch (json['quality']) {
        null => null,
        final String name => ReadingQuality.parse(name),
        final other => wrong('of $probe has the quality $other'),
      },
      field: json['field'] == null ? null : ProbeField.fromJson(json['field']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProbeReading &&
      other.probe == probe &&
      other.step == step &&
      _sameNumbers(other.value, value) &&
      other.unit == unit &&
      other.kind == kind &&
      other.quality == quality;

  @override
  int get hashCode =>
      Object.hash(probe, step, Object.hashAll(value), unit, kind, quality);

  @override
  String toString() => 'ProbeReading($probe at $step: $value $unit)';
}

bool _sameNumbers(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
