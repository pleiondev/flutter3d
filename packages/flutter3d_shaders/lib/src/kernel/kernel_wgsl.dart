/// A kernel's tree as WGSL: what WebGPU and the wgpu sidecar compile — 1.0.
///
/// Every binding is in group zero, numbered in declaration order; every name
/// the source chose is prefixed (`b_` for a binding, `l_` for a local), so
/// a kernel may call a local `ptr` or `loop` without meeting a WGSL keyword;
/// the entry point is `main`. Every operation is parenthesised, so the
/// precedence is the tree's and never WGSL's.
///
/// **Every f32 sum, difference and product is rounded where the source
/// rounds it.** A GPU compiler may fuse `a * b + c` into one multiply-add,
/// rounded once where the source rounds twice, and under fast math may
/// reorder a sum; Metal's does both. The particle step came out one ulp off
/// the CPU's in eight values of sixteen hundred, and the skinning pass, a
/// sum of four terms, in a third of its values. WGSL has no switch for
/// either, so each result passes through `f3d_exact`: a bit cast and an
/// inclusive or with a zero the compiler cannot see is zero (the top bit of
/// the invocation's z), which neither a fusion nor a reordering can look
/// through. It costs two integer operations an operation; the four kernels
/// conformance runs then give the Dart kernel's bytes on wgpu over Metal and
/// on Chrome's Dawn over Metal. A quotient and a square root are not
/// covered: a GPU may compute them to a few ulp, and no rounding afterwards
/// brings the exact one back.
///
/// **An inclusive or, because a barrier meets itself.** Dawn compiles under
/// Metal's relaxed math, which folds `0.0 + x` to `x`, so a sum that starts
/// at zero wraps one barrier directly in another. It was an exclusive or,
/// and two of those with one value cancel: the product beneath came out
/// bare and fused into the next sum, and the skinning kernel was an ulp off
/// in 26 values of 512 on Dawn. A second inclusive or with the same zero
/// leaves the first standing.
///
/// **An image store is handed its level's own value.** A sum that lands
/// halfway between two levels was stored half up on Dawn, where the Dart
/// kernel and wgpu round it to even, and the blur kernel was a level off in
/// 12 channels of 1024. `f3d_unorm8` rounds to the level, ties to even
/// (WGSL's `round`), and stores the level over 255, which any conversion
/// reads back as that level.
library;

import 'kernel_ast.dart';

/// The entry point every translated kernel has.
const String kernelEntryPoint = 'main';

/// [kernel] as one WGSL module.
String emitWgsl(KKernel kernel) => _Emitter().module(kernel);

final class _Emitter {
  /// The vector sizes, one for a scalar, whose products went through an
  /// `f3d_exact`.
  final Set<int> _exact = <int>{};

  /// Whether the kernel stores to an image, and so needs `f3d_unorm8`.
  bool _storesImage = false;

  String module(KKernel kernel) {
    final body = StringBuffer();
    _block(body, kernel.body, 1);
    final out = StringBuffer()
      ..writeln('// ${kernel.name}, translated from the kernel language.');
    for (final b in kernel.bindings) {
      final declaration = switch (b.kind) {
        KBindingKind.buffer =>
          'var<storage, ${b.writable ? 'read_write' : 'read'}> b_${b.name}: '
              'array<${_type(b.element)}>',
        KBindingKind.texture => 'var b_${b.name}: texture_2d<f32>',
        KBindingKind.image =>
          'var b_${b.name}: texture_storage_2d<rgba8unorm, write>',
        _ => throw UnsupportedError('WGSL has no binding for ${b.kind}'),
      };
      out.writeln('@group(0) @binding(${b.index}) $declaration;');
    }
    if (_exact.isNotEmpty) {
      out
        ..writeln()
        ..writeln('// Zero, and not provably so: see f3d_exact.')
        ..writeln('var<private> f3d_zero: u32;');
      for (final n in _exact.toList()..sort()) {
        final (name, f, u) = n == 1
            ? ('f3d_exact', 'f32', 'u32')
            : ('f3d_exact$n', 'vec$n<f32>', 'vec$n<u32>');
        final zero = n == 1 ? 'f3d_zero' : '$u(f3d_zero)';
        out.writeln(
          'fn $name(x: $f) -> $f { return bitcast<$f>(bitcast<$u>(x) | '
          '$zero); }',
        );
      }
    }
    if (_storesImage) {
      out
        ..writeln()
        ..writeln(
          '// The level a store means, ties to even, as every device reads '
          'it.',
        )
        ..writeln('fn f3d_unorm8(v: vec4<f32>) -> vec4<f32> {')
        ..writeln(
          '  return round(clamp(v, vec4<f32>(0.0f), vec4<f32>(1.0f)) * '
          '255.0f) / 255.0f;',
        )
        ..writeln('}');
    }
    final (x, y, z) = kernel.workgroup;
    out
      ..writeln()
      ..writeln('@compute @workgroup_size($x, $y, $z)')
      ..writeln(
        'fn $kernelEntryPoint(@builtin(global_invocation_id) f3d_id: '
        'vec3<u32>) {',
      );
    if (_exact.isNotEmpty) out.writeln('  f3d_zero = f3d_id.z >> 31u;');
    out
      ..write(body)
      ..writeln('}');
    return out.toString();
  }

  static String _type(KType type) => switch (type) {
    KType.vec2 => 'vec2<f32>',
    KType.vec3 => 'vec3<f32>',
    KType.vec4 => 'vec4<f32>',
    KType.uvec3 => 'vec3<u32>',
    _ => type.concrete.name,
  };

  void _block(StringBuffer out, List<KStmt> statements, int depth) {
    final indent = '  ' * depth;
    for (final s in statements) {
      switch (s) {
        case KDeclare(:final local, :final value):
          out.writeln(
            '$indent${local.mutable ? 'var' : 'let'} l_${local.name}: '
            '${_type(local.type)} = ${_expr(value)};',
          );
        case KAssign(:final local, :final value):
          out.writeln('${indent}l_${local.name} = ${_expr(value)};');
        case KBufferWrite(:final binding, :final index, :final value):
          out.writeln(
            '${indent}b_${binding.name}[${_expr(index)}] = ${_expr(value)};',
          );
        case KImageStore(:final binding, :final x, :final y, :final value):
          _storesImage = true;
          out.writeln(
            '${indent}textureStore(b_${binding.name}, '
            '${_coordinates(x, y)}, f3d_unorm8(${_expr(value)}));',
          );
        case KIf(:final condition, :final then, :final otherwise):
          out.writeln('${indent}if (${_expr(condition)}) {');
          _block(out, then, depth + 1);
          if (otherwise.isEmpty) {
            out.writeln('$indent}');
          } else {
            out.writeln('$indent} else {');
            _block(out, otherwise, depth + 1);
            out.writeln('$indent}');
          }
        case KFor(:final counter, :final from, :final to, :final body):
          final c = 'l_${counter.name}';
          final one = counter.type == KType.u32 ? '1u' : '1i';
          out.writeln(
            '${indent}for (var $c: ${_type(counter.type)} = ${_expr(from)}; '
            '$c < ${_expr(to)}; $c = $c + $one) {',
          );
          _block(out, body, depth + 1);
          out.writeln('$indent}');
        case KBreak():
          out.writeln('${indent}break;');
        case KContinue():
          out.writeln('${indent}continue;');
        case KReturn():
          out.writeln('${indent}return;');
      }
    }
  }

  String _coordinates(KExpr x, KExpr y) =>
      'vec2<i32>(${_asI32(x)}, ${_asI32(y)})';

  String _asI32(KExpr e) =>
      e.type == KType.i32 ? _expr(e) : 'bitcast<i32>(${_expr(e)})';

  String _expr(KExpr e) => switch (e) {
    KIntLiteral(:final value, :final type) => _int(value, type),
    KFloatLiteral(:final value) => _float(value),
    KBoolLiteral(:final value) => '$value',
    KLocalRef(:final local) => 'l_${local.name}',
    KInvocationId() => 'f3d_id',
    KBufferRead(:final binding, :final index) =>
      'b_${binding.name}[${_expr(index)}]',
    KBufferLength(:final binding) => 'arrayLength(&b_${binding.name})',
    KTextureSize(:final binding, :final height) =>
      'textureDimensions(b_${binding.name}).${height ? 'y' : 'x'}',
    KTextureLoad(:final binding, :final x, :final y) =>
      'textureLoad(b_${binding.name}, ${_coordinates(x, y)}, 0)',
    KSwizzle(:final target, :final components) =>
      '(${_expr(target)}).${components.map((c) => 'xyzw'[c]).join()}',
    KUnary(:final op, :final operand) => '($op${_expr(operand)})',
    KBinary(:final op, :final left, :final right, :final type) => switch (op) {
      // The shift amount is masked to the bit width, as the Dart kernel
      // masks it, so the two agree on an amount of 32 or more.
      '<<' || '>>' => '(${_expr(left)} $op (${_expr(right)} & 31u))',
      '+' || '-' || '*' when type == KType.f32 || type.scalar == KType.f32 =>
        _exactly('${_expr(left)} $op ${_expr(right)}', type.components),
      _ => '(${_expr(left)} $op ${_expr(right)})',
    },
    KCall(:final function, :final arguments) => _call(function, arguments),
  };

  String _exactly(String product, int components) {
    _exact.add(components);
    return '${components == 1 ? 'f3d_exact' : 'f3d_exact$components'}'
        '($product)';
  }

  String _call(String function, List<KExpr> arguments) {
    final args = arguments.map(_expr).toList();
    return switch (function) {
      // The source reads `select(condition, then, otherwise)`; WGSL's order
      // is the other way round.
      'select' => 'select(${args[2]}, ${args[1]}, ${args[0]})',
      'vec2' || 'vec3' || 'vec4' => '$function<f32>(${args.join(', ')})',
      _ => '$function(${args.join(', ')})',
    };
  }

  static String _int(int value, KType type) {
    if (type == KType.u32) return '${value}u';
    // The one i32 whose magnitude has no i32 literal.
    if (value == -0x80000000) return '(-2147483647i - 1i)';
    return value < 0 ? '(-${-value}i)' : '${value}i';
  }

  /// An f32 as a WGSL literal that reads back as exactly that f32: the
  /// shortest decimal of the double, which already holds an f32 exactly.
  static String _float(double value) {
    final text = value == value.truncateToDouble() && value.abs() < 1e15
        ? value.toStringAsFixed(1)
        : '$value';
    return value < 0 ? '(${text}f)' : '${text}f';
  }
}
