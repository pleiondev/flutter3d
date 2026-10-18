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

  /// A 32-bit float.
  static const KType f32 = KType._('f32', 1);

  /// A 32-bit signed integer.
  static const KType i32 = KType._('i32', 1);

  /// A 32-bit unsigned integer.
  static const KType u32 = KType._('u32', 1);

  /// A boolean, the type of a comparison and a condition.
  static const KType boolean = KType._('bool', 1);

  /// Two f32 components.
  static const KType vec2 = KType._('vec2', 2, scalar: f32);

  /// Three f32 components.
  static const KType vec3 = KType._('vec3', 3, scalar: f32);

  /// Four f32 components: a texel as RGBA.
  static const KType vec4 = KType._('vec4', 4, scalar: f32);

  /// The invocation's id: three `u32`s, read one at a time.
  static const KType uvec3 = KType._('uvec3', 3, scalar: u32);

  /// An integer literal before it meets a type; `i32` where it meets none.
  static const KType abstractInt = KType._('abstract int', 1);

  /// A float literal before it meets a type; `f32` where it meets none.
  static const KType abstractFloat = KType._('abstract float', 1);

  /// The type as a message names it: `f32`, `vec3`, `abstract int`.
  final String name;

  /// How many components it has: one for a scalar, two to four for a
  /// vector.
  final int components;

  /// The component type of a vector; null for a scalar.
  final KType? scalar;

  /// Whether it has a [scalar] component type: a `vec` or `uvec3`.
  bool get isVector => scalar != null;

  /// Whether it is `i32`, `u32` or an integer literal not yet typed.
  bool get isInteger => this == i32 || this == u32 || this == abstractInt;

  /// Whether it is `f32` or a float literal not yet typed.
  bool get isFloat => this == f32 || this == abstractFloat;

  /// Whether it is a number with one component: an integer or a float.
  bool get isNumericScalar => isInteger || isFloat;

  /// Whether it is a literal's type that has not met a concrete one.
  bool get isAbstract => this == abstractInt || this == abstractFloat;

  /// The concrete type an abstract literal becomes on its own.
  KType get concrete => switch (this) {
    abstractInt => i32,
    abstractFloat => f32,
    _ => this,
  };

  /// Returns the f32 vector of [components], two to four; `f32` for any
  /// other count.
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

  /// The kind as the source declares it: `buffer`, `texture` or `image`.
  final String name;

  @override
  String toString() => name;
}

/// One declared binding, in declaration order: its index is its WGSL
/// binding number in group zero.
final class KBinding {
  /// The binding [name] of [kind] holding [element], declared on [line] as
  /// the [index]th; not atomic unless said.
  const KBinding({
    required this.name,
    required this.kind,
    required this.element,
    required this.writable,
    required this.index,
    required this.line,
    this.atomic = false,
  });

  /// The name the source declares and a dispatch hands its resource by.
  final String name;

  /// Whether it is a buffer, a texture or an image.
  final KBindingKind kind;

  /// An `atomic` buffer (kernel language 2): read and written only through
  /// the atomic calls, each element by any number of invocations at once.
  final bool atomic;

  /// The scalar a buffer holds; [KType.vec4] for a texture or an image,
  /// whose texels are RGBA8 read and written as four floats.
  final KType element;

  /// A `read_write` buffer, or an image.
  final bool writable;

  /// Its place among the kernel's bindings, from nought: the WGSL binding
  /// number in group zero.
  final int index;

  /// The source line it is declared on, counted from one.
  final int line;
}

/// A local, or a loop's counter.
final class KLocal {
  /// The local [name] of [type]; [mutable] for a `var`.
  KLocal(this.name, this.type, {required this.mutable});

  /// The name the source gives it.
  final String name;

  /// Its type, fixed at its declaration.
  final KType type;

  /// Whether it is a `var` that may be assigned again; a `let` and a loop's
  /// counter are not.
  final bool mutable;
}

/// Every expression, typed.
sealed class KExpr {
  /// An expression whose value is of [type].
  const KExpr(this.type);

  /// The type the parser decided, which both translators take as given.
  final KType type;
}

/// An integer literal.
final class KIntLiteral extends KExpr {
  /// The literal [value], typed [type]: abstract until it meets another.
  const KIntLiteral(this.value, super.type);

  /// The literal's value.
  final int value;
}

/// A float literal.
final class KFloatLiteral extends KExpr {
  /// The literal [value], written as [text], typed [type].
  const KFloatLiteral(this.value, this.text, super.type);

  /// The value as an f32 would hold it: a number of the kernel's, unitless.
  final double value;

  /// As written, for the WGSL emitter: a literal stays the literal.
  final String text;
}

/// `true` or `false`.
final class KBoolLiteral extends KExpr {
  /// The literal [value].
  const KBoolLiteral(this.value) : super(KType.boolean);

  /// The literal's value.
  final bool value;
}

/// A read of a local or a loop's counter.
final class KLocalRef extends KExpr {
  /// A read of [local], of its type.
  KLocalRef(this.local) : super(local.type);

  /// The local read.
  final KLocal local;
}

/// `id`, the global invocation id.
final class KInvocationId extends KExpr {
  /// The id, a `uvec3`.
  const KInvocationId() : super(KType.uvec3);
}

/// `buffer[index]`.
final class KBufferRead extends KExpr {
  /// A read of [binding] at [index], of the buffer's element type.
  KBufferRead(this.binding, this.index) : super(binding.element);

  /// The buffer read.
  final KBinding binding;

  /// The element's index, from nought.
  final KExpr index;
}

/// `atomicLoad(buffer, index)`, `atomicExchange(buffer, index, value)` or
/// `atomicAdd(buffer, index, value)` on an `atomic` buffer: the element's
/// value before the call, which [op] — `load`, `exchange`, `add` — leaves
/// changed in one step no other invocation sees half of. [value] is null
/// for a load.
final class KAtomic extends KExpr {
  /// The call [op] on [binding] at [index], with [value] for all but a
  /// load.
  KAtomic(this.op, this.binding, this.index, this.value)
    : super(binding.element);

  /// `load`, `exchange` or `add`.
  final String op;

  /// The `atomic` buffer it acts on.
  final KBinding binding;

  /// The element's index, from nought.
  final KExpr index;

  /// What an exchange stores or an add adds; null for a load.
  final KExpr? value;
}

/// `len(buffer)`: how many elements it holds.
final class KBufferLength extends KExpr {
  /// The length of [binding], a `u32`.
  const KBufferLength(this.binding) : super(KType.u32);

  /// The buffer measured.
  final KBinding binding;
}

/// `width(t)` or `height(t)` of a texture or an image.
final class KTextureSize extends KExpr {
  /// The width of [binding], or its height when [height]; a `u32` count of
  /// texels.
  const KTextureSize(this.binding, {required this.height}) : super(KType.u32);

  /// The texture or image measured.
  final KBinding binding;

  /// Whether it is `height`; false for `width`.
  final bool height;
}

/// `load(texture, x, y)`: the texel as four floats.
final class KTextureLoad extends KExpr {
  /// A load of [binding]'s texel at column [x] and row [y].
  const KTextureLoad(this.binding, this.x, this.y) : super(KType.vec4);

  /// The texture read.
  final KBinding binding;

  /// The texel's column, from nought.
  final KExpr x;

  /// The texel's row, from nought.
  final KExpr y;
}

/// `.x`, `.xy`, `.rgb`: components of a vector, by index.
final class KSwizzle extends KExpr {
  /// The [components] of [target], typed [type].
  const KSwizzle(this.target, this.components, super.type);

  /// The vector the components are taken from.
  final KExpr target;

  /// Each component's index, nought to three, in the order written.
  final List<int> components;
}

/// A unary operation.
final class KUnary extends KExpr {
  /// [op] applied to [operand], typed [type].
  const KUnary(this.op, this.operand, super.type);

  /// `-`, `!` or `~`.
  final String op;

  /// What it applies to.
  final KExpr operand;
}

/// A binary operation. Both sides already have the operation's operand
/// types: an abstract literal on one side was given the other's type.
final class KBinary extends KExpr {
  /// [left] [op] [right], typed [type]: `bool` for a comparison.
  const KBinary(this.op, this.left, this.right, super.type);

  /// The operator as written: `+`, `<`, `&&`, `<<` and the rest.
  final String op;

  /// The left operand.
  final KExpr left;

  /// The right operand.
  final KExpr right;
}

/// A built-in function: the conversions, the arithmetic ones, `select`
/// and the vector constructors.
final class KCall extends KExpr {
  /// The call of [function] with [arguments], typed [type].
  const KCall(this.function, this.arguments, super.type);

  /// The built-in's name as written: `f32`, `min`, `select`, `vec4`.
  final String function;

  /// The arguments, in the order written.
  final List<KExpr> arguments;
}

/// Every statement.
sealed class KStmt {
  /// A statement starting on [line].
  const KStmt(this.line);

  /// The source line it starts on, counted from one.
  final int line;
}

/// `let` or `var`.
final class KDeclare extends KStmt {
  /// The declaration of [local], set to [value].
  const KDeclare(this.local, this.value, super.line);

  /// The local declared.
  final KLocal local;

  /// Its first value.
  final KExpr value;
}

/// `name = value;`, the compound forms already expanded.
final class KAssign extends KStmt {
  /// The assignment of [value] to [local].
  const KAssign(this.local, this.value, super.line);

  /// The `var` assigned.
  final KLocal local;

  /// The value it takes.
  final KExpr value;
}

/// `buffer[index] = value;`.
final class KBufferWrite extends KStmt {
  /// The write of [value] into [binding] at [index].
  const KBufferWrite(this.binding, this.index, this.value, super.line);

  /// The `read_write` buffer written.
  final KBinding binding;

  /// The element's index, from nought.
  final KExpr index;

  /// The value written, of the buffer's element type.
  final KExpr value;
}

/// `atomicStore(buffer, index, value);`, or `atomicAdd` or `atomicExchange`
/// as a statement, its answer let go, on an `atomic` buffer: [op] is
/// `store`, `add` or `exchange`.
final class KAtomicStore extends KStmt {
  /// The call [op] on [binding] at [index], with [value].
  const KAtomicStore(this.op, this.binding, this.index, this.value, super.line);

  /// `store`, `add` or `exchange`.
  final String op;

  /// The `atomic` buffer it acts on.
  final KBinding binding;

  /// The element's index, from nought.
  final KExpr index;

  /// What is stored, added or exchanged.
  final KExpr value;
}

/// `store(image, x, y, value);`.
final class KImageStore extends KStmt {
  /// The store of [value] into [binding]'s texel at [x] and [y].
  const KImageStore(this.binding, this.x, this.y, this.value, super.line);

  /// The image written.
  final KBinding binding;

  /// The texel's column, from nought.
  final KExpr x;

  /// The texel's row, from nought.
  final KExpr y;

  /// The texel, a `vec4` stored as RGBA8.
  final KExpr value;
}

/// `if condition { } else { }`.
final class KIf extends KStmt {
  /// The branch on [condition] into [then] or [otherwise].
  const KIf(this.condition, this.then, this.otherwise, super.line);

  /// The `bool` deciding the branch.
  final KExpr condition;

  /// What runs when [condition] holds.
  final List<KStmt> then;

  /// Empty without an `else`.
  final List<KStmt> otherwise;
}

/// `for i in from .. to { }`: [counter] from [from] while below [to], by one.
final class KFor extends KStmt {
  /// The loop of [counter] over [from] up to [to], running [body].
  const KFor(this.counter, this.from, this.to, this.body, super.line);

  /// The loop's counter, which the body reads and cannot assign.
  final KLocal counter;

  /// The counter's first value.
  final KExpr from;

  /// The bound the counter stays below.
  final KExpr to;

  /// What runs once per value of [counter].
  final List<KStmt> body;
}

/// `break;`: leaves the innermost loop.
final class KBreak extends KStmt {
  /// A `break` on [line].
  const KBreak(super.line);
}

/// `continue;`: goes on to the innermost loop's next value.
final class KContinue extends KStmt {
  /// A `continue` on [line].
  const KContinue(super.line);
}

/// `return;`: this invocation is done.
final class KReturn extends KStmt {
  /// A `return` on [line].
  const KReturn(super.line);
}

/// One kernel, parsed and checked.
final class KKernel {
  /// The kernel [name], read as [languageVersion], with its [workgroup]
  /// size, [bindings] and [body].
  const KKernel({
    required this.name,
    required this.languageVersion,
    required this.workgroup,
    required this.bindings,
    required this.body,
  });

  /// The name after `compute`, which a stage is named by.
  final String name;

  /// The kernel language version its source was read as.
  final int languageVersion;

  /// The workgroup's size in invocations along x, y and z: one for an axis
  /// the source leaves out, (64, 1, 1) when it gives no `workgroup` line.
  final (int, int, int) workgroup;

  /// The declared bindings, in declaration order.
  final List<KBinding> bindings;

  /// The statements of its `kernel` block, in order.
  final List<KStmt> body;
}
