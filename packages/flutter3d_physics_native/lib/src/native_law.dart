/// Laws and expressions the C core evaluates itself: a material's
/// `PropertyLaw` at a body's temperature, a probe's derived quantity.
///
/// The Dart side compiles each to the expression language's internal
/// bytecode (`ExpressionBytecode`, flutter3d_foundation's `internal.dart`),
/// and the core runs it with a C port of the same interpreter, in binary64
/// on the same portable maths: the core's answer is the Dart answer, bit
/// for bit (`test/law_parity_test.dart`).
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_foundation/internal.dart' show ExpressionBytecode;
import 'package:flutter3d_matter/flutter3d_matter.dart';

import 'core/core.dart' as c;
import 'native_world.dart';

/// Which value a law gives in the core — `F3dLawProperty`: of a body's
/// material ([ofBody], `NativeWorld.setLaw`) or of a shallow liquid
/// ([ofLiquid], `NativeWorld.setShallowLaw`).
///
/// **Open**: a class of constants, so a property a later core reads through
/// a law is added without breaking a `switch` written against these.
final class NativeLawProperty {
  const NativeLawProperty._(this.code, this.name);

  /// J/(kg·K): `ThermalProperties.specificHeat`.
  static const NativeLawProperty specificHeat = NativeLawProperty._(
    0,
    'specificHeat',
  );

  /// W/(m·K): `ThermalProperties.conductivity`.
  static const NativeLawProperty conductivity = NativeLawProperty._(
    1,
    'conductivity',
  );

  /// Nought to one: `ThermalProperties.emissivity`.
  static const NativeLawProperty emissivity = NativeLawProperty._(
    2,
    'emissivity',
  );

  /// kg/m³: a liquid's `MechanicalProperties.density`.
  static const NativeLawProperty density = NativeLawProperty._(3, 'density');

  /// Pa·s: a liquid's `FluidProperties.viscosity`.
  static const NativeLawProperty viscosity = NativeLawProperty._(
    4,
    'viscosity',
  );

  /// N/m: a liquid's `FluidProperties.surfaceTension`.
  static const NativeLawProperty surfaceTension = NativeLawProperty._(
    5,
    'surfaceTension',
  );

  /// Every one the core reads through a law, in their order.
  static const List<NativeLawProperty> values = <NativeLawProperty>[
    specificHeat,
    conductivity,
    emissivity,
    density,
    viscosity,
    surfaceTension,
  ];

  /// The ones a body's material is read through.
  static const List<NativeLawProperty> ofBody = <NativeLawProperty>[
    specificHeat,
    conductivity,
    emissivity,
  ];

  /// The ones a shallow liquid is read through.
  static const List<NativeLawProperty> ofLiquid = <NativeLawProperty>[
    density,
    viscosity,
    surfaceTension,
  ];

  /// `F3dLawProperty`'s number.
  final int code;

  /// The property's name in its group of `PhysicalMaterial`.
  final String name;

  /// [material]'s law of this property, or null; null too for a code a
  /// later core reads that this one does not know.
  PropertyLaw? of(PhysicalMaterial material) => switch (code) {
    0 => material.thermal?.specificHeat,
    1 => material.thermal?.conductivity,
    2 => material.thermal?.emissivity,
    3 => material.mechanical?.density,
    4 => material.fluid?.viscosity,
    5 => material.fluid?.surfaceTension,
    _ => null,
  };

  @override
  String toString() => 'NativeLawProperty.$name';
}

/// A material's law as the core evaluates it: its value as a function of a
/// body's temperature alone, compiled to bytecode.
///
/// **What the core knows of a body's state is its temperature.** An input
/// of [law] that is the temperature (`MatterState.temperatureId`) is the
/// body's, held to the input's valid range as `LawInput.read` holds it; any
/// other — the pressure, a plugin's quantity — is what `LawInput.read`
/// gives a state that does not hold it (the standard atmosphere for a
/// pressure, the input's fallback otherwise), fixed when the law is
/// compiled. A law of another state is evaluated in Dart and pushed as a
/// number ([NativeMaterialTracker]).
///
/// A law of a kind the expression language cannot write (a plugin's own
/// `PropertyLaw`) has no [NativeLaw]: [NativeLaw.of] answers null.
final class NativeLaw {
  NativeLaw._(this.law, this.expression)
    : _program = ExpressionBytecode.compile(expression);

  /// [law] compiled, or null for a law of a kind it cannot write.
  static NativeLaw? of(PropertyLaw law) {
    final expression = lawExpression(law);
    return expression == null ? null : NativeLaw._(law, expression);
  }

  /// What was compiled.
  final PropertyLaw law;

  /// The law as an expression of one variable, [temperature], in K.
  final Expression expression;

  final ExpressionBytecode _program;

  /// The variable [expression] reads: the body's temperature, K.
  static const String temperature = 'T';

  /// The bytecode the core loads.
  Uint8List get bytecode => _program.encode();

  /// The value at [kelvin] as the Dart interpreter computes it: what the
  /// core's interpreter answers, to the bit.
  double at(double kelvin) => _program.inputs.isEmpty
      ? _program.run(const <List<double>>[]).single
      : _program.run(<List<double>>[
          <double>[kelvin],
        ]).single;
}

/// [law] as an expression of the body's temperature, `T` in K, that gives
/// what `law.at` gives a state at that temperature, bit for bit; null for a
/// law of a kind this cannot write.
Expression? lawExpression(PropertyLaw law) => switch (law) {
  ConstantLaw(:final value) => ExpressionConstant(<double>[
    value,
  ], ExpressionType.float),
  final TableLaw table => _table(table),
  final FormulaLaw formula => _formula(formula),
  _ => null,
};

/// A state that holds no quantity: what an input not the temperature reads.
const MatterState _empty = MatterState();

const ExpressionType _bool = ExpressionType.boolean;

/// The body's temperature of [type], held to [input]'s valid range as
/// `LawInput.read` holds it: below [LawInput.low] the low end, above
/// [LawInput.high] the high one.
Expression _held(LawInput input, ExpressionType type) {
  Expression x = ExpressionVariable(NativeLaw.temperature, type);
  final raw = x;
  Expression k(double v) => ExpressionConstant(<double>[v], type);
  if (input.high case final high?) {
    x = ExpressionConditional(
      ExpressionBinary('>', raw, k(high), _bool),
      k(high),
      x,
    );
  }
  if (input.low case final low?) {
    x = ExpressionConditional(
      ExpressionBinary('<', raw, k(low), _bool),
      k(low),
      x,
    );
  }
  return x;
}

bool _isTemperature(LawInput input) => input.id == MatterState.temperatureId;

/// `TableLaw.interpolate` written out: the ends, then the segment of the
/// last point at or below the input, `y0 + (y1 - y0) * ((x - x0) / (x1 -
/// x0))` with the two differences the same doubles Dart subtracts.
Expression _table(TableLaw table) {
  const type = ExpressionType.float;
  if (!_isTemperature(table.input)) {
    return ExpressionConstant(<double>[table.at(_empty)], type);
  }
  final xs = table.xs, ys = table.ys;
  final last = xs.length - 1;
  final x = _held(table.input, type);
  Expression k(double v) => ExpressionConstant(<double>[v], type);
  Expression segment(int i) => ExpressionBinary(
    '+',
    k(ys[i]),
    ExpressionBinary(
      '*',
      k(ys[i + 1] - ys[i]),
      ExpressionBinary(
        '/',
        ExpressionBinary('-', x, k(xs[i]), type),
        k(xs[i + 1] - xs[i]),
        type,
      ),
      type,
    ),
    type,
  );
  var inside = segment(0);
  for (var i = 1; i < last; i++) {
    inside = ExpressionConditional(
      ExpressionBinary('>=', x, k(xs[i]), _bool),
      segment(i),
      inside,
    );
  }
  return ExpressionConditional(
    ExpressionBinary('<=', x, k(xs[0]), _bool),
    k(ys[0]),
    ExpressionConditional(
      ExpressionBinary('>=', x, k(xs[last]), _bool),
      k(ys[last]),
      inside,
    ),
  );
}

Expression _formula(FormulaLaw formula) =>
    formula.parsed.accept(_Bind(formula.inputs));

/// A formula's tree with each variable bound: the temperature to the
/// body's, held to its range; any other input to its value in a state that
/// does not hold it.
final class _Bind extends ExpressionVisitor<Expression> {
  _Bind(this.inputs);

  final Map<String, LawInput> inputs;

  @override
  Expression visitConstant(ExpressionConstant expression) => expression;

  @override
  Expression visitVariable(ExpressionVariable expression) {
    final input = inputs[expression.name];
    if (input == null) return expression;
    return _isTemperature(input)
        ? _held(input, expression.type)
        : ExpressionConstant(<double>[input.read(_empty)], expression.type);
  }

  @override
  Expression visitConstruct(ExpressionConstruct expression) =>
      ExpressionConstruct(<Expression>[
        for (final argument in expression.arguments) argument.accept(this),
      ], expression.type);

  @override
  Expression visitSwizzle(ExpressionSwizzle expression) => ExpressionSwizzle(
    expression.target.accept(this),
    expression.components,
    expression.type,
  );

  @override
  Expression visitNegate(ExpressionNegate expression) =>
      ExpressionNegate(expression.operand.accept(this));

  @override
  Expression visitNot(ExpressionNot expression) =>
      ExpressionNot(expression.operand.accept(this));

  @override
  Expression visitBinary(ExpressionBinary expression) => ExpressionBinary(
    expression.op,
    expression.left.accept(this),
    expression.right.accept(this),
    expression.type,
  );

  @override
  Expression visitCall(ExpressionCall expression) =>
      ExpressionCall(expression.builtin, <Expression>[
        for (final argument in expression.arguments) argument.accept(this),
      ], expression.type);

  @override
  Expression visitConditional(ExpressionConditional expression) =>
      ExpressionConditional(
        expression.condition.accept(this),
        expression.then.accept(this),
        expression.otherwise.accept(this),
      );

  @override
  Expression visitUnknown(Expression expression) =>
      throw UnsupportedError('a law of ${expression.runtimeType}');
}

/// Keeps a body's material in the core what its laws say at a state the
/// Dart side holds — a `MaterialStateComponent`'s, with a plugin's
/// quantities and a pressure the core does not know — by evaluating them
/// here and passing the numbers.
///
/// **Only when they move.** [update] evaluates each of
/// [NativeLawProperty.ofBody]'s laws at the state and passes a value only
/// when it is more than [threshold] (a share of the value last passed) from
/// it, so a body whose state creeps does not cost a call a step. A value
/// is passed as a law of that one number ([NativeWorld.setLaw]), which the
/// core writes into the material at the next step without touching the
/// rest of it: its fuel, its fire.
///
/// For a law of the temperature alone [NativeWorld.setMaterialLaws] is
/// the better path: the core reads it every step at the body's own
/// temperature, with nothing to pass.
final class NativeMaterialTracker {
  /// A tracker of [body]'s [material] in [world], passing a value again once
  /// it has moved by more than [threshold] of the one last passed, a
  /// fraction (a thousandth unless given). Nothing is passed until [update].
  NativeMaterialTracker(
    this.world,
    this.body,
    this.material, {
    this.threshold = 1e-3,
  });

  /// The world the body is in, which [update] passes the values to.
  final NativeWorld world;

  /// The body whose material is kept.
  final NativeBody body;

  /// The material whose laws [update] evaluates; a property it gives no
  /// law for is left as the core has it.
  final PhysicalMaterial material;

  /// How far a value moves, as a share of the one last passed, before it
  /// is passed again.
  final double threshold;

  /// What was last passed, by property.
  final Map<NativeLawProperty, double> _passed = <NativeLawProperty, double>{};

  /// Evaluates the laws at [state] and passes those that moved; returns
  /// the properties it passed.
  List<NativeLawProperty> update(MatterState state) {
    final passed = <NativeLawProperty>[];
    for (final property in NativeLawProperty.ofBody) {
      final law = property.of(material);
      if (law == null) continue;
      final value = law.at(state);
      final before = _passed[property];
      if (before != null &&
          (value - before).abs() <= threshold * before.abs()) {
        continue;
      }
      world.setLaw(body, property, NativeLaw.of(ConstantLaw(value)));
      _passed[property] = value;
      passed.add(property);
    }
    return passed;
  }
}

/// An expression of the engine's language run by the C core: a probe's
/// `derived:` quantity, a law, anything [parseExpression] reads.
///
/// Compiled to bytecode here and loaded into the core; [run] answers what
/// `CompiledExpression.evaluate` answers, bit for bit, on every platform,
/// whether the core is built in f32 or f64: the interpreter computes in
/// binary64 either way. Freed by [dispose].
final class NativeExpression {
  /// [expression] compiled and loaded into the core.
  ///
  /// Throws an [UnsupportedError] for a node or a builtin the bytecode has
  /// no instruction for (a host's own), and a [StateError] when the core
  /// refuses the program or has no memory for it.
  NativeExpression(this.expression)
    : _bytecode = ExpressionBytecode.compile(expression) {
    final bytes = _bytecode.encode();
    final at = c.coreAlloc(bytes.length);
    try {
      c.setU8s(at, bytes);
      _program = c.f3d_program_load(at, bytes.length);
    } finally {
      c.coreFree(at);
    }
    if (_program == 0) {
      throw StateError('the physics core refused the program');
    }
    var lanes = 0;
    for (final input in _bytecode.inputs) {
      lanes += input.width;
    }
    _width = _bytecode.resultWidth;
    _inputs = c.coreAlloc(8 * (lanes > 0 ? lanes : 1));
    _result = c.coreAlloc(8 * 4);
    _finalizer.attach(this, (_program, _inputs, _result), detach: this);
  }

  static final Finalizer<(int, int, int)> _finalizer =
      Finalizer<(int, int, int)>((held) {
        c.f3d_program_free(held.$1);
        c.coreFree(held.$2);
        c.coreFree(held.$3);
      });

  /// What was compiled.
  final Expression expression;

  final ExpressionBytecode _bytecode;
  int _program = 0;
  int _inputs = 0;
  int _result = 0;
  int _width = 0;

  /// The variables [run] takes, in its order: where a tree walk first
  /// meets each.
  List<String> get variables => <String>[
    for (final input in _bytecode.inputs) input.name,
  ];

  /// The value, given each of [variables]' components in order, in the
  /// coherent SI unit of its type.
  List<double> run(List<List<double>> values) {
    if (_program == 0) throw StateError('this expression was disposed');
    final inputs = _bytecode.inputs;
    if (values.length != inputs.length) {
      throw ArgumentError.value(
        values.length,
        'values',
        'not one list for each of ${variables.join(', ')}',
      );
    }
    var at = 0;
    for (var i = 0; i < inputs.length; i++) {
      if (values[i].length != inputs[i].width) {
        throw ArgumentError.value(
          values[i],
          inputs[i].name,
          'not ${inputs[i].width} components',
        );
      }
      for (final component in values[i]) {
        c.writeF64(_inputs + 8 * at++, component);
      }
    }
    final wrote = c.f3d_program_run(_program, _inputs, _result);
    return <double>[for (var i = 0; i < wrote; i++) c.readF64(_result + 8 * i)];
  }

  /// The value, given each variable's components by name.
  List<double> runNamed(Map<String, List<double>> values) => run(<List<double>>[
    for (final name in variables)
      values[name] ?? (throw ArgumentError('no value for "$name"')),
  ]);

  /// How many numbers [run] answers.
  int get width => _width;

  /// Frees it in the core. Calling it again does nothing.
  void dispose() {
    if (_program == 0) return;
    _finalizer.detach(this);
    c.f3d_program_free(_program);
    c.coreFree(_inputs);
    c.coreFree(_result);
    _program = 0;
  }
}
