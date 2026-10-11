/// The core's interpreter of the expression bytecode answers what the Dart
/// one answers, bit for bit: on every expression fixture of
/// flutter3d_foundation and every law of the catalogue, through the library
/// the hook builds (f32) and through the core built both ways in C.
///
/// **Where f32 cannot be bit-identical, and what is held instead.** The
/// interpreter runs in binary64 in both builds, so a program's answer is
/// Dart's to the bit in both. What a body's material holds is not: in the
/// f32 core the body's temperature is an f32, and the value a law writes is
/// rounded to f32 once. So a law set on a body is held to Dart's value *at
/// that f32 temperature*, rounded to f32 — the bits the f32 core can hold —
/// and in the f64 core to Dart's own double.
///
/// NaN is compared as NaN: what bits a NaN has is the hardware's (0/0 is
/// 0x7FF8… on ARM and 0xFFF8… on x86) in Dart as in C.
///
/// Mutation: shorten one of `exp`'s coefficients in `f3d_expr.c` to twelve
/// digits, or write the C `mix` as `a·(1 − t) + b·t`, and the programs
/// differ; write a table's segment as `y0 + (x - x0) · (dy / dx)`, the
/// slope divided first, and a catalogue law differs between its points.
@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_foundation/internal.dart' show ExpressionBytecode;
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import '../../flutter3d_foundation/test/expression_fixtures.dart';
import 'c_build.dart';

/// [value]'s bits, every NaN one NaN.
String _bits(double value) {
  if (value.isNaN) return 'nan';
  final bytes = ByteData(8)..setFloat64(0, value);
  String half(int at) => bytes.getUint32(at).toRadixString(16).padLeft(8, '0');
  return '${half(0)}${half(4)}';
}

List<String> _all(List<double> values) => <String>[
  for (final v in values) _bits(v),
];

double _f32(double value) => (Float32List(1)..[0] = value)[0];

/// Every law of the catalogue, by where it is.
Map<String, PropertyLaw> _laws() => <String, PropertyLaw>{
  for (final material in Materials.all)
    for (final group in material.groups)
      for (final MapEntry(:key, :value) in group.laws.entries)
        '${material.id} ${group.name}.$key': value,
};

/// The temperatures a law is read at: across what a game and a laboratory
/// reach, every point of a table and the middle of every segment, and its
/// valid range's ends and just past them.
List<double> _temperatures(PropertyLaw law) {
  final out = <double>[for (var t = 100.0; t <= 2500.0; t += 37.25) t];
  if (law is TableLaw) {
    for (var i = 0; i < law.xs.length; i++) {
      out.add(law.xs[i]);
      if (i + 1 < law.xs.length) out.add((law.xs[i] + law.xs[i + 1]) / 2);
    }
    out
      ..add(law.xs.first - 1)
      ..add(law.xs.last + 1);
  }
  if (law is FormulaLaw) {
    for (final input in law.inputs.values) {
      for (final end in <double?>[input.low, input.high]) {
        if (end != null) out.addAll(<double>[end - 0.5, end, end + 0.5]);
      }
    }
  }
  return out;
}

/// The corpus for the C driver, and the lines it must print.
final class _Corpus {
  final BytesBuilder bytes = BytesBuilder();
  int programs = 0;

  /// Per build: f32 and f64.
  final List<String> f32 = <String>[];
  final List<String> f64 = <String>[];

  /// What a line is, where it is not a fixture's run.
  final Map<int, String> notes = <int, String>{};

  void _u32(int v) => bytes.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void _f64(double v) => bytes.add(
    (ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List(),
  );

  void program(
    Uint8List code,
    List<List<double>> runs,
    List<List<double>> answers,
  ) {
    programs++;
    _u32(0);
    _u32(code.length);
    bytes.add(code);
    _u32(runs.length);
    for (var i = 0; i < runs.length; i++) {
      runs[i].forEach(_f64);
      final line = _all(answers[i]).map(_hex).join(' ');
      f32.add(line);
      f64.add(line);
    }
  }

  void law(NativeLaw law, List<double> temperatures) {
    programs++;
    _u32(1);
    final code = law.bytecode;
    _u32(code.length);
    bytes.add(code);
    _u32(temperatures.length);
    for (final t in temperatures) {
      _f64(t);
      f32.add(_hex(_bits(_f32(law.at(_f32(t))))));
      f64.add(_hex(_bits(law.at(t))));
      notes[f64.length - 1] = '${law.law} on a body at $t K';
    }
  }

  /// The driver prints sixteen digits.
  static String _hex(String bits) => bits.padLeft(16, '0');

  Uint8List done() {
    final head = ByteData(4)..setUint32(0, programs, Endian.little);
    return Uint8List.fromList(<int>[
      ...head.buffer.asUint8List(),
      ...bytes.toBytes(),
    ]);
  }
}

/// The driver's lines, a NaN of any bits read as one NaN.
List<String> _lines(String out) => <String>[
  for (final line in out.split('\n'))
    if (line.isNotEmpty)
      line
          .split(' ')
          .map((word) {
            if (word == 'refused') return word;
            final v =
                (ByteData(8)
                      ..setUint32(0, int.parse(word.substring(0, 8), radix: 16))
                      ..setUint32(4, int.parse(word.substring(8), radix: 16)))
                    .getFloat64(0);
            return v.isNaN ? 'nan'.padLeft(16, '0') : word;
          })
          .join(' '),
];

void main() {
  setUpAll(loadPhysicsCore);

  test('the core answers every expression fixture as Dart does', () {
    var compared = 0;
    for (final fixture in expressionFixtures) {
      final expression = parseExpression(fixture.source, scope: fixture.scope);
      final closures = CompiledExpression(expression);
      final bytecode = ExpressionBytecode.compile(expression);
      final core = NativeExpression(expression);
      addTearDown(core.dispose);
      for (final values in fixture.values) {
        final dart = _all(
          closures.evaluate(<List<double>>[
            for (final name in closures.variables) values[name]!,
          ]),
        );
        expect(_all(bytecode.runNamed(values)), dart);
        expect(
          _all(core.runNamed(values)),
          dart,
          reason: '${fixture.source} at $values',
        );
        compared++;
      }
    }
    expect(compared, greaterThan(50));
  });

  test('the core answers every builtin as Dart does on numbers that round', () {
    // The fixtures' values are kind to some builtins (a mix at a quarter of
    // a doubling is exact either way it is written); these are not: an LCG
    // over -4 to 4, a half and its neighbours, and the edges of each
    // function's domain.
    var seed = 12345;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return seed / 0x7FFFFFFF * 8 - 4;
    }

    final numbers = <double>[
      for (var i = 0; i < 400; i++) next(),
      0.5,
      -0.5,
      1.5,
      -2.5,
      0.49999999999999994,
      1,
      -1,
      0,
      -0.0,
      1e-300,
      1e300,
      710,
      -746,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ];
    const sources = <String>[
      'mix(a, b, c)',
      'smoothstep(a, b, c)',
      'clamp(a, b, c)',
      'step(a, b) + min(a, b) + max(a, b)',
      'pow(abs(a), b)',
      'pow(a, floor(b))',
      'atan2(a, b)',
      'sin(a) + cos(b) + tan(c)',
      'asin(a / 4.0) + acos(b / 4.0) + atan(c)',
      'exp(a * 30.0) + log(abs(b) * 1000.0)',
      'floor(a * 7.3) + fract(b * 3.1) + sign(c) + abs(a)',
      'sqrt(abs(a)) + length(vec3(a, b, c)) + dot(vec2(a, b), vec2(c, a))',
      'normalize(vec3(a, b, c)).y + (a > b && b <= c ? 1.0 : 0.0)',
      'a == b || a != c ? a / b : -c',
    ];
    final scope = ExpressionScope(
      variables: const <String, ExpressionType>{
        'a': ExpressionType.float,
        'b': ExpressionType.float,
        'c': ExpressionType.float,
      },
    );
    var compared = 0;
    for (final source in sources) {
      final expression = parseExpression(source, scope: scope);
      final bytecode = ExpressionBytecode.compile(expression);
      final core = NativeExpression(expression);
      addTearDown(core.dispose);
      for (var i = 0; i + 2 < numbers.length; i++) {
        final values = <String, List<double>>{
          'a': <double>[numbers[i]],
          'b': <double>[numbers[i + 1]],
          'c': <double>[numbers[(i * 7 + 2) % numbers.length]],
        };
        expect(
          _all(core.runNamed(values)),
          _all(bytecode.runNamed(values)),
          reason: '$source at $values',
        );
        compared++;
      }
    }
    expect(compared, greaterThan(5000));
  });

  test('the core answers every law of the catalogue as Dart does', () {
    var compared = 0;
    for (final MapEntry(key: where, value: law) in _laws().entries) {
      final compiled = NativeLaw.of(law);
      expect(compiled, isNotNull, reason: where);
      final core = NativeExpression(compiled!.expression);
      addTearDown(core.dispose);
      for (final t in _temperatures(law)) {
        // The law written as an expression of the temperature is the law.
        final dart = law.at(MaterialState.at(temperature: t));
        expect(_bits(compiled.at(t)), _bits(dart), reason: '$where at $t K');
        final answer = core.variables.isEmpty
            ? core.run(const <List<double>>[])
            : core.run(<List<double>>[
                <double>[t],
              ]);
        expect(_bits(answer.single), _bits(dart), reason: '$where at $t K');
        compared++;
      }
    }
    expect(compared, greaterThan(10000));
  });

  test('a body reads its law at its temperature, in f32, from the next '
      'step', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final steel = Materials.steel;
    final body = world.addBody(position: Vector3.zero());
    world
      ..gravity = Vector3.zero()
      ..setMaterial(body, NativeMaterial.of(steel))
      ..setTemperature(body, 900);
    expect(
      world.setMaterialLaws(body, steel),
      contains(NativeLawProperty.specificHeat),
    );
    final law = NativeLaw.of(steel.thermal!.specificHeat!)!;
    // Not before the step: the material is still as set.
    expect(
      world.materialOf(body).specificHeat,
      _f32(steel.thermal!.specificHeat!.value),
    );
    world.step(1 / 60);
    expect(world.materialOf(body).specificHeat, _f32(law.at(_f32(900))));
    expect(
      law.at(900),
      steel.thermal!.specificHeat!.at(MaterialState.at(temperature: 900)),
    );
    // Taken off, it keeps the value last written.
    world
      ..setLaw(body, NativeLawProperty.specificHeat, null)
      ..setTemperature(body, 400)
      ..step(1 / 60);
    expect(world.materialOf(body).specificHeat, _f32(law.at(_f32(900))));
  });

  test('a tracker passes a state the core does not know, when it moves', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    const damp = PhysicalMaterial(
      id: 'bog.peat',
      name: 'peat',
      phase: MaterialPhase.solid,
      thermal: ThermalProperties(
        specificHeat: FormulaLaw(
          1900.0,
          expression: '1900 [J/(kg·K)] * (1 + 2.2 * w)',
          inputs: <String, LawInput>{'w': LawInput('bog.wetness')},
        ),
        conductivity: ConstantLaw(0.06),
        source: 'a test',
      ),
    );
    final body = world.addBody(position: Vector3.zero());
    world
      ..gravity = Vector3.zero()
      ..setMaterial(body, NativeMaterial.of(damp));
    final tracker = NativeMaterialTracker(world, body, damp);
    MaterialState wet(double w) => MaterialState(
      quantities: <String, Quantity>{'bog.wetness': Quantity(w, Unit.one)},
    );
    expect(tracker.update(wet(0.5)), hasLength(2));
    world.step(1 / 60);
    expect(world.materialOf(body).specificHeat, _f32(1900 * (1 + 2.2 * 0.5)));
    // Within the threshold, nothing is passed.
    expect(tracker.update(wet(0.5000001)), isEmpty);
    expect(tracker.update(wet(0.6)), <NativeLawProperty>[
      NativeLawProperty.specificHeat,
    ]);
  });

  test('the core built in f32 and in f64 answers the same programs to the '
      'bits each can hold', () async {
    final corpus = _Corpus();
    for (final fixture in expressionFixtures) {
      final expression = parseExpression(fixture.source, scope: fixture.scope);
      final bytecode = ExpressionBytecode.compile(expression);
      final runs = <List<double>>[];
      final answers = <List<double>>[];
      for (final values in fixture.values) {
        runs.add(<double>[
          for (final input in bytecode.inputs) ...values[input.name]!,
        ]);
        answers.add(bytecode.runNamed(values));
      }
      corpus.program(bytecode.encode(), runs, answers);
    }
    // Every law of the catalogue as a program, and every specific heat that
    // changes with temperature set on a body as well.
    for (final MapEntry(key: where, value: law) in _laws().entries) {
      final compiled = NativeLaw.of(law)!;
      final temperatures = _temperatures(law);
      corpus.program(
        compiled.bytecode,
        <List<double>>[
          for (final t in temperatures)
            if (compiled.expression is ExpressionConstant)
              const <double>[]
            else
              <double>[t],
        ],
        <List<double>>[
          for (final t in temperatures) <double>[compiled.at(t)],
        ],
      );
      if (where.endsWith('thermal.specificHeat') && law.dependsOnState) {
        // A body is above absolute zero.
        corpus.law(compiled, <double>[
          for (final t in temperatures)
            if (t > 0) t,
        ]);
      }
    }
    final scratch = Directory.systemTemp.createTempSync('f3d_law_parity');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final file = File('${scratch.path}/corpus.bin')
      ..writeAsBytesSync(corpus.done());
    for (final (name, defines, expected)
        in <(String, List<String>, List<String>)>[
          ('f32', const <String>[], corpus.f32),
          ('f64', const <String>['-DF3D_REAL_DOUBLE'], corpus.f64),
        ]) {
      final binary = '${scratch.path}/parity_$name';
      // The core compiled once per precision and kept (`c_build.dart`).
      final built = await buildAgainstCore(
        'cc',
        <String>[
          '-std=c11',
          '-O2',
          '-ffp-contract=off',
          '-fno-fast-math',
          ...defines,
          if (Platform.isLinux) '-pthread',
        ],
        <String>['test/c/law_parity.c'],
        binary,
      );
      expect(built.exitCode, 0, reason: '${built.stdout}${built.stderr}');
      final ran = Process.runSync(binary, <String>[file.path]);
      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      final lines = _lines('${ran.stdout}');
      expect(lines.length, expected.length, reason: name);
      for (var i = 0; i < lines.length; i++) {
        expect(
          lines[i],
          expected[i],
          reason: '$name, line $i: ${corpus.notes[i] ?? 'a program'}',
        );
      }
    }
  });
}
