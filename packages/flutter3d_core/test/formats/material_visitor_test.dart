/// The material language's tree, and a frame resource's size, read through
/// a visitor whose `visitUnknown` answers for a kind it predates.
///
///     dart test test/formats/material_visitor_test.dart
///
/// What it holds: a kind of expression, statement or size that none of the
/// translators knows — a later minor's, or a plugin's own — reaches
/// `visitUnknown`, and each of the engine's translators (the GLSL emitter,
/// the folder, the software evaluator) refuses it by name rather than
/// compiling it to something else.
///
/// Mutation: make `Expression.accept` answer `visitConstant` for an
/// unknown kind, and the first test fails; take the `accept` override off
/// `ExpressionBinary`, and the counting visitor misses the operator.
library;

import 'package:flutter3d_core/flutter3d_core.dart'
    show AbsolutePixels, FrameFraction, ResourceSize, ResourceSizeVisitor;
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        CompiledExpression,
        ExpressionCodec,
        Expression,
        ExpressionBinary,
        ExpressionCall,
        ExpressionConstant,
        ExpressionConstruct,
        ExpressionNegate,
        ExpressionSwizzle,
        ExpressionType;
import 'package:test/test.dart';

const String _source = '''
material Visited {
  param float strength = 2.0;

  fragment {
    let edge = clamp(nDotV, 0.0, 1.0) * strength;
    return vec4(albedo * edge, alpha);
  }
}
''';

/// A plugin's own expression: the length of the albedo, which no translator
/// in the engine knows.
final class _AlbedoLength extends Expression {
  const _AlbedoLength() : super(ExpressionType.float);
}

/// A plugin's own statement.
final class _Comment extends MaterialStatement {
  const _Comment();
}

/// Counts the kinds it meets, and says what it met for an unknown one.
final class _Census extends MaterialExpressionVisitor<String> {
  final Map<String, int> seen = <String, int>{};

  String _saw(String kind) {
    seen[kind] = (seen[kind] ?? 0) + 1;
    return kind;
  }

  @override
  String visitConstant(ExpressionConstant expression) => _saw('constant');

  @override
  String visitInputRef(MaterialInputRef expression) => _saw('input');

  @override
  String visitParamRef(MaterialParamRef expression) => _saw('param');

  @override
  String visitLocalRef(MaterialLocalRef expression) => _saw('local');

  @override
  String visitConstruct(ExpressionConstruct expression) {
    for (final argument in expression.arguments) {
      argument.accept(this);
    }
    return _saw('construct');
  }

  @override
  String visitSwizzle(ExpressionSwizzle expression) {
    expression.target.accept(this);
    return _saw('swizzle');
  }

  @override
  String visitNegate(ExpressionNegate expression) {
    expression.operand.accept(this);
    return _saw('negate');
  }

  @override
  String visitBinary(ExpressionBinary expression) {
    expression.left.accept(this);
    expression.right.accept(this);
    return _saw('binary');
  }

  @override
  String visitCall(ExpressionCall expression) {
    for (final argument in expression.arguments) {
      argument.accept(this);
    }
    return _saw('call');
  }

  @override
  String visitSample(MaterialSample expression) {
    expression.uv.accept(this);
    return _saw('sample');
  }

  @override
  String visitUnknown(Expression expression) => _saw('unknown');
}

final class _SizeName extends ResourceSizeVisitor<String> {
  const _SizeName();

  @override
  String visitFrameFraction(FrameFraction size) => 'fraction ${size.divisor}';

  @override
  String visitAbsolutePixels(AbsolutePixels size) =>
      'pixels ${size.width}x${size.height}';

  @override
  String visitUnknown(ResourceSize size) => 'unknown';
}

/// A plugin's own size: the frame's width, square.
final class _Square extends ResourceSize {
  const _Square();

  @override
  (int, int) resolve(int frameWidth, int frameHeight) =>
      (frameWidth, frameWidth);
}

MaterialProgram _withBody(
  MaterialProgram program,
  List<MaterialStatement> body,
) => MaterialProgram(
  name: program.name,
  parameters: program.parameters,
  textures: program.textures,
  body: body,
  inputsUsed: program.inputsUsed,
);

void main() {
  test('a kind no visitor knows reaches visitUnknown', () {
    final census = _Census();
    expect(const _AlbedoLength().accept(census), 'unknown');
    expect(census.seen, <String, int>{'unknown': 1});
  });

  test('every kind of a parsed body reaches its own method', () {
    final program = parseMaterial(_source);
    final census = _Census();
    final returned = program.body.last as MaterialReturn;
    returned.value.accept(census);
    final let = program.body.first as MaterialLet;
    let.value.accept(census);
    expect(census.seen.containsKey('unknown'), isFalse);
    expect(census.seen['binary'], greaterThanOrEqualTo(2));
    expect(census.seen['call'], 1);
    expect(census.seen['param'], 1);
    expect(census.seen['local'], 1);
  });

  test('the GLSL emitter refuses an expression it does not know, by name', () {
    final program = parseMaterial(_source);
    final foreign = _withBody(program, <MaterialStatement>[
      const MaterialReturn(
        ExpressionConstruct(<Expression>[
          _AlbedoLength(),
          _AlbedoLength(),
          _AlbedoLength(),
          _AlbedoLength(),
        ], ExpressionType.vec4),
      ),
    ]);
    expect(
      () => emitMaterialFragment(foreign),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('not an expression this build of the material language'),
        ),
      ),
    );
  });

  test('the folder and the evaluator refuse a statement they do not know', () {
    final program = parseMaterial(_source);
    final foreign = _withBody(program, <MaterialStatement>[
      const _Comment(),
      ...program.body,
    ]);
    expect(
      () => specializeMaterial(foreign, const MaterialVariant('Visited')),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('not a statement this build'),
        ),
      ),
    );
    expect(() => emitMaterialFragment(foreign), throwsA(isA<ArgumentError>()));
  });

  test('a material expression is an expression of the expression language', () {
    final program = parseMaterial(_source);
    final let = program.body.first as MaterialLet;
    // A reader that knows only the expression language: an input and a
    // parameter are variables to it, and it runs the tree.
    final compiled = CompiledExpression(let.value);
    expect(compiled.variables, <String>['nDotV', 'strength']);
    expect(
      compiled.evaluateNamed(<String, Object>{'nDotV': 0.25, 'strength': 2.0}),
      <double>[0.5],
    );
    expect(
      const ExpressionCodec().encode(let.value),
      '(clamp(nDotV, 0.0, 1.0) * strength)',
    );
    // And `sample`, which only a material has, is unknown to it.
    final sampled = parseMaterial('''
material Sampled {
  texture base = base_color_texture;
  fragment { return sample(base, uv); }
}
''');
    final returned = sampled.body.single as MaterialReturn;
    expect(
      () => CompiledExpression(returned.value),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a resource size is read by its kind, and an unknown one says so', () {
    const name = _SizeName();
    expect(const FrameFraction(2).accept(name), 'fraction 2');
    expect(const AbsolutePixels(64, 32).accept(name), 'pixels 64x32');
    expect(const _Square().accept(name), 'unknown');
    expect(const _Square().resolve(640, 480), (640, 640));
  });
}
