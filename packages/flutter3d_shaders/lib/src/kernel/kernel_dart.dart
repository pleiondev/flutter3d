/// A kernel's tree as Dart closures: what the CPU placement runs — 1.0.
///
/// **The same arithmetic as WGSL, written down.** Every f32 operation is
/// done in double and rounded to the nearest f32, which for `+`, `-`, `*`,
/// `/` and `sqrt` is exactly the correctly rounded f32 result; integers wrap
/// at 32 bits as WGSL's do; an integer divided by zero is the dividend, its
/// remainder zero; a shift is by its amount modulo 32; `round` breaks ties
/// to even. Where a GPU is allowed to differ — an f32 division or `%` it
/// computes to 2.5 ulp, `sin`, `cos` and `pow` to its own precision, a read
/// or write outside a buffer — this answers the f32 nearest the exact value
/// and zero, and a kernel whose bytes must match on every placement keeps
/// to `+`, `-`, `*`, the integers and guarded indices.
///
/// Closures rather than a walk over the tree per invocation, so the tree is
/// read once per kernel and a dispatch costs calls, not switches.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'kernel_ast.dart';

/// A texture a kernel reads with `load`, as the CPU placement hands it.
///
/// **Implemented by a backend**, over its own texture; `KernelPixels` is
/// one over plain RGBA8 bytes. Implementable outside this package through
/// 1.x: a member added later arrives with a default body.
abstract base class KernelTexture {
  /// A texture; a subclass says what holds its texels.
  const KernelTexture();

  /// In texels.
  int get width;

  /// In texels.
  int get height;

  /// Writes the texel at ([x], [y]) of the base level into [rgba], as four
  /// floats from nought to one, or four zeros outside the texture.
  void load(int x, int y, Float32List rgba);
}

/// A storage texture a kernel writes with `store`, as the CPU placement
/// hands it.
abstract base class KernelImage {
  /// An image; a subclass says what holds its texels.
  const KernelImage();

  /// In texels.
  int get width;

  /// In texels.
  int get height;

  /// Writes [rgba] — four floats, clamped to nought and one and rounded to
  /// the nearest of 256 levels, ties to even — to the texel at ([x], [y]);
  /// nothing outside the image.
  void store(int x, int y, Float32List rgba);
}

/// RGBA8 texels in host memory, rows from the top, read and written as a
/// kernel reads and writes a texture and an image: for a test, and for a
/// backend whose textures are bytes already.
final class KernelPixels extends KernelTexture implements KernelImage {
  /// [width] × [height] texels over [rgba], four bytes each; zeros when
  /// [rgba] is not given.
  KernelPixels(this.width, this.height, {Uint8List? rgba})
    : rgba = rgba ?? Uint8List(width * height * 4) {
    if (this.rgba.length != width * height * 4) {
      throw ArgumentError(
        '${this.rgba.length} bytes are not $width × $height RGBA8 texels',
      );
    }
  }

  @override
  final int width;

  @override
  final int height;

  /// The texels, four bytes each, row by row from the top.
  final Uint8List rgba;

  @override
  void load(int x, int y, Float32List out) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      out.fillRange(0, 4, 0);
      return;
    }
    final at = (y * width + x) * 4;
    for (var c = 0; c < 4; c++) {
      out[c] = unormValue(rgba[at + c]);
    }
  }

  @override
  void store(int x, int y, Float32List value) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final at = (y * width + x) * 4;
    for (var c = 0; c < 4; c++) {
      rgba[at + c] = unormLevel(value[c]);
    }
  }
}

/// [value], clamped to `[0, 1]`, as the RGBA8 level a GPU stores for it:
/// `round(value × 255)`, the product in f32 and ties to even.
int unormLevel(double value) {
  final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
  return roundHalfEven(roundToF32(clamped * 255.0)).toInt();
}

/// [level] of 255 as the f32 a GPU reads an RGBA8 texel as.
double unormValue(int level) => roundToF32(level / 255.0);

/// [x] to the nearest whole number, ties to even, as WGSL's `round`.
double roundHalfEven(double x) {
  if (!x.isFinite) return x;
  final floor = x.floorToDouble();
  final fraction = x - floor;
  if (fraction < 0.5) return floor;
  if (fraction > 0.5) return floor + 1.0;
  return floor % 2.0 == 0.0 ? floor : floor + 1.0;
}

/// What one dispatch is handed: a binding's resource by its index.
final class KernelResources {
  KernelResources(this.buffers, this.textures, this.images);

  final List<ByteData?> buffers;
  final List<KernelTexture?> textures;
  final List<KernelImage?> images;
}

final class _Frame {
  _Frame(int slots, this.resources)
    : values = List<Object?>.filled(slots, null);

  final List<Object?> values;
  final KernelResources resources;
  int x = 0;
  int y = 0;
  int z = 0;
}

typedef _Eval = Object? Function(_Frame f);

/// What a statement says happens next.
const int _next = 0;
const int _break = 1;
const int _continue = 2;
const int _return = 3;

typedef _Exec = int Function(_Frame f);

/// [kernel] as something that runs a workgroup.
final class CompiledKernel {
  CompiledKernel(this.kernel) {
    _body = _block(kernel.body);
  }

  final KKernel kernel;
  final Map<KLocal, int> _slots = <KLocal, int>{};
  late final _Exec _body;

  int _slot(KLocal local) => _slots.putIfAbsent(local, () => _slots.length);

  /// Runs every invocation of the workgroup at ([gx], [gy], [gz]).
  void runWorkgroup(int gx, int gy, int gz, KernelResources resources) {
    final f = _Frame(_slots.length, resources);
    final (sx, sy, sz) = kernel.workgroup;
    for (var lz = 0; lz < sz; lz++) {
      for (var ly = 0; ly < sy; ly++) {
        for (var lx = 0; lx < sx; lx++) {
          f
            ..x = gx * sx + lx
            ..y = gy * sy + ly
            ..z = gz * sz + lz;
          _body(f);
        }
      }
    }
  }

  // ------------------------------------------------------------ statements

  _Exec _block(List<KStmt> statements) {
    final compiled = statements.map(_statement).toList(growable: false);
    if (compiled.length == 1) return compiled.single;
    return (f) {
      for (final s in compiled) {
        final r = s(f);
        if (r != _next) return r;
      }
      return _next;
    };
  }

  _Exec _statement(KStmt s) {
    switch (s) {
      case KDeclare(:final local, :final value) ||
          KAssign(:final local, :final value):
        final slot = _slot(local);
        final e = _expr(value);
        return (f) {
          f.values[slot] = e(f);
          return _next;
        };
      case KBufferWrite(:final binding, :final index, :final value):
        final at = binding.index;
        final i = _expr(index);
        final v = _expr(value);
        final write = _writer(binding.element);
        return (f) {
          final buffer = _buffer(f, at, binding);
          final n = i(f)! as int;
          final value = v(f);
          if (n >= 0 && n * 4 + 4 <= buffer.lengthInBytes) {
            write(buffer, n * 4, value);
          }
          return _next;
        };
      case KAtomicStore(:final op, :final binding, :final index, :final value):
        final apply = _expr(
          KAtomic(op == 'store' ? 'exchange' : op, binding, index, value),
        );
        return (f) {
          apply(f);
          return _next;
        };
      case KImageStore(:final binding, :final x, :final y, :final value):
        final at = binding.index;
        final ex = _expr(x);
        final ey = _expr(y);
        final ev = _expr(value);
        return (f) {
          final image = f.resources.images[at];
          if (image == null) throw _unbound(binding);
          image.store(ex(f)! as int, ey(f)! as int, ev(f)! as Float32List);
          return _next;
        };
      case KIf(:final condition, :final then, :final otherwise):
        final c = _expr(condition);
        final t = _block(then);
        final o = otherwise.isEmpty ? null : _block(otherwise);
        return (f) {
          if (c(f)! as bool) return t(f);
          return o == null ? _next : o(f);
        };
      case KFor(:final counter, :final from, :final to, :final body):
        final slot = _slot(counter);
        final start = _expr(from);
        final end = _expr(to);
        final run = _block(body);
        final unsigned = counter.type == KType.u32;
        return (f) {
          var i = start(f)! as int;
          while (i < (end(f)! as int)) {
            f.values[slot] = i;
            final r = run(f);
            if (r == _return) return _return;
            if (r == _break) break;
            i = unsigned ? (i + 1).toUnsigned(32) : (i + 1).toSigned(32);
          }
          return _next;
        };
      case KBreak():
        return (f) => _break;
      case KContinue():
        return (f) => _continue;
      case KReturn():
        return (f) => _return;
    }
  }

  static StateError _unbound(KBinding binding) => StateError(
    'the ${binding.kind.name} "${binding.name}" was dispatched unbound',
  );

  static ByteData _buffer(_Frame f, int at, KBinding binding) =>
      f.resources.buffers[at] ?? (throw _unbound(binding));

  static void Function(ByteData, int, Object?) _writer(KType element) =>
      switch (element) {
        KType.f32 => (b, o, v) => b.setFloat32(o, v! as double, Endian.little),
        KType.i32 => (b, o, v) => b.setInt32(o, v! as int, Endian.little),
        _ => (b, o, v) => b.setUint32(o, v! as int, Endian.little),
      };

  // ----------------------------------------------------------- expressions

  _Eval _expr(KExpr e) {
    switch (e) {
      case KIntLiteral(:final value):
        return (f) => value;
      case KFloatLiteral(:final value):
        final rounded = roundToF32(value);
        return (f) => rounded;
      case KBoolLiteral(:final value):
        return (f) => value;
      case KLocalRef(:final local):
        final slot = _slot(local);
        return (f) => f.values[slot];
      case KInvocationId():
        return (f) => Uint32List.fromList(<int>[f.x, f.y, f.z]);
      case KBufferRead(:final binding, :final index):
        final at = binding.index;
        final i = _expr(index);
        return switch (binding.element) {
          KType.f32 => (f) {
            final b = _buffer(f, at, binding);
            final n = i(f)! as int;
            return n >= 0 && n * 4 + 4 <= b.lengthInBytes
                ? b.getFloat32(n * 4, Endian.little)
                : 0.0;
          },
          KType.i32 => (f) {
            final b = _buffer(f, at, binding);
            final n = i(f)! as int;
            return n >= 0 && n * 4 + 4 <= b.lengthInBytes
                ? b.getInt32(n * 4, Endian.little)
                : 0;
          },
          _ => (f) {
            final b = _buffer(f, at, binding);
            final n = i(f)! as int;
            return n >= 0 && n * 4 + 4 <= b.lengthInBytes
                ? b.getUint32(n * 4, Endian.little)
                : 0;
          },
        };
      case KAtomic(:final op, :final binding, :final index, :final value):
        // Invocations run one after another here, so an atomic is the plain
        // read, then the write, with nothing between.
        final at = binding.index;
        final i = _expr(index);
        final v = value == null ? null : _expr(value);
        final signed = binding.element == KType.i32;
        return (f) {
          final b = _buffer(f, at, binding);
          final n = i(f)! as int;
          if (n < 0 || n * 4 + 4 > b.lengthInBytes) return 0;
          final old = signed
              ? b.getInt32(n * 4, Endian.little)
              : b.getUint32(n * 4, Endian.little);
          if (v == null) return old;
          final given = v(f)! as int;
          final next = op == 'add' ? old + given : given;
          if (signed) {
            b.setInt32(n * 4, next.toSigned(32), Endian.little);
          } else {
            b.setUint32(n * 4, next.toUnsigned(32), Endian.little);
          }
          return old;
        };
      case KBufferLength(:final binding):
        final at = binding.index;
        return (f) => _buffer(f, at, binding).lengthInBytes ~/ 4;
      case KTextureSize(:final binding, :final height):
        final at = binding.index;
        final image = binding.kind == KBindingKind.image;
        return (f) {
          final ({int width, int height}) size;
          if (image) {
            final i = f.resources.images[at] ?? (throw _unbound(binding));
            size = (width: i.width, height: i.height);
          } else {
            final t = f.resources.textures[at] ?? (throw _unbound(binding));
            size = (width: t.width, height: t.height);
          }
          return height ? size.height : size.width;
        };
      case KTextureLoad(:final binding, :final x, :final y):
        final at = binding.index;
        final ex = _expr(x);
        final ey = _expr(y);
        return (f) {
          final t = f.resources.textures[at] ?? (throw _unbound(binding));
          final out = Float32List(4);
          t.load(ex(f)! as int, ey(f)! as int, out);
          return out;
        };
      case KSwizzle(:final target, :final components):
        if (target is KInvocationId && components.length == 1) {
          return switch (components.single) {
            0 => (f) => f.x,
            1 => (f) => f.y,
            _ => (f) => f.z,
          };
        }
        final t = _expr(target);
        if (components.length == 1) {
          final c = components.single;
          return (f) => (t(f)! as Float32List)[c];
        }
        return (f) {
          final v = t(f)! as Float32List;
          return Float32List.fromList(<double>[
            for (final c in components) v[c],
          ]);
        };
      case KUnary(:final op, :final operand, :final type):
        final o = _expr(operand);
        return switch ((op, type)) {
          ('!', _) => (f) => !(o(f)! as bool),
          ('~', KType.u32) => (f) => (~(o(f)! as int)).toUnsigned(32),
          ('~', _) => (f) => (~(o(f)! as int)).toSigned(32),
          ('-', KType.f32) => (f) => -(o(f)! as double),
          ('-', KType.i32) => (f) => (-(o(f)! as int)).toSigned(32),
          _ => (f) => _map(o(f)! as Float32List, (double v) => -v),
        };
      case KBinary(:final op, :final left, :final right):
        return _binary(op, left, right);
      case KCall(:final function, :final arguments, :final type):
        return _call(function, arguments, type);
    }
  }

  static Float32List _map(Float32List v, double Function(double) g) {
    final out = Float32List(v.length);
    for (var i = 0; i < v.length; i++) {
      out[i] = g(v[i]);
    }
    return out;
  }

  /// [a] times [b] modulo 2³², without a product above 2⁵³: right on the
  /// web too, where an integer is a double.
  static int _mul32(int a, int b) {
    final ua = a.toUnsigned(32);
    final ub = b.toUnsigned(32);
    final low = (ua & 0xFFFF) * ub;
    final high = (((ua >>> 16) * ub) & 0xFFFF) * 0x10000;
    return (low + high).toUnsigned(32);
  }

  _Eval _binary(String op, KExpr left, KExpr right) {
    final l = _expr(left);
    final r = _expr(right);
    switch (op) {
      case '&&':
        return (f) => (l(f)! as bool) && (r(f)! as bool);
      case '||':
        return (f) => (l(f)! as bool) || (r(f)! as bool);
      case '==':
        return (f) => _equal(l(f), r(f));
      case '!=':
        return (f) => !_equal(l(f), r(f));
      case '<':
        return (f) => (l(f)! as num) < (r(f)! as num);
      case '<=':
        return (f) => (l(f)! as num) <= (r(f)! as num);
      case '>':
        return (f) => (l(f)! as num) > (r(f)! as num);
      case '>=':
        return (f) => (l(f)! as num) >= (r(f)! as num);
    }
    final a = left.type;
    final b = right.type;
    if (a.isVector || b.isVector) {
      final double Function(double, double) g = switch (op) {
        '+' => (x, y) => x + y,
        '-' => (x, y) => x - y,
        '*' => (x, y) => x * y,
        _ => (x, y) => x / y,
      };
      final n = (a.isVector ? a : b).components;
      return (f) {
        final x = l(f)!;
        final y = r(f)!;
        final out = Float32List(n);
        for (var i = 0; i < n; i++) {
          // Stored into an f32 list, so each component is rounded once.
          out[i] = g(
            x is Float32List ? x[i] : x as double,
            y is Float32List ? y[i] : y as double,
          );
        }
        return out;
      };
    }
    if (a == KType.f32) {
      return switch (op) {
        '+' => (f) => roundToF32((l(f)! as double) + (r(f)! as double)),
        '-' => (f) => roundToF32((l(f)! as double) - (r(f)! as double)),
        '*' => (f) => roundToF32((l(f)! as double) * (r(f)! as double)),
        '/' => (f) => roundToF32((l(f)! as double) / (r(f)! as double)),
        _ => (f) => roundToF32((l(f)! as double).remainder(r(f)! as double)),
      };
    }
    final unsigned = a == KType.u32;
    int wrap(int v) => unsigned ? v.toUnsigned(32) : v.toSigned(32);
    return switch (op) {
      '+' => (f) => wrap((l(f)! as int) + (r(f)! as int)),
      '-' => (f) => wrap((l(f)! as int) - (r(f)! as int)),
      '*' => (f) => wrap(_mul32(l(f)! as int, r(f)! as int)),
      '/' => (f) {
        final x = l(f)! as int;
        final y = r(f)! as int;
        if (y == 0) return x;
        if (!unsigned && x == -0x80000000 && y == -1) return x;
        return x ~/ y;
      },
      '%' => (f) {
        final x = l(f)! as int;
        final y = r(f)! as int;
        if (y == 0) return 0;
        if (!unsigned && x == -0x80000000 && y == -1) return 0;
        return x.remainder(y);
      },
      '&' => (f) => wrap((l(f)! as int) & (r(f)! as int)),
      '|' => (f) => wrap((l(f)! as int) | (r(f)! as int)),
      '^' => (f) => wrap((l(f)! as int) ^ (r(f)! as int)),
      '<<' => (f) => wrap((l(f)! as int) << ((r(f)! as int) & 31)),
      _ =>
        (f) => unsigned
            ? (l(f)! as int) >>> ((r(f)! as int) & 31)
            : (l(f)! as int) >> ((r(f)! as int) & 31),
    };
  }

  static bool _equal(Object? a, Object? b) => a == b;

  _Eval _call(String function, List<KExpr> arguments, KType type) {
    final args = arguments.map(_expr).toList(growable: false);
    final from = arguments.isEmpty ? null : arguments.first.type;
    switch (function) {
      case 'f32':
        final a = args.single;
        return switch (from) {
          KType.boolean => (f) => (a(f)! as bool) ? 1.0 : 0.0,
          KType.f32 => a,
          _ => (f) => roundToF32((a(f)! as int).toDouble()),
        };
      case 'i32' || 'u32':
        final a = args.single;
        final unsigned = function == 'u32';
        return switch (from) {
          KType.boolean => (f) => (a(f)! as bool) ? 1 : 0,
          KType.f32 => (f) => _truncate(a(f)! as double, unsigned: unsigned),
          _ =>
            unsigned
                ? (f) => (a(f)! as int).toUnsigned(32)
                : (f) => (a(f)! as int).toSigned(32),
        };
      case 'min' || 'max':
        final a = args[0];
        final b = args[1];
        final pick = function == 'min' ? math.min<num> : math.max<num>;
        if (type.isVector) {
          return (f) {
            final x = a(f)! as Float32List;
            final y = b(f)! as Float32List;
            return Float32List.fromList(<double>[
              for (var i = 0; i < x.length; i++) pick(x[i], y[i]).toDouble(),
            ]);
          };
        }
        return (f) => pick(a(f)! as num, b(f)! as num);
      case 'clamp':
        final x = args[0];
        final lo = args[1];
        final hi = args[2];
        if (type.isVector) {
          return (f) {
            final v = x(f)! as Float32List;
            final a = lo(f)! as Float32List;
            final b = hi(f)! as Float32List;
            return Float32List.fromList(<double>[
              for (var i = 0; i < v.length; i++)
                math.min(math.max(v[i], a[i]), b[i]),
            ]);
          };
        }
        return (f) => math.min<num>(
          math.max<num>(x(f)! as num, lo(f)! as num),
          hi(f)! as num,
        );
      case 'abs':
        final a = args.single;
        return switch (type) {
          KType.f32 => (f) => (a(f)! as double).abs(),
          KType.i32 => (f) => (a(f)! as int).abs().toSigned(32),
          KType.u32 => a,
          _ => (f) => _map(a(f)! as Float32List, (double v) => v.abs()),
        };
      case 'pow':
        final a = args[0];
        final b = args[1];
        double g(double x, double y) => roundToF32(math.pow(x, y).toDouble());
        if (type.isVector) {
          return (f) {
            final x = a(f)! as Float32List;
            final y = b(f)! as Float32List;
            return Float32List.fromList(<double>[
              for (var i = 0; i < x.length; i++) g(x[i], y[i]),
            ]);
          };
        }
        return (f) => g(a(f)! as double, b(f)! as double);
      case 'floor' || 'ceil' || 'round' || 'trunc' || 'sqrt' || 'sin' || 'cos':
        final a = args.single;
        final double Function(double) g = switch (function) {
          'floor' => (v) => v.floorToDouble(),
          'ceil' => (v) => v.ceilToDouble(),
          'round' => roundHalfEven,
          'trunc' => (v) => v.truncateToDouble(),
          'sin' => (v) => roundToF32(math.sin(v)),
          'cos' => (v) => roundToF32(math.cos(v)),
          _ => (v) => roundToF32(math.sqrt(v)),
        };
        if (type.isVector) return (f) => _map(a(f)! as Float32List, g);
        return (f) => g(a(f)! as double);
      case 'select':
        final c = args[0];
        final a = args[1];
        final b = args[2];
        return (f) => (c(f)! as bool) ? a(f) : b(f);
      default: // vec2, vec3, vec4
        final n = type.components;
        return (f) {
          final out = Float32List(n);
          var at = 0;
          for (final a in args) {
            final v = a(f)!;
            if (v is Float32List) {
              for (final c in v) {
                out[at++] = c;
              }
            } else {
              out[at++] = v as double;
            }
          }
          // One scalar fills every component.
          if (at == 1) out.fillRange(1, n, out[0]);
          return out;
        };
    }
  }

  /// [v] toward zero, clamped to the type's range; NaN is zero.
  static int _truncate(double v, {required bool unsigned}) {
    if (v.isNaN) return 0;
    final t = v.truncateToDouble();
    if (unsigned) {
      if (t <= 0) return 0;
      if (t >= 4294967295.0) return 0xFFFFFFFF;
      return t.toInt();
    }
    if (t <= -2147483648.0) return -0x80000000;
    if (t >= 2147483647.0) return 0x7FFFFFFF;
    return t.toInt();
  }
}
