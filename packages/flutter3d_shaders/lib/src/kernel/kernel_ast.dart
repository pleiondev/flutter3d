/// The tree a kernel language kernel is read into, typed — 1.0.
///
/// **Private to this package**, so it is not frozen with the contract: the
/// two translators read it, and the public face is `ComputeKernel`. When the
/// material language moves onto the expression language of
/// `flutter3d_foundation`, this tree moves with it and nothing outside
/// notices.
///
/// Every expression carries its [KType], decided once by the parser, so the
/// WGSL emitter and the Dart compiler never infer a type of their own and
/// cannot disagree about one.
library;

import 'dart:typed_data';

final Float32List _f32 = Float32List(1);

/// [value] as the nearest f32: what every f32 the language computes is.
double roundToF32(double value) {
  _f32[0] = value;
  return _f32[0];
}

/// A type in the kernel language.
final class KType {
  const KType._(this.name, this.components, {this.scalar});

  static const KType f32 = KType._('f32', 1);
  static const KType i32 = KType._('i32', 1);
  static const KType u32 = KType._('u32', 1);
  static const KType boolean = KType._('bool', 1);
  static const KType vec2 = KType._('vec2', 2, scalar: f32);
  static const KType vec3 = KType._('vec3', 3, scalar: f32);
  static const KType vec4 = KType._('vec4', 4, scalar: f32);

  /// The invocation's id: three `u32`s, read one at a time.
  static const KType uvec3 = KType._('uvec3', 3, scalar: u32);

  /// An integer literal before it meets a type; `i32` where it meets none.
  static const KType abstractInt = KType._('abstract int', 1);

  /// A float literal before it meets a type; `f32` where it meets none.
  static const KType abstractFloat = KType._('abstract float', 1);

  final String name;
  final int components;

  /// The component type of a vector; null for a scalar.
  final KType? scalar;

  bool get isVector => scalar != null;
  bool get isInteger => this == i32 || this == u32 || this == abstractInt;
  bool get isFloat => this == f32 || this == abstractFloat;
  bool get isNumericScalar => isInteger || isFloat;
  bool get isAbstract => this == abstractInt || this == abstractFloat;

  /// The concrete type an abstract literal becomes on its own.
  KType get concrete => switch (this) {
    abstractInt => i32,
    abstractFloat => f32,
    _ => this,
  };

  static KType vector(int components) => switch (components) {
    2 => vec2,
    3 => vec3,
    4 => vec4,
    _ => f32,
  };

  @override
  String toString() => name;
}

/// What a binding is: a class with constants, as every set that may grow
/// is in a published package, even one private to it.
final class KBindingKind {
  const KBindingKind._(this.name);

  /// A storage buffer of scalars.
  static const KBindingKind buffer = KBindingKind._('buffer');

  /// A texture a kernel reads texels of with `load`.
  static const KBindingKind texture = KBindingKind._('texture');

  /// A storage texture a kernel writes texels of with `store`.
  static const KBindingKind image = KBindingKind._('image');

  final String name;

  @override
  String toString() => name;
}

/// One declared binding, in declaration order: its index is its WGSL
/// binding number in group zero.
final class KBinding {
  const KBinding({
    required this.name,
    required this.kind,
    required this.element,
    required this.writable,
    required this.index,
    required this.line,
    this.atomic = false,
  });

  final String name;
  final KBindingKind kind;

  /// An `atomic` buffer (kernel language 2): read and written only through
  /// the atomic calls, each element by any number of invocations at once.
  final bool atomic;

  /// The scalar a buffer holds; [KType.vec4] for a texture or an image,
  /// whose texels are RGBA8 read and written as four floats.
  final KType element;

  /// A `read_write` buffer, or an image.
  final bool writable;
  final int index;
  final int line;
}

/// A local, or a loop's counter.
final class KLocal {
  KLocal(this.name, this.type, {required this.mutable});
  final String name;
  final KType type;
  final bool mutable;
}

/// Every expression, typed.
sealed class KExpr {
  const KExpr(this.type);
  final KType type;
}

final class KIntLiteral extends KExpr {
  const KIntLiteral(this.value, super.type);
  final int value;
}

final class KFloatLiteral extends KExpr {
  const KFloatLiteral(this.value, this.text, super.type);

  /// The value as an f32 would hold it: a number of the kernel's, unitless.
  final double value;

  /// As written, for the WGSL emitter: a literal stays the literal.
  final String text;
}

final class KBoolLiteral extends KExpr {
  const KBoolLiteral(this.value) : super(KType.boolean);
  final bool value;
}

final class KLocalRef extends KExpr {
  KLocalRef(this.local) : super(local.type);
  final KLocal local;
}

/// `id`, the global invocation id.
final class KInvocationId extends KExpr {
  const KInvocationId() : super(KType.uvec3);
}

/// `buffer[index]`.
final class KBufferRead extends KExpr {
  KBufferRead(this.binding, this.index) : super(binding.element);
  final KBinding binding;
  final KExpr index;
}

/// `atomicLoad(buffer, index)`, `atomicExchange(buffer, index, value)` or
/// `atomicAdd(buffer, index, value)` on an `atomic` buffer: the element's
/// value before the call, which [op] — `load`, `exchange`, `add` — leaves
/// changed in one step no other invocation sees half of. [value] is null
/// for a load.
final class KAtomic extends KExpr {
  KAtomic(this.op, this.binding, this.index, this.value)
    : super(binding.element);
  final String op;
  final KBinding binding;
  final KExpr index;
  final KExpr? value;
}

/// `len(buffer)`: how many elements it holds.
final class KBufferLength extends KExpr {
  const KBufferLength(this.binding) : super(KType.u32);
  final KBinding binding;
}

/// `width(t)` or `height(t)` of a texture or an image.
final class KTextureSize extends KExpr {
  const KTextureSize(this.binding, {required this.height}) : super(KType.u32);
  final KBinding binding;
  final bool height;
}

/// `load(texture, x, y)`: the texel as four floats.
final class KTextureLoad extends KExpr {
  const KTextureLoad(this.binding, this.x, this.y) : super(KType.vec4);
  final KBinding binding;
  final KExpr x;
  final KExpr y;
}

/// `.x`, `.xy`, `.rgb`: components of a vector, by index.
final class KSwizzle extends KExpr {
  const KSwizzle(this.target, this.components, super.type);
  final KExpr target;
  final List<int> components;
}

final class KUnary extends KExpr {
  const KUnary(this.op, this.operand, super.type);

  /// `-`, `!` or `~`.
  final String op;
  final KExpr operand;
}

/// A binary operation. Both sides already have the operation's operand
/// types: an abstract literal on one side was given the other's type.
final class KBinary extends KExpr {
  const KBinary(this.op, this.left, this.right, super.type);
  final String op;
  final KExpr left;
  final KExpr right;
}

/// A built-in function: the conversions, the arithmetic ones, `select`
/// and the vector constructors.
final class KCall extends KExpr {
  const KCall(this.function, this.arguments, super.type);
  final String function;
  final List<KExpr> arguments;
}

/// Every statement.
sealed class KStmt {
  const KStmt(this.line);
  final int line;
}

/// `let` or `var`.
final class KDeclare extends KStmt {
  const KDeclare(this.local, this.value, super.line);
  final KLocal local;
  final KExpr value;
}

/// `name = value;`, the compound forms already expanded.
final class KAssign extends KStmt {
  const KAssign(this.local, this.value, super.line);
  final KLocal local;
  final KExpr value;
}

/// `buffer[index] = value;`.
final class KBufferWrite extends KStmt {
  const KBufferWrite(this.binding, this.index, this.value, super.line);
  final KBinding binding;
  final KExpr index;
  final KExpr value;
}

/// `atomicStore(buffer, index, value);`, or `atomicAdd` or `atomicExchange`
/// as a statement, its answer let go, on an `atomic` buffer: [op] is
/// `store`, `add` or `exchange`.
final class KAtomicStore extends KStmt {
  const KAtomicStore(this.op, this.binding, this.index, this.value, super.line);
  final String op;
  final KBinding binding;
  final KExpr index;
  final KExpr value;
}

/// `store(image, x, y, value);`.
final class KImageStore extends KStmt {
  const KImageStore(this.binding, this.x, this.y, this.value, super.line);
  final KBinding binding;
  final KExpr x;
  final KExpr y;
  final KExpr value;
}

final class KIf extends KStmt {
  const KIf(this.condition, this.then, this.otherwise, super.line);
  final KExpr condition;
  final List<KStmt> then;

  /// Empty without an `else`.
  final List<KStmt> otherwise;
}

/// `for i in from .. to { }`: [counter] from [from] while below [to], by one.
final class KFor extends KStmt {
  const KFor(this.counter, this.from, this.to, this.body, super.line);
  final KLocal counter;
  final KExpr from;
  final KExpr to;
  final List<KStmt> body;
}

final class KBreak extends KStmt {
  const KBreak(super.line);
}

final class KContinue extends KStmt {
  const KContinue(super.line);
}

/// `return;`: this invocation is done.
final class KReturn extends KStmt {
  const KReturn(super.line);
}

/// One kernel, parsed and checked.
final class KKernel {
  const KKernel({
    required this.name,
    required this.languageVersion,
    required this.workgroup,
    required this.bindings,
    required this.body,
  });

  final String name;

  /// The kernel language version its source was read as.
  final int languageVersion;
  final (int, int, int) workgroup;
  final List<KBinding> bindings;
  final List<KStmt> body;
}
