/// A material's property as a function of its state: the law, of which the
/// catalogue's number is the value at the reference state.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        CompiledExpression,
        Dimension,
        Expression,
        ExpressionCodec,
        ExpressionScope,
        ExpressionSyntaxException,
        Unit,
        UnitFormatException,
        UnitMismatchException;

import '../physical_constants.dart';
import '../standard_world.dart';
import 'material_json.dart';
import 'material_state.dart';

/// How a value was come by: measured, read from a handbook, or estimated.
///
/// **A class of constants rather than an enum**, so a kind a later minor
/// adds — `derived`, `simulated` — is [Confidence.named] and breaks no
/// switch written against these, and a file that names one this build does
/// not know still reads.
final class Confidence {
  /// A confidence by its wire [name].
  const Confidence.named(this.name);

  /// A primary measurement, on a named specimen, read in its paper.
  static const Confidence measured = Confidence.named('measured');

  /// A compiled handbook, a standard, or a reference equation of state.
  static const Confidence handbook = Confidence.named('handbook');

  /// A typical value, the middle of a spread, a value derived by a rule of
  /// thumb, or the engine's own choice: its source says which.
  static const Confidence estimate = Confidence.named('estimate');

  /// The three the engine's catalogue uses, from the most trusted.
  static const List<Confidence> values = <Confidence>[
    measured,
    handbook,
    estimate,
  ];

  /// Its word in a file.
  final String name;

  @override
  bool operator ==(Object other) => other is Confidence && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Confidence.$name';
}

/// The spread a value is known within: the low and high ends of a range a
/// source gives, in the property's unit.
final class PropertyInterval {
  const PropertyInterval(this.low, this.high);

  final double low, high;

  /// `[low, high]`, as a file holds it.
  List<double> toJson() => <double>[low, high];

  /// Whether [value] lies within it, ends included.
  bool contains(double value) => value >= low && value <= high;

  @override
  bool operator ==(Object other) =>
      other is PropertyInterval && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() => 'PropertyInterval($low, $high)';
}

/// One quantity of a [MatterState] a law reads: its id, its unit, and the
/// range the law is valid over.
///
/// **A law does not extrapolate.** The value read is held to [low]…[high]
/// before the law sees it, so water's viscosity above its boiling point is
/// its value at the boiling point rather than whatever the fit gives there.
final class LawInput {
  const LawInput(
    this.id, {
    this.unit = Unit.one,
    this.low,
    this.high,
    this.fallback,
  });

  /// The input [json] holds. Throws a [MaterialFormatException] for one
  /// that is not.
  factory LawInput.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw MaterialFormatException('a law\'s input is an object, not $json');
    }
    final id = switch (json['id']) {
      final String id => MatterState.checkedQuantityId(id),
      final other => throw MaterialFormatException(
        'a law\'s input names a quantity\'s id, not $other',
      ),
    };
    final Unit unit;
    try {
      unit = json['unit'] == null ? Unit.one : Unit.fromJson(json['unit']);
    } on UnitFormatException catch (e) {
      throw MaterialFormatException('the law\'s input "$id": ${e.message}');
    }
    double? number(String key) => switch (json[key]) {
      null => null,
      final num n when n.isFinite => n.toDouble(),
      final other => throw MaterialFormatException(
        'the law\'s input "$id": "$key" must be a finite number, not $other',
      ),
    };
    return LawInput(
      id,
      unit: unit,
      low: number('low'),
      high: number('high'),
      fallback: number('fallback'),
    );
  }

  /// A body's temperature, K.
  static const LawInput temperature = LawInput(
    MatterState.temperatureId,
    unit: Unit.kelvin,
  );

  /// The pressure a body is under, Pa.
  static const LawInput pressure = LawInput(
    MatterState.pressureId,
    unit: Unit.pascal,
  );

  /// The quantity's id in a [MatterState].
  final String id;

  /// What it measures. [low], [high] and [fallback] are in the coherent SI
  /// unit of its dimension (K for a temperature, Pa for a pressure), as the
  /// law receives it.
  final Unit unit;

  /// The least and greatest value the law is valid at; null for no bound.
  final double? low, high;

  /// The value when a state does not hold the quantity, in the coherent SI
  /// unit of [unit] (kelvin for a temperature, pascals for a pressure, a
  /// plain fraction for a share): for a temperature or a pressure, the
  /// standard world's unless given.
  final double? fallback;

  /// This input with the valid range [low]…[high].
  LawInput within(double? low, double? high) =>
      LawInput(id, unit: unit, low: low, high: high, fallback: fallback);

  /// The value [state] holds, in the coherent unit, held to the valid
  /// range.
  double read(MatterState state) {
    final held = state.quantities[id];
    final double raw = held != null
        ? held.valueIn(Unit.coherent(unit.dimension))
        : fallback ??
              switch (id) {
                MatterState.temperatureId => standardAirTemperature,
                MatterState.pressureId => standardAtmosphere,
                _ => 0.0,
              };
    final lowest = low, highest = high;
    if (lowest != null && raw < lowest) return lowest;
    if (highest != null && raw > highest) return highest;
    return raw;
  }

  /// The input as a file holds it: `{"id": …, "unit": …, "low": …, "high":
  /// …, "fallback": …}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'unit': unit.toJson(),
    'low': ?low,
    'high': ?high,
    'fallback': ?fallback,
  };

  @override
  bool operator ==(Object other) =>
      other is LawInput &&
      other.id == id &&
      other.unit == unit &&
      other.low == low &&
      other.high == high &&
      other.fallback == fallback;

  @override
  int get hashCode => Object.hash(id, unit, low, high, fallback);

  @override
  String toString() => 'LawInput($id)';
}

/// One property of a material as a function of the state a body of it is
/// in: a constant, a table, or a formula of the engine's expression
/// language.
///
/// **The catalogue's number is the law at the reference state.** [value] is
/// what the source quotes at the material's temperature and pressure (20 °C
/// and one atmosphere unless the entry says otherwise), and [at] given that
/// state answers [value] exactly: a table holds it as one of its points, a
/// formula is anchored on it. What reads a material at another state calls
/// [at]; what wants the one number reads [value].
///
/// **An open base**: a law a later minor adds, or a plugin's own, extends
/// it. A file naming a kind this build does not know reads as a
/// [ConstantLaw] of its [value], keeping the rest, so it is written back
/// as it was.
///
/// Every value is in the coherent SI unit of the property it is a law of,
/// as the property's documentation gives it.
abstract base class PropertyLaw {
  const PropertyLaw(this.value, {this.confidence, this.source, this.interval});

  /// The value at the material's reference state, in the property's unit.
  final double value;

  /// How the value was come by; null when the source does not say.
  final Confidence? confidence;

  /// Where this value comes from, when it is not the group's source.
  final String? source;

  /// The spread the source gives the value within, or null.
  final PropertyInterval? interval;

  /// The kind's word in a file: `constant`, `table`, `formula`.
  String get kind;

  /// Whether the value changes with the state at all.
  bool get dependsOnState;

  /// The value at [state], in the property's unit.
  double at(MatterState state);

  /// What the kind writes beside [value] and the common keys.
  Map<String, Object?> lawJson();

  /// The law as a file holds it: a bare number for a [ConstantLaw] that
  /// says nothing but its value, as version 1 of a material's document wrote
  /// every property; otherwise an object with `value`, `law`, the kind's own
  /// keys, and `confidence`, `source` and `interval` where they are known.
  Object toJson() => <String, Object?>{
    'value': value,
    'law': kind,
    ...lawJson(),
    'confidence': ?confidence?.name,
    'source': ?source,
    'interval': ?interval?.toJson(),
  };

  static const Set<String> _commonKeys = <String>{
    'value',
    'law',
    'confidence',
    'source',
    'interval',
  };

  /// The law [json] holds, as [toJson] writes it: a number is a
  /// [ConstantLaw]. [where] names the property in an error.
  ///
  /// Throws a [MaterialFormatException] for anything that is not a law.
  static PropertyLaw fromJson(Object? json, {String where = 'a property'}) {
    if (json is num) {
      if (!json.isFinite) {
        throw MaterialFormatException('$where must be finite, not $json');
      }
      return ConstantLaw(json.toDouble());
    }
    if (json is! Map<String, Object?>) {
      throw MaterialFormatException(
        '$where must be a number or a law, not $json',
      );
    }
    final value = switch (json['value']) {
      final num n when n.isFinite => n.toDouble(),
      final other => throw MaterialFormatException(
        '$where: a law\'s "value" must be a finite number, not $other',
      ),
    };
    final confidence = switch (json['confidence']) {
      null => null,
      final String name when name.isNotEmpty => Confidence.named(name),
      final other => throw MaterialFormatException(
        '$where: "confidence" must be a word, not $other',
      ),
    };
    final source = switch (json['source']) {
      null => null,
      final String said => said,
      final other => throw MaterialFormatException(
        '$where: "source" must be text, not $other',
      ),
    };
    final interval = switch (json['interval']) {
      null => null,
      [final num low, final num high] when low <= high => PropertyInterval(
        low.toDouble(),
        high.toDouble(),
      ),
      final other => throw MaterialFormatException(
        '$where: "interval" must be [low, high], not $other',
      ),
    };
    final rest = <String, Object?>{
      for (final MapEntry(:key, :value) in json.entries)
        if (!_commonKeys.contains(key)) key: value,
    };
    try {
      return switch (json['law']) {
        null || 'constant' => ConstantLaw(
          value,
          confidence: confidence,
          source: source,
          interval: interval,
          unknown: rest,
        ),
        'table' => TableLaw._fromJson(
          value,
          rest,
          confidence: confidence,
          source: source,
          interval: interval,
        ),
        'formula' => FormulaLaw._fromJson(
          value,
          rest,
          confidence: confidence,
          source: source,
          interval: interval,
        ),
        final String other => ConstantLaw(
          value,
          confidence: confidence,
          source: source,
          interval: interval,
          unknown: <String, Object?>{'law': other, ...rest},
        ),
        final other => throw MaterialFormatException(
          '"law" must be a word, not $other',
        ),
      };
    } on MaterialFormatException catch (e) {
      throw MaterialFormatException('$where: ${e.message}');
    }
  }

  @override
  String toString() => '$runtimeType($value)';
}

/// A value the same at every state: the catalogue's number with nothing
/// known of how it changes.
final class ConstantLaw extends PropertyLaw {
  const ConstantLaw(
    super.value, {
    super.confidence,
    super.source,
    super.interval,
    this.unknown = const <String, Object?>{},
  });

  /// The keys of its file this build did not read — a law of a kind a
  /// later version knows, among them — kept so they are written back.
  final Map<String, Object?> unknown;

  @override
  String get kind => 'constant';

  @override
  bool get dependsOnState => false;

  @override
  double at(MatterState state) => value;

  @override
  Map<String, Object?> lawJson() => const <String, Object?>{};

  @override
  Object toJson() {
    if (confidence == null &&
        source == null &&
        interval == null &&
        unknown.isEmpty) {
      return value;
    }
    return <String, Object?>{
      'value': value,
      'law': kind,
      'confidence': ?confidence?.name,
      'source': ?source,
      'interval': ?interval?.toJson(),
      ...unknown,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ConstantLaw &&
      other.value == value &&
      other.confidence == confidence &&
      other.source == source &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(value, confidence, source, interval);
}

/// A value tabulated against one quantity of the state, read between the
/// points on a straight line.
///
/// **One formula, written down.** With the input `x` held to the table's
/// ends, the segment is the last `i` with `xs[i] <= x`, and the value is
/// `ys[i] + (ys[i + 1] - ys[i]) * ((x - xs[i]) / (xs[i + 1] - xs[i]))`, in
/// that order of operations, in double precision: at a point the value is
/// that point's exactly. The C core reads each property's value at the
/// reference state ([value]) from its generated header, unless a body is
/// given the law itself (`NativeWorld.setMaterialLaws` in
/// flutter3d_physics_native): then it evaluates this formula, written as an
/// expression and compiled to bytecode, at the body's temperature, to the
/// bit what [at] gives.
final class TableLaw extends PropertyLaw {
  const TableLaw(
    super.value, {
    this.input = LawInput.temperature,
    required this.xs,
    required this.ys,
    super.confidence,
    super.source,
    super.interval,
  });

  /// What the table is against.
  final LawInput input;

  /// The input's values, rising, in its coherent unit.
  final List<double> xs;

  /// The property's value at each of [xs].
  final List<double> ys;

  @override
  String get kind => 'table';

  @override
  bool get dependsOnState => true;

  @override
  double at(MatterState state) => interpolate(input.read(state));

  /// The value at [x], in the input's coherent unit, by the formula above.
  double interpolate(double x) {
    final last = xs.length - 1;
    if (x <= xs[0]) return ys[0];
    if (x >= xs[last]) return ys[last];
    var i = 0;
    while (xs[i + 1] <= x) {
      i++;
    }
    final x0 = xs[i], y0 = ys[i];
    return y0 + (ys[i + 1] - y0) * ((x - x0) / (xs[i + 1] - x0));
  }

  /// What is wrong with the table, one sentence each: fewer than two
  /// points, lists of two lengths, inputs that do not rise.
  List<String> problems() => <String>[
    if (xs.length < 2) 'a table has two points at least',
    if (xs.length != ys.length) 'a table has as many values as inputs',
    for (var i = 1; i < xs.length; i++)
      if (!(xs[i] > xs[i - 1]))
        'a table\'s inputs rise, and ${xs[i]} follows ${xs[i - 1]}',
    for (final y in ys)
      if (!y.isFinite) 'a table\'s value $y is not finite',
  ];

  @override
  bool operator ==(Object other) =>
      other is TableLaw &&
      other.value == value &&
      other.input == input &&
      _sameList(other.xs, xs) &&
      _sameList(other.ys, ys) &&
      other.confidence == confidence &&
      other.source == source &&
      other.interval == interval;

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(value, input, Object.hashAll(xs), Object.hashAll(ys));

  @override
  Map<String, Object?> lawJson() => <String, Object?>{
    'input': input.toJson(),
    'points': <List<double>>[
      for (var i = 0; i < xs.length; i++) <double>[xs[i], ys[i]],
    ],
  };

  static TableLaw _fromJson(
    double value,
    Map<String, Object?> json, {
    Confidence? confidence,
    String? source,
    PropertyInterval? interval,
  }) {
    final points = switch (json['points']) {
      final List<Object?> list
          when list.every(
            (p) =>
                p is List &&
                p.length == 2 &&
                p.every((n) => n is num && n.isFinite),
          ) =>
        list.cast<List<Object?>>(),
      final other => throw MaterialFormatException(
        'a table\'s "points" are [input, value] pairs, not $other',
      ),
    };
    final law = TableLaw(
      value,
      input: json['input'] == null
          ? LawInput.temperature
          : LawInput.fromJson(json['input']),
      xs: List<double>.unmodifiable(<double>[
        for (final p in points) (p[0]! as num).toDouble(),
      ]),
      ys: List<double>.unmodifiable(<double>[
        for (final p in points) (p[1]! as num).toDouble(),
      ]),
      confidence: confidence,
      source: source,
      interval: interval,
    );
    final problems = law.problems();
    if (problems.isNotEmpty) {
      throw MaterialFormatException(problems.join('; '));
    }
    return law;
  }
}

/// A value given by a formula of the engine's expression language, over the
/// state's quantities by the symbols [inputs] binds: `T`, the temperature
/// in K, and `p`, the pressure in Pa, unless it says otherwise.
///
/// **Units are checked as the text is read**, so a formula carries the unit
/// of its value: `exp(-13.22 + 1858.7 [K] / T) * 1 [Pa·s]` is a viscosity,
/// and [dimension] says so. The text is read and compiled once, the first
/// time it is needed, and every evaluation after that is the compiled
/// closures on Portable maths: the same bits on every platform.
///
/// The factories write the forms a handbook gives ([FormulaLaw.andrade],
/// [FormulaLaw.arrhenius], [FormulaLaw.polynomial]) as that text.
final class FormulaLaw extends PropertyLaw {
  const FormulaLaw(
    super.value, {
    required this.expression,
    this.inputs = standardInputs,
    super.confidence,
    super.source,
    super.interval,
  });

  /// Andrade's law of a liquid's viscosity, or any quantity whose
  /// logarithm is linear in 1/T: ln(y / [unit]) = [a] + [b] / T, with [b]
  /// in K.
  factory FormulaLaw.andrade(
    double value, {
    required double a,
    required double b,
    required String unit,
    LawInput input = LawInput.temperature,
    Confidence? confidence,
    String? source,
  }) => FormulaLaw(
    value,
    expression: 'exp(${_n(a)} + ${_n(b)} [K] / T) * 1 [$unit]',
    inputs: <String, LawInput>{'T': input},
    confidence: confidence,
    source: source,
  );

  /// Arrhenius's law: y = [y0] · exp([activation] / (R T)), with
  /// [activation] in J/mol and R the molar gas constant.
  factory FormulaLaw.arrhenius(
    double value, {
    required double y0,
    required double activation,
    required String unit,
    LawInput input = LawInput.temperature,
    Confidence? confidence,
    String? source,
  }) => FormulaLaw(
    value,
    expression:
        '${_n(y0)} [$unit] * exp(${_n(activation)} [J/mol] / '
        '(${_n(molarGasConstant)} [J/(mol·K)] * T))',
    inputs: <String, LawInput>{'T': input},
    confidence: confidence,
    source: source,
  );

  /// A polynomial in the input's coherent unit: y = c₀ + c₁x + c₂x² + …,
  /// in [unit], written in Horner's form.
  factory FormulaLaw.polynomial(
    double value, {
    required List<double> coefficients,
    required String unit,
    LawInput input = LawInput.temperature,
    Confidence? confidence,
    String? source,
  }) {
    final x = '(T / 1 [${Unit.coherent(input.unit.dimension).symbol}])';
    var text = _n(coefficients.last);
    for (var i = coefficients.length - 2; i >= 0; i--) {
      text = '(${_n(coefficients[i])} + $x * $text)';
    }
    return FormulaLaw(
      value,
      expression: '$text * 1 [$unit]',
      inputs: <String, LawInput>{'T': input},
      confidence: confidence,
      source: source,
    );
  }

  /// `T`, the temperature in K, and `p`, the pressure in Pa.
  static const Map<String, LawInput> standardInputs = <String, LawInput>{
    'T': LawInput.temperature,
    'p': LawInput.pressure,
  };

  /// The formula's text.
  final String expression;

  /// What each symbol the formula reads is, by symbol.
  final Map<String, LawInput> inputs;

  static final Expando<_Compiled> _compiled = Expando<_Compiled>();

  /// [value] as the expression language reads it back, a negative one in
  /// parentheses.
  static String _n(double value) =>
      value.isNegative ? '($value)' : value.toString();

  _Compiled get _program => _compiled[this] ??= _Compiled.of(this);

  /// The formula as the expression language read it.
  ///
  /// Throws a [MaterialFormatException] for text that is not a formula over
  /// [inputs].
  Expression get parsed => _program.compiled.expression;

  /// What the formula's value measures.
  Dimension get dimension => _program.compiled.type.dimension;

  @override
  String get kind => 'formula';

  @override
  bool get dependsOnState => _program.inputs.isNotEmpty;

  @override
  double at(MatterState state) {
    final program = _program;
    return program.compiled.evaluate(<List<double>>[
      for (final input in program.inputs) <double>[input.read(state)],
    ]).single;
  }

  @override
  Map<String, Object?> lawJson() => <String, Object?>{
    'expression': expression,
    if (!_sameInputs(inputs, standardInputs))
      'inputs': <String, Object?>{
        for (final MapEntry(:key, :value) in inputs.entries)
          key: value.toJson(),
      },
  };

  static FormulaLaw _fromJson(
    double value,
    Map<String, Object?> json, {
    Confidence? confidence,
    String? source,
    PropertyInterval? interval,
  }) {
    final expression = switch (json['expression']) {
      final String text when text.trim().isNotEmpty => text,
      final other => throw MaterialFormatException(
        'a formula\'s "expression" is its text, not $other',
      ),
    };
    final inputs = switch (json['inputs']) {
      null => standardInputs,
      final Map<String, Object?> map =>
        Map<String, LawInput>.unmodifiable(<String, LawInput>{
          for (final MapEntry(:key, :value) in map.entries)
            key: LawInput.fromJson(value),
        }),
      final other => throw MaterialFormatException(
        'a formula\'s "inputs" map symbols to quantities, not $other',
      ),
    };
    final law = FormulaLaw(
      value,
      expression: expression,
      inputs: inputs,
      confidence: confidence,
      source: source,
      interval: interval,
    );
    law._program; // Read now, so a bad formula is refused with its file.
    return law;
  }

  @override
  bool operator ==(Object other) =>
      other is FormulaLaw &&
      other.value == value &&
      other.expression == expression &&
      _sameInputs(other.inputs, inputs) &&
      other.confidence == confidence &&
      other.source == source &&
      other.interval == interval;

  static bool _sameInputs(Map<String, LawInput> a, Map<String, LawInput> b) =>
      a.length == b.length &&
      a.entries.every((MapEntry<String, LawInput> e) => b[e.key] == e.value);

  @override
  int get hashCode => Object.hash(value, expression, confidence, source);
}

/// A formula read and compiled, with the input each of its variables is.
final class _Compiled {
  _Compiled(this.compiled, this.inputs);

  factory _Compiled.of(FormulaLaw law) {
    final Expression expression;
    try {
      expression = ExpressionCodec(
        scope: ExpressionScope.quantities(<String, Unit>{
          for (final MapEntry(:key, :value) in law.inputs.entries)
            key: value.unit,
        }),
      ).decode(law.expression);
    } on ExpressionSyntaxException catch (e) {
      throw MaterialFormatException(
        'the formula "${law.expression}" does not read: $e',
      );
    } on UnitMismatchException catch (e) {
      throw MaterialFormatException(
        'the formula "${law.expression}" does not read: ${e.message}',
      );
    }
    final compiled = CompiledExpression(expression);
    if (compiled.type.components != 1 || compiled.type.isBoolean) {
      throw MaterialFormatException(
        'the formula "${law.expression}" is a ${compiled.type}, not a number',
      );
    }
    return _Compiled(compiled, <LawInput>[
      for (final name in compiled.variables) law.inputs[name]!,
    ]);
  }

  final CompiledExpression compiled;

  /// The input of each of [compiled]'s variables, in its order.
  final List<LawInput> inputs;
}
