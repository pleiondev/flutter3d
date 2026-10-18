/// A compact register bytecode for the expression language, and a Dart
/// interpreter for it.
///
/// **Internal in 1.0.** Nothing here is exported and no file the engine
/// writes holds it. It is laid down now so that a later minor can publish
/// it as an addition, for a C core or a Wasm plugin that evaluates a law
/// without Dart: the format carries [expressionBytecodeVersion] in a
/// header, and the tests hold its interpreter to the closure compiler,
/// bit for bit, on every expression fixture and on every expression of the
/// `.f3dmat` fixtures.
///
/// ## The format
///
/// Little-endian throughout.
///
/// ```text
/// header        'F3DX'  u16 version  u16 flags (0)
///               u16 lanes  u16 constants  u16 dimensions  u16 inputs
///               u16 instructions  u16 result lane  u16 result width
///               u16 result dimension
/// constants     f64 × constants
/// dimensions    (i8 per base of `Dimension.bases`, in its order — 8 in
///               version 1: kg m s A K mol cd rad,
///               u8 1 for a bool) × dimensions
/// inputs        (u16 name length, UTF-8 name, u16 lane, u16 width,
///               u16 dimension) × inputs
/// instructions  (u16 × 8: op, width | flags << 8, dst, a, b, c,
///               dimension, 0) × instructions
/// ```
///
/// **Registers are lanes of doubles.** A register is a run of `width`
/// lanes starting at its index; the host writes each input's components
/// into its lanes, in the coherent unit of its dimension, before the run.
/// Every instruction writes fresh lanes, so a run is a straight line with
/// no jumps, and `? :` is a [ExpressionOp.select] of two computed values,
/// which gives the same value the closures' short circuit does.
///
/// **Typed registers, units checked at compile time.** Every instruction
/// names the dimension of what it writes, from the table; [verify] checks
/// each one against its operands' (a sum of one dimension, a product of
/// two, `sqrt` halving, `pow` of a quantity only by a constant whole
/// exponent) before anything runs, so a program whose units do not add up
/// is refused when it is loaded, as the parser refuses its text.
///
/// **Flags** mark an operand of one lane that is spread across `width`
/// lanes, GLSL's broadcasting: bit 0 for `a`, bit 1 for `b`, bit 2 for `c`.
///
/// ## What a C port needs
///
/// IEEE 754 binary64 `+ - * /`, a correctly rounded `sqrt`, `floor`, the
/// six comparisons, and no fused multiply-add (`-ffp-contract=off`); the
/// transcendental ops ([ExpressionOp.sin] … [ExpressionOp.pow]) port
/// `portable_math.dart` as written, never the platform's libm. The scalar
/// kernels (`expression_kernels.dart`) port line for line, in their order
/// of operations: a dot product sums from nought, lane 0 first. Nothing in
/// the encoding is a closure or a Dart object: an interpreter is a switch
/// over [ExpressionOp] in a loop.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../exceptions.dart';
import '../portable_math.dart';
import '../units.dart';
import 'expression_ast.dart';
import 'expression_kernels.dart';

/// The version of the bytecode format this build writes and reads.
const int expressionBytecodeVersion = 1;

/// `F3DX`, the first four bytes of an encoded program.
const List<int> expressionBytecodeMagic = <int>[0x46, 0x33, 0x44, 0x58];

/// The operation codes. Numbers, not an enum: they are the format.
abstract final class ExpressionOp {
  /// Copies `width` constants from pool index `a` into lanes from `dst`.
  static const int loadConstant = 1;

  /// Copies `width` lanes from `a` to `dst`.
  static const int move = 2;

  /// Writes `width` lanes picked from the register at `a`: lane `i` takes the
  /// component in bits `2i` and `2i + 1` of `b`.
  static const int swizzle = 3;

  /// Writes minus each of `width` lanes from `a`.
  static const int negate = 4;

  /// Writes one lane: one where lane `a` is nought, nought otherwise.
  static const int not = 5;

  /// Writes `a + b` lane by lane, either operand spread by its flag.
  static const int add = 6;

  /// Writes `a - b` lane by lane, either operand spread by its flag.
  static const int subtract = 7;

  /// Writes `a * b` lane by lane, either operand spread by its flag.
  static const int multiply = 8;

  /// Writes `a / b` lane by lane, either operand spread by its flag.
  static const int divide = 9;

  /// Writes one lane: one where lane `a` is below lane `b`, nought otherwise.
  static const int less = 10;

  /// Writes one lane: one where lane `a` is at most lane `b`, nought
  /// otherwise.
  static const int lessEqual = 11;

  /// Writes one lane: one where lane `a` is above lane `b`, nought otherwise.
  static const int greater = 12;

  /// Writes one lane: one where lane `a` is at least lane `b`, nought
  /// otherwise.
  static const int greaterEqual = 13;

  /// Writes one lane: one where lanes `a` and `b` are equal, nought
  /// otherwise.
  static const int equal = 14;

  /// Writes one lane: one where lanes `a` and `b` differ, nought otherwise.
  static const int notEqual = 15;

  /// Writes one lane: one where lanes `a` and `b` are both not nought.
  static const int and = 16;

  /// Writes one lane: one where lane `a` or lane `b` is not nought.
  static const int or = 17;

  /// Copies `width` lanes from `b` where lane `a` is not nought, from `c`
  /// otherwise: the `? :` of the language, both sides computed.
  static const int select = 18;

  /// Writes one lane: the sum of the products of `width` lanes from `a` and
  /// `b`, from nought and lane 0 first.
  static const int dot = 20;

  /// Writes one lane: the square root of the sum of the squares of `width`
  /// lanes from `a`.
  static const int length = 21;

  /// Writes `width` lanes from `a` divided by their length; nought in every
  /// lane for a length of nought.
  static const int normalize = 22;

  /// Writes `a + (b - a) * c` lane by lane, each operand spread by its flag.
  static const int mix = 23;

  /// Writes `a` held between `b` and `c` lane by lane, `b` winning when they
  /// cross; each operand spread by its flag.
  static const int clamp = 24;

  /// Writes the Hermite ramp of `c` between the edges `a` and `b`, lane by
  /// lane, each operand spread by its flag.
  static const int smoothstep = 25;

  /// Writes nought where `b` is below the edge `a` and one from it, lane by
  /// lane.
  static const int step = 26;

  /// Writes `a` to the power `b` lane by lane, by `Portable.pow`.
  static const int pow = 27;

  /// Writes the smaller of `a` and `b` lane by lane, `a` when they are equal.
  static const int min = 28;

  /// Writes the larger of `a` and `b` lane by lane, `b` when they are equal.
  static const int max = 29;

  /// Writes the magnitude of each of `width` lanes from `a`.
  static const int abs = 30;

  /// Writes the correctly rounded square root of each lane from `a`.
  static const int sqrt = 31;

  /// Writes each lane from `a` rounded down to a whole number.
  static const int floor = 32;

  /// Writes what each lane from `a` is above its floor.
  static const int fract = 33;

  /// Writes the sine of each lane from `a`, in radians, by `Portable.sin`.
  static const int sin = 34;

  /// Writes the cosine of each lane from `a`, in radians, by `Portable.cos`.
  static const int cos = 35;

  /// Writes the tangent of each lane from `a`, in radians, by
  /// `Portable.tan`.
  static const int tan = 36;

  /// Writes the arcsine of each lane from `a`, in radians, by
  /// `Portable.asin`.
  static const int asin = 37;

  /// Writes the arccosine of each lane from `a`, in radians, by
  /// `Portable.acos`.
  static const int acos = 38;

  /// Writes the arctangent of each lane from `a`, in radians, by
  /// `Portable.atan`.
  static const int atan = 39;

  /// Writes the angle of (`b`, `a`) lane by lane, in radians, by
  /// `Portable.atan2`.
  static const int atan2 = 40;

  /// Writes e to the power of each lane from `a`, by `Portable.exp`.
  static const int exp = 41;

  /// Writes the natural logarithm of each lane from `a`, by `Portable.log`.
  static const int log = 42;

  /// Writes one, nought or minus one by the sign of each lane from `a`; NaN
  /// stays NaN.
  static const int sign = 43;

  /// The binary operators' codes, by the operator.
  static const Map<String, int> operators = <String, int>{
    '+': add,
    '-': subtract,
    '*': multiply,
    '/': divide,
    '<': less,
    '<=': lessEqual,
    '>': greater,
    '>=': greaterEqual,
    '==': equal,
    '!=': notEqual,
    '&&': and,
    '||': or,
  };

  /// The builtins' codes, by the builtin's name.
  static const Map<String, int> builtins = <String, int>{
    'dot': dot,
    'length': length,
    'normalize': normalize,
    'mix': mix,
    'clamp': clamp,
    'smoothstep': smoothstep,
    'step': step,
    'pow': pow,
    'min': min,
    'max': max,
    'abs': abs,
    'sqrt': sqrt,
    'floor': floor,
    'fract': fract,
    'sin': sin,
    'cos': cos,
    'tan': tan,
    'asin': asin,
    'acos': acos,
    'atan': atan,
    'atan2': atan2,
    'exp': exp,
    'log': log,
    'sign': sign,
  };
}

/// A dimension as the format stores it: the eight exponents and whether
/// it is a truth value.
final class _Dim {
  const _Dim(this.exponents, this.boolean);

  factory _Dim.of(ExpressionType type) {
    final dimension = type.dimension;
    for (final base in dimension.exponents.keys) {
      if (!Dimension.bases.contains(base) && dimension[base] != 0) {
        throw UnsupportedError(
          'the bytecode stores the eight bases only, and $type has "$base"',
        );
      }
    }
    return _Dim(<int>[
      for (final base in Dimension.bases) dimension[base],
    ], type.isBoolean);
  }

  /// How many exponents a dimension stores: one per [Dimension.bases], in
  /// their order. A build that names another base writes another format,
  /// with [expressionBytecodeVersion] raised.
  static final int count = Dimension.bases.length;

  final List<int> exponents;
  final bool boolean;

  bool get isNone => exponents.every((e) => e == 0);

  _Dim times(_Dim other, int sign) => _Dim(<int>[
    for (var i = 0; i < count; i++) exponents[i] + sign * other.exponents[i],
  ], false);

  _Dim scaled(int power) =>
      _Dim(<int>[for (final e in exponents) e * power], false);

  static final _Dim none = _Dim(List<int>.filled(count, 0), false);
  static final _Dim angle = _Dim.of(
    ExpressionType.float.withDimension(Dimension.angle),
  );

  @override
  bool operator ==(Object other) =>
      other is _Dim &&
      other.boolean == boolean &&
      Iterable<int>.generate(
        count,
      ).every((i) => exponents[i] == other.exponents[i]);

  @override
  int get hashCode => Object.hash(Object.hashAll(exponents), boolean);
}

/// One input of a program: a variable's name, the lanes the host writes it
/// into, and its type.
final class ExpressionBytecodeInput {
  /// The input [name], written into [width] lanes from [lane], of the
  /// dimension at index `_dim` of the program's table.
  const ExpressionBytecodeInput(this.name, this.lane, this.width, this._dim);

  /// The variable's name, as [ExpressionBytecode.runNamed] looks it up.
  final String name;

  /// The first lane the host writes the value into.
  final int lane;

  /// How many lanes the value takes: its count of components.
  final int width;
  final int _dim;
}

/// Thrown by [ExpressionBytecode.verify] and [ExpressionBytecode.decode]
/// for a program that is not well formed, or whose units do not add up: bytes
/// that are not what they claim to be, so a [Flutter3dFormatException].
final class ExpressionBytecodeException extends Flutter3dFormatException {
  /// A refusal that [message] explains.
  const ExpressionBytecodeException(this.message);

  @override
  final String message;

  @override
  String toString() => 'ExpressionBytecodeException: $message';
}

/// A compiled program: straight-line instructions over lanes of doubles.
final class ExpressionBytecode {
  ExpressionBytecode._(
    this._dimensions, {
    required this.lanes,
    required this.constants,
    required this.inputs,
    required this.code,
    required this.resultLane,
    required this.resultWidth,
    required this.resultDimension,
  });

  /// [expression] compiled.
  ///
  /// Throws [UnsupportedError] for a node or a builtin with no opcode (a
  /// host's own), and for a dimension over a base outside the eight.
  factory ExpressionBytecode.compile(Expression expression) {
    final compiler = _BytecodeCompiler();
    final result = compiler.register(expression);
    final program = ExpressionBytecode._(
      compiler.dimensions,
      lanes: compiler.lanes,
      constants: Float64List.fromList(compiler.constants),
      inputs: compiler.inputs,
      code: Uint16List.fromList(compiler.code),
      resultLane: result,
      resultWidth: expression.type.components,
      resultDimension: compiler.dim(expression.type),
    );
    program.verify();
    return program;
  }

  /// How many lanes a run needs.
  final int lanes;

  /// The constant pool.
  final Float64List constants;

  final List<_Dim> _dimensions;

  /// What the host writes before a run, in the order a tree walk first
  /// meets each variable.
  final List<ExpressionBytecodeInput> inputs;

  /// The instructions, eight `u16` each.
  final Uint16List code;

  /// The first lane of the value a run answers.
  final int resultLane;

  /// How many lanes the answer takes: its count of components.
  final int resultWidth;

  /// The index in the dimension table of what the answer measures.
  final int resultDimension;

  /// How many instructions there are.
  int get instructionCount => code.length ~/ 8;

  /// The value, given each input's components by name in coherent units.
  List<double> runNamed(Map<String, List<double>> values) => run(<List<double>>[
    for (final input in inputs)
      values[input.name] ??
          (throw ArgumentError('no value for "${input.name}"')),
  ]);

  /// The register file, allocated on the first run and reused by every
  /// later one: every lane a run reads is written earlier in the same run
  /// ([verify] holds a program to that), so nothing carries over.
  late final Float64List _registers = Float64List(lanes);

  /// The value, given each of [inputs]' components in order.
  List<double> run(List<List<double>> slots) {
    final r = _registers;
    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final value = slots[i];
      for (var lane = 0; lane < input.width; lane++) {
        r[input.lane + lane] = value[lane];
      }
    }
    for (var pc = 0; pc < code.length; pc += 8) {
      final op = code[pc];
      final width = code[pc + 1] & 0xFF;
      final flags = code[pc + 1] >> 8;
      final dst = code[pc + 2];
      final a = code[pc + 3];
      final b = code[pc + 4];
      final c = code[pc + 5];
      // How far each operand moves per lane: nought when its flag spreads
      // one lane across the width.
      final sa = flags & 1 != 0 ? 0 : 1;
      final sb = flags & 2 != 0 ? 0 : 1;
      final sc = flags & 4 != 0 ? 0 : 1;
      switch (op) {
        case ExpressionOp.loadConstant:
          for (var i = 0; i < width; i++) {
            r[dst + i] = constants[a + i];
          }
        case ExpressionOp.move:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a + i];
          }
        case ExpressionOp.swizzle:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a + ((b >> (2 * i)) & 3)];
          }
        case ExpressionOp.negate:
          for (var i = 0; i < width; i++) {
            r[dst + i] = -r[a + i];
          }
        case ExpressionOp.not:
          r[dst] = r[a] != 0 ? 0 : 1;
        // Each operator as `expressionOperatorAt` computes it, written out
        // under its own opcode: no symbol is looked up and no string is
        // compared per lane.
        case ExpressionOp.add:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a + i * sa] + r[b + i * sb];
          }
        case ExpressionOp.subtract:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a + i * sa] - r[b + i * sb];
          }
        case ExpressionOp.multiply:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a + i * sa] * r[b + i * sb];
          }
        case ExpressionOp.divide:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a + i * sa] / r[b + i * sb];
          }
        case ExpressionOp.less:
          r[dst] = r[a] < r[b] ? 1.0 : 0.0;
        case ExpressionOp.lessEqual:
          r[dst] = r[a] <= r[b] ? 1.0 : 0.0;
        case ExpressionOp.greater:
          r[dst] = r[a] > r[b] ? 1.0 : 0.0;
        case ExpressionOp.greaterEqual:
          r[dst] = r[a] >= r[b] ? 1.0 : 0.0;
        case ExpressionOp.equal:
          r[dst] = r[a] == r[b] ? 1.0 : 0.0;
        case ExpressionOp.notEqual:
          r[dst] = r[a] != r[b] ? 1.0 : 0.0;
        case ExpressionOp.and:
          r[dst] = r[a] != 0 && r[b] != 0 ? 1.0 : 0.0;
        case ExpressionOp.or:
          r[dst] = r[a] != 0 || r[b] != 0 ? 1.0 : 0.0;
        case ExpressionOp.select:
          for (var i = 0; i < width; i++) {
            r[dst + i] = r[a] != 0 ? r[b + i] : r[c + i];
          }
        case ExpressionOp.dot:
          var sum = 0.0;
          for (var i = 0; i < width; i++) {
            sum += r[a + i] * r[b + i];
          }
          r[dst] = sum;
        case ExpressionOp.length:
          var sum = 0.0;
          for (var i = 0; i < width; i++) {
            sum += r[a + i] * r[a + i];
          }
          r[dst] = math.sqrt(sum);
        case ExpressionOp.normalize:
          var sum = 0.0;
          for (var i = 0; i < width; i++) {
            sum += r[a + i] * r[a + i];
          }
          final length = math.sqrt(sum);
          for (var i = 0; i < width; i++) {
            r[dst + i] = length == 0 ? 0 : r[a + i] / length;
          }
        case ExpressionOp.mix:
          for (var i = 0; i < width; i++) {
            r[dst + i] = mixAt(r[a + i * sa], r[b + i * sb], r[c + i * sc]);
          }
        case ExpressionOp.clamp:
          for (var i = 0; i < width; i++) {
            r[dst + i] = clampAt(r[a + i * sa], r[b + i * sb], r[c + i * sc]);
          }
        case ExpressionOp.smoothstep:
          for (var i = 0; i < width; i++) {
            r[dst + i] = smoothstepAt(
              r[a + i * sa],
              r[b + i * sb],
              r[c + i * sc],
            );
          }
        case ExpressionOp.step:
          for (var i = 0; i < width; i++) {
            r[dst + i] = stepAt(r[a + i * sa], r[b + i * sb]);
          }
        case ExpressionOp.pow:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.pow(r[a + i * sa], r[b + i * sb]);
          }
        case ExpressionOp.min:
          for (var i = 0; i < width; i++) {
            r[dst + i] = minAt(r[a + i * sa], r[b + i * sb]);
          }
        case ExpressionOp.max:
          for (var i = 0; i < width; i++) {
            r[dst + i] = maxAt(r[a + i * sa], r[b + i * sb]);
          }
        case ExpressionOp.atan2:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.atan2(r[a + i * sa], r[b + i * sb]);
          }
        case ExpressionOp.abs:
          for (var i = 0; i < width; i++) {
            r[dst + i] = absAt(r[a + i]);
          }
        case ExpressionOp.sqrt:
          for (var i = 0; i < width; i++) {
            r[dst + i] = math.sqrt(r[a + i]);
          }
        case ExpressionOp.floor:
          for (var i = 0; i < width; i++) {
            r[dst + i] = floorAt(r[a + i]);
          }
        case ExpressionOp.fract:
          for (var i = 0; i < width; i++) {
            r[dst + i] = fractAt(r[a + i]);
          }
        case ExpressionOp.sin:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.sin(r[a + i]);
          }
        case ExpressionOp.cos:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.cos(r[a + i]);
          }
        case ExpressionOp.tan:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.tan(r[a + i]);
          }
        case ExpressionOp.asin:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.asin(r[a + i]);
          }
        case ExpressionOp.acos:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.acos(r[a + i]);
          }
        case ExpressionOp.atan:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.atan(r[a + i]);
          }
        case ExpressionOp.exp:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.exp(r[a + i]);
          }
        case ExpressionOp.log:
          for (var i = 0; i < width; i++) {
            r[dst + i] = Portable.log(r[a + i]);
          }
        case ExpressionOp.sign:
          for (var i = 0; i < width; i++) {
            r[dst + i] = signAt(r[a + i]);
          }
        default:
          throw StateError('no opcode $op');
      }
    }
    return <double>[for (var i = 0; i < resultWidth; i++) r[resultLane + i]];
  }

  // ----------------------------------------------------------- verifying

  /// Checks every instruction: its lanes in range, its widths, and its
  /// units against its operands'.
  ///
  /// Throws [ExpressionBytecodeException] naming the first that fails.
  void verify() {
    // The dimension written to each lane, and the constant a lane holds
    // when a `loadConstant` wrote it (for `pow`'s exponent).
    final laneDim = List<int?>.filled(lanes, null);
    final laneConstant = List<double?>.filled(lanes, null);
    Never refuse(int index, String why) =>
        throw ExpressionBytecodeException('instruction $index: $why');
    for (final input in inputs) {
      if (input.lane + input.width > lanes ||
          input._dim >= _dimensions.length) {
        throw ExpressionBytecodeException(
          'input "${input.name}" is out of range',
        );
      }
      for (var i = 0; i < input.width; i++) {
        laneDim[input.lane + i] = input._dim;
      }
    }
    for (var pc = 0, n = 0; pc < code.length; pc += 8, n++) {
      final op = code[pc];
      final width = code[pc + 1] & 0xFF;
      final flags = code[pc + 1] >> 8;
      final dst = code[pc + 2];
      final a = code[pc + 3];
      final b = code[pc + 4];
      final c = code[pc + 5];
      final d = code[pc + 6];
      if (width < 1 || width > 4) refuse(n, 'width $width');
      if (d >= _dimensions.length) refuse(n, 'no dimension $d');
      final out = _dimensions[d];
      final writes = switch (op) {
        ExpressionOp.dot || ExpressionOp.length || ExpressionOp.not => 1,
        _ => width,
      };
      if (dst + writes > lanes) refuse(n, 'writes past the lanes');
      _Dim read(int lane, int count, String which) {
        if (lane + count > lanes) refuse(n, '$which is past the lanes');
        final dims = <int?>{for (var i = 0; i < count; i++) laneDim[lane + i]};
        if (dims.length != 1 || dims.single == null) {
          refuse(n, '$which reads lanes nothing wrote with one dimension');
        }
        return _dimensions[dims.single!];
      }

      int span(int flag) => flags & flag != 0 ? 1 : width;
      void expect(bool ok, String why) {
        if (!ok) refuse(n, why);
      }

      switch (op) {
        case ExpressionOp.loadConstant:
          if (a + width > constants.length) refuse(n, 'no constant $a');
        case ExpressionOp.move ||
            ExpressionOp.negate ||
            ExpressionOp.length ||
            ExpressionOp.abs ||
            ExpressionOp.floor ||
            ExpressionOp.fract:
          expect(read(a, width, 'a') == out, 'changes the unit');
        case ExpressionOp.swizzle:
          final source = <int>{
            for (var i = 0; i < width; i++) (b >> 2 * i) & 3,
          };
          final top = source.reduce(math.max);
          expect(read(a, top + 1, 'a') == out, 'changes the unit');
        case ExpressionOp.not:
          expect(read(a, 1, 'a').boolean && out.boolean, 'is not of bools');
        case ExpressionOp.add || ExpressionOp.subtract:
          final x = read(a, span(1), 'a');
          final y = read(b, span(2), 'b');
          expect(x == y && x == out && !x.boolean, 'adds two units');
        case ExpressionOp.multiply || ExpressionOp.divide:
          final x = read(a, span(1), 'a');
          final y = read(b, span(2), 'b');
          expect(!x.boolean && !y.boolean, 'multiplies a bool');
          expect(
            out == x.times(y, op == ExpressionOp.multiply ? 1 : -1),
            'writes the wrong unit',
          );
        case ExpressionOp.less ||
            ExpressionOp.lessEqual ||
            ExpressionOp.greater ||
            ExpressionOp.greaterEqual ||
            ExpressionOp.equal ||
            ExpressionOp.notEqual:
          final x = read(a, 1, 'a');
          final y = read(b, 1, 'b');
          expect(x == y && out.boolean && width == 1, 'compares two units');
        case ExpressionOp.and || ExpressionOp.or:
          expect(
            read(a, 1, 'a').boolean &&
                read(b, 1, 'b').boolean &&
                out.boolean &&
                width == 1,
            'is not of bools',
          );
        case ExpressionOp.select:
          expect(read(a, 1, 'a').boolean, 'selects by a number');
          expect(
            read(b, width, 'b') == out && read(c, width, 'c') == out,
            'selects between two units',
          );
        case ExpressionOp.dot:
          expect(
            out == read(a, width, 'a').times(read(b, width, 'b'), 1),
            'writes the wrong unit',
          );
        case ExpressionOp.normalize || ExpressionOp.sign:
          read(a, width, 'a');
          expect(out == _Dim.none, 'is not a pure number');
        case ExpressionOp.mix:
          final x = read(a, span(1), 'a');
          expect(
            x == read(b, span(2), 'b') &&
                read(c, span(4), 'c') == _Dim.none &&
                x == out,
            'mixes two units',
          );
        case ExpressionOp.clamp:
          final x = read(a, span(1), 'a');
          expect(
            x == read(b, span(2), 'b') &&
                x == read(c, span(4), 'c') &&
                x == out,
            'clamps across units',
          );
        case ExpressionOp.smoothstep:
          final x = read(a, span(1), 'a');
          expect(
            x == read(b, span(2), 'b') &&
                x == read(c, span(4), 'c') &&
                out == _Dim.none,
            'smooths across units',
          );
        case ExpressionOp.step || ExpressionOp.atan2:
          expect(
            read(a, span(1), 'a') == read(b, span(2), 'b') && out == _Dim.none,
            'takes two units',
          );
        case ExpressionOp.min || ExpressionOp.max:
          final x = read(a, span(1), 'a');
          expect(x == read(b, span(2), 'b') && x == out, 'takes two units');
        case ExpressionOp.pow:
          final base = read(a, span(1), 'a');
          expect(read(b, span(2), 'b') == _Dim.none, 'raises to a unit');
          if (base.isNone) {
            expect(out == _Dim.none, 'writes the wrong unit');
          } else {
            final exponent = laneConstant[b];
            expect(
              (flags & 2 != 0 || width == 1) &&
                  exponent != null &&
                  exponent == exponent.truncateToDouble() &&
                  exponent.abs() <= expressionPowerLimit &&
                  out == base.scaled(exponent.toInt()),
              'raises a quantity to a power that is not a constant whole '
              'number from -$expressionPowerLimit to $expressionPowerLimit',
            );
          }
        case ExpressionOp.sqrt:
          final x = read(a, width, 'a');
          expect(x == out.scaled(2), 'writes the wrong unit');
        case ExpressionOp.sin || ExpressionOp.cos || ExpressionOp.tan:
          final x = read(a, width, 'a');
          expect(
            (x == _Dim.none || x == _Dim.angle) && out == _Dim.none,
            'takes an angle or a pure number',
          );
        case ExpressionOp.asin ||
            ExpressionOp.acos ||
            ExpressionOp.atan ||
            ExpressionOp.exp ||
            ExpressionOp.log:
          expect(
            read(a, width, 'a') == _Dim.none && out == _Dim.none,
            'takes a pure number',
          );
        default:
          refuse(n, 'no opcode $op');
      }
      for (var i = 0; i < writes; i++) {
        laneDim[dst + i] = d;
        laneConstant[dst + i] = op == ExpressionOp.loadConstant
            ? constants[a + i]
            : null;
      }
    }
    if (resultDimension >= _dimensions.length ||
        resultLane + resultWidth > lanes) {
      throw const ExpressionBytecodeException('the result is out of range');
    }
  }

  // ------------------------------------------------------------ encoding

  /// The program as bytes, header first.
  Uint8List encode() {
    final names = <List<int>>[
      for (final input in inputs) utf8.encode(input.name),
    ];
    final size =
        4 +
        4 +
        16 +
        constants.length * 8 +
        _dimensions.length * (_Dim.count + 1) +
        <int>[
          for (final name in names) 8 + name.length,
        ].fold<int>(0, (a, b) => a + b) +
        code.length * 2;
    final bytes = ByteData(size);
    var at = 0;
    void u8(int v) => bytes.setUint8(at++, v);
    void u16(int v) {
      bytes.setUint16(at, v, Endian.little);
      at += 2;
    }

    expressionBytecodeMagic.forEach(u8);
    u16(expressionBytecodeVersion);
    u16(0);
    for (final v in <int>[
      lanes,
      constants.length,
      _dimensions.length,
      inputs.length,
      instructionCount,
      resultLane,
      resultWidth,
      resultDimension,
    ]) {
      u16(v);
    }
    for (final k in constants) {
      bytes.setFloat64(at, k, Endian.little);
      at += 8;
    }
    for (final dim in _dimensions) {
      for (final e in dim.exponents) {
        bytes.setInt8(at++, e);
      }
      u8(dim.boolean ? 1 : 0);
    }
    for (var i = 0; i < inputs.length; i++) {
      u16(names[i].length);
      names[i].forEach(u8);
      u16(inputs[i].lane);
      u16(inputs[i].width);
      u16(inputs[i]._dim);
    }
    code.forEach(u16);
    return bytes.buffer.asUint8List();
  }

  /// The program [bytes] hold, verified.
  ///
  /// Throws [ExpressionBytecodeException] for bytes that are not one, a
  /// version this build does not read, or a program [verify] refuses.
  static ExpressionBytecode decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var at = 0;
    void need(int count) {
      if (at + count > bytes.length) {
        throw const ExpressionBytecodeException('the bytes end early');
      }
    }

    int u16() {
      need(2);
      final v = data.getUint16(at, Endian.little);
      at += 2;
      return v;
    }

    need(4);
    for (final byte in expressionBytecodeMagic) {
      if (bytes[at++] != byte) {
        throw const ExpressionBytecodeException('not F3DX bytecode');
      }
    }
    final version = u16();
    // Every version up to this build's is read; only a newer one, or none,
    // is refused.
    if (version > expressionBytecodeVersion || version < 1) {
      throw ExpressionBytecodeException(
        'bytecode version $version; this build reads up to '
        '$expressionBytecodeVersion',
      );
    }
    u16();
    final lanes = u16();
    final constantCount = u16();
    final dimensionCount = u16();
    final inputCount = u16();
    final instructionCount = u16();
    final resultLane = u16();
    final resultWidth = u16();
    final resultDimension = u16();
    need(constantCount * 8);
    final constants = Float64List(constantCount);
    for (var i = 0; i < constantCount; i++) {
      constants[i] = data.getFloat64(at, Endian.little);
      at += 8;
    }
    // The exponents, then the byte that says a bool.
    final stride = _Dim.count + 1;
    need(dimensionCount * stride);
    final dimensions = <_Dim>[
      for (var i = 0; i < dimensionCount; i++)
        _Dim(<int>[
          for (var e = 0; e < _Dim.count; e++)
            data.getInt8(at + i * stride + e),
        ], data.getUint8(at + i * stride + _Dim.count) != 0),
    ];
    at += dimensionCount * stride;
    final inputs = <ExpressionBytecodeInput>[];
    for (var i = 0; i < inputCount; i++) {
      final length = u16();
      need(length);
      final name = utf8.decode(bytes.sublist(at, at + length));
      at += length;
      inputs.add(ExpressionBytecodeInput(name, u16(), u16(), u16()));
    }
    final code = Uint16List(instructionCount * 8);
    for (var i = 0; i < code.length; i++) {
      code[i] = u16();
    }
    if (at != bytes.length) {
      throw const ExpressionBytecodeException('bytes follow the program');
    }
    return ExpressionBytecode._(
      dimensions,
      lanes: lanes,
      constants: constants,
      inputs: inputs,
      code: code,
      resultLane: resultLane,
      resultWidth: resultWidth,
      resultDimension: resultDimension,
    )..verify();
  }
}

/// Compiles a tree into instructions, every node into fresh lanes, a node
/// met twice (the same object) into the lanes it was given the first time.
final class _BytecodeCompiler extends ExpressionVisitor<int> {
  int lanes = 0;
  final List<double> constants = <double>[];
  final List<_Dim> dimensions = <_Dim>[];
  final List<ExpressionBytecodeInput> inputs = <ExpressionBytecodeInput>[];
  final List<int> code = <int>[];
  final Map<Expression, int> _done = Map<Expression, int>.identity();
  final Map<String, ExpressionBytecodeInput> _inputsByName =
      <String, ExpressionBytecodeInput>{};

  int register(Expression expression) =>
      _done[expression] ??= expression.accept(this);

  int dim(ExpressionType type) {
    final d = _Dim.of(type);
    final found = dimensions.indexOf(d);
    if (found >= 0) return found;
    dimensions.add(d);
    return dimensions.length - 1;
  }

  int allocate(int width) {
    final lane = lanes;
    lanes += width;
    if (lanes > 0xFFFF) {
      throw UnsupportedError('the expression needs more than 65535 lanes');
    }
    return lane;
  }

  int emit(
    int op,
    ExpressionType type, {
    required int width,
    int a = 0,
    int b = 0,
    int c = 0,
    int flags = 0,
    int? into,
  }) {
    final dst = into ?? allocate(op == ExpressionOp.dot ? 1 : type.components);
    code.addAll(<int>[op, width | flags << 8, dst, a, b, c, dim(type), 0]);
    return dst;
  }

  @override
  int visitConstant(ExpressionConstant expression) {
    final index = constants.length;
    constants.addAll(expression.value);
    return emit(
      ExpressionOp.loadConstant,
      expression.type,
      width: expression.value.length,
      a: index,
    );
  }

  @override
  int visitVariable(ExpressionVariable expression) {
    final known = _inputsByName[expression.name];
    if (known != null) return known.lane;
    final input = ExpressionBytecodeInput(
      expression.name,
      allocate(expression.type.components),
      expression.type.components,
      dim(expression.type),
    );
    _inputsByName[expression.name] = input;
    inputs.add(input);
    return input.lane;
  }

  @override
  int visitConstruct(ExpressionConstruct expression) {
    final parts = <(int, ExpressionType)>[
      for (final argument in expression.arguments)
        (register(argument), argument.type),
    ];
    final dst = allocate(expression.type.components);
    var offset = 0;
    for (final (lane, type) in parts) {
      emit(
        ExpressionOp.move,
        type,
        width: type.components,
        a: lane,
        into: dst + offset,
      );
      offset += type.components;
    }
    return dst;
  }

  @override
  int visitSwizzle(ExpressionSwizzle expression) {
    var packed = 0;
    for (var i = 0; i < expression.components.length; i++) {
      packed |= expression.components[i] << (2 * i);
    }
    return emit(
      ExpressionOp.swizzle,
      expression.type,
      width: expression.type.components,
      a: register(expression.target),
      b: packed,
    );
  }

  @override
  int visitNegate(ExpressionNegate expression) => emit(
    ExpressionOp.negate,
    expression.type,
    width: expression.type.components,
    a: register(expression.operand),
  );

  @override
  int visitNot(ExpressionNot expression) => emit(
    ExpressionOp.not,
    expression.type,
    width: 1,
    a: register(expression.operand),
  );

  @override
  int visitBinary(ExpressionBinary expression) {
    final a = register(expression.left);
    final b = register(expression.right);
    final width = expression.type.isBoolean ? 1 : expression.type.components;
    return emit(
      ExpressionOp.operators[expression.op] ??
          (throw UnsupportedError('no opcode for "${expression.op}"')),
      expression.type,
      width: width,
      a: a,
      b: b,
      flags: _spread(<Expression>[expression.left, expression.right], width),
    );
  }

  @override
  int visitCall(ExpressionCall expression) {
    final builtin = expression.builtin;
    final op = ExpressionOp.builtins[builtin.name];
    if (op == null ||
        !identical(ExpressionBuiltin.byName(builtin.name), builtin)) {
      throw UnsupportedError('no opcode for the builtin "${builtin.name}"');
    }
    final lanes = <int>[
      for (final argument in expression.arguments) register(argument),
    ];
    final widest = expression.arguments
        .map((a) => a.type.components)
        .fold<int>(1, math.max);
    return emit(
      op,
      expression.type,
      width: widest,
      a: lanes[0],
      b: lanes.length > 1 ? lanes[1] : 0,
      c: lanes.length > 2 ? lanes[2] : 0,
      flags: builtin.componentWise ? _spread(expression.arguments, widest) : 0,
    );
  }

  @override
  int visitConditional(ExpressionConditional expression) => emit(
    ExpressionOp.select,
    expression.type,
    width: expression.type.components,
    a: register(expression.condition),
    b: register(expression.then),
    c: register(expression.otherwise),
  );

  @override
  int visitUnknown(Expression expression) =>
      throw UnsupportedError('no opcode for ${expression.runtimeType}');

  /// The flags that spread each one-lane operand across [width] lanes.
  static int _spread(List<Expression> operands, int width) {
    var flags = 0;
    for (var i = 0; i < operands.length; i++) {
      if (operands[i].type.components == 1 && width > 1) flags |= 1 << i;
    }
    return flags;
  }
}
