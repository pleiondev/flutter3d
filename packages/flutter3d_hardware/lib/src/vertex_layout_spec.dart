/// How the bytes in a vertex buffer become the inputs of a vertex stage.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
/// See
/// `graphics/formats.dart` for why the directory exists.
///
/// ## Why this exists at all, when it did not before
///
/// Every draw in this engine bound one interleaved buffer and let the backend
/// work the layout out: Impeller reads it from the compiled shader's reflection
/// and WebGL from `getActiveAttrib`. That is enough while a vertex is a vertex.
/// It stops being enough for instancing, because the thing that makes an
/// instanced draw worth doing is a *second* buffer stepping once per instance
/// rather than once per vertex, and no amount of reflection can tell a backend
/// which of two buffers that is. Somebody has to say it.
///
/// So a layout is **optional and means "stop guessing"**. A pipeline built
/// without one behaves exactly as every pipeline in this engine behaved before
/// — reflection, one buffer, one attribute stream — and that is what keeps the
/// goldens still.
///
/// ## The names differ from flutter_gpu's, and only the names
///
/// flutter_gpu calls these `VertexLayout`, `VertexBuffer` and `VertexAttribute`.
/// This engine already has a `VertexLayout` and a `VertexAttribute` meaning
/// something else — the mesh's own description of its interleaved floats — and
/// the renderer imports both libraries into one file. Two different types with
/// one name, distinguishable only by which import won, is the kind of ambiguity
/// that is invisible at the call site.
///
/// **The enum *values* are flutter_gpu's, unchanged**, under the same rule as
/// `formats.dart`: same values, no more and no fewer, same names, same order.
/// That is what lets the mapping tests assert a value lands on the value of the
/// same name rather than merely on a distinct one.
///
/// ## Slots are dense
///
/// Buffers occupy slots 0, 1, 2 … with no gaps. This is not a simplification:
/// flutter_gpu 3.47 throws on a sparse binding, and its own source carries the
/// issue link for lifting that. A HAL that allowed gaps would be promising
/// something one backend answers with an exception, and the exception would
/// arrive at a draw rather than at the binding that caused it.
library;

/// The type of one vertex attribute, and how much room it takes.
///
/// Every value flutter_gpu has. Its own header notes the absent ones —
/// normalized, packed, half-float, BGRA-swizzled and 64-bit — as a thing to add
/// later; when they arrive there, they arrive here.
final class VertexFormat {
  const VertexFormat._(
    this.index,
    this.name, {
    required this.bytesPerElement,
    required this.componentCount,
  });

  /// One 32-bit float, four bytes.
  static const VertexFormat float32 = VertexFormat._(
    0,
    'float32',
    bytesPerElement: 4,
    componentCount: 1,
  );

  /// Two 32-bit floats, eight bytes.
  static const VertexFormat float32x2 = VertexFormat._(
    1,
    'float32x2',
    bytesPerElement: 8,
    componentCount: 2,
  );

  /// Three 32-bit floats, twelve bytes.
  static const VertexFormat float32x3 = VertexFormat._(
    2,
    'float32x3',
    bytesPerElement: 12,
    componentCount: 3,
  );

  /// Four 32-bit floats, sixteen bytes.
  static const VertexFormat float32x4 = VertexFormat._(
    3,
    'float32x4',
    bytesPerElement: 16,
    componentCount: 4,
  );

  /// One 32-bit unsigned integer, four bytes, read as an integer.
  static const VertexFormat uint32 = VertexFormat._(
    4,
    'uint32',
    bytesPerElement: 4,
    componentCount: 1,
  );

  /// Two 32-bit unsigned integers, eight bytes, read as integers.
  static const VertexFormat uint32x2 = VertexFormat._(
    5,
    'uint32x2',
    bytesPerElement: 8,
    componentCount: 2,
  );

  /// Three 32-bit unsigned integers, twelve bytes, read as integers.
  static const VertexFormat uint32x3 = VertexFormat._(
    6,
    'uint32x3',
    bytesPerElement: 12,
    componentCount: 3,
  );

  /// Four 32-bit unsigned integers, sixteen bytes, read as integers.
  static const VertexFormat uint32x4 = VertexFormat._(
    7,
    'uint32x4',
    bytesPerElement: 16,
    componentCount: 4,
  );

  /// One 32-bit signed integer, four bytes, read as an integer.
  static const VertexFormat sint32 = VertexFormat._(
    8,
    'sint32',
    bytesPerElement: 4,
    componentCount: 1,
  );

  /// Two 32-bit signed integers, eight bytes, read as integers.
  static const VertexFormat sint32x2 = VertexFormat._(
    9,
    'sint32x2',
    bytesPerElement: 8,
    componentCount: 2,
  );

  /// Three 32-bit signed integers, twelve bytes, read as integers.
  static const VertexFormat sint32x3 = VertexFormat._(
    10,
    'sint32x3',
    bytesPerElement: 12,
    componentCount: 3,
  );

  /// Four 32-bit signed integers, sixteen bytes, read as integers.
  static const VertexFormat sint32x4 = VertexFormat._(
    11,
    'sint32x4',
    bytesPerElement: 16,
    componentCount: 4,
  );

  /// Every value this version names, in the order of [index].
  static const List<VertexFormat> values = <VertexFormat>[
    float32,
    float32x2,
    float32x3,
    float32x4,
    uint32,
    uint32x2,
    uint32x3,
    uint32x4,
    sint32,
    sint32x2,
    sint32x3,
    sint32x4,
  ];

  /// The value whose [name] is [wireName], or null when this version names
  /// none (absent) — how a file that names a value is read.
  static VertexFormat? byName(String wireName) {
    for (final value in values) {
      if (value.name == wireName) return value;
    }
    return null;
  }

  /// The position in [values]: stable within a major, appended only.
  final int index;

  /// The stable name, and the wire name: what a file, a report or a
  /// snapshot writes for this value. Never renamed within a major.
  final String name;

  /// Size of one whole attribute, not of one component.
  final int bytesPerElement;

  /// How many components the attribute has, from one to four.
  final int componentCount;

  @override
  String toString() => 'VertexFormat.$name';
}

/// Whether a buffer advances once per vertex or once per instance.
///
/// [instance] is the whole point of the type. A buffer marked with it is read
/// once per instance, so a hundred instances of one mesh read a hundred
/// transforms from it while every instance reads the same vertices from the
/// buffer beside it.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class VertexStepMode {
  const VertexStepMode._(this.name);

  /// The buffer advances one element per vertex.
  static const VertexStepMode vertex = VertexStepMode._('vertex');

  /// The buffer advances one element per instance, so every vertex of an
  /// instance reads the same element.
  static const VertexStepMode instance = VertexStepMode._('instance');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<VertexStepMode> values = <VertexStepMode>[vertex, instance];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static VertexStepMode? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'VertexStepMode.$name';
}

/// One input of a vertex stage, and where in its buffer it starts.
///
/// Named [InputAttribute] rather than `VertexAttribute` because the engine's
/// mesh description already owns that name — see the library comment. "Input"
/// is what the shader calls it.
final class InputAttribute {
  /// Creates an attribute [name] of [format] at [offsetInBytes] into each
  /// element.
  const InputAttribute({
    required this.name,
    required this.format,
    this.offsetInBytes = 0,
  });

  /// Must match the `in` variable in the vertex shader.
  ///
  /// A name and not a location, because the two hardware backends disagree
  /// about which is authoritative and both agree about names: Impeller resolves
  /// them through the compiled shader's reflection, and WebGL through
  /// `getAttribLocation`. A location would have to be right for both.
  final String name;

  /// The attribute's type and size.
  final VertexFormat format;

  /// Where this attribute begins inside one element of its buffer.
  final int offsetInBytes;
}

/// One buffer's worth of attributes, and how far apart its elements are.
final class BufferLayout {
  /// Creates the layout of one buffer whose elements are [strideInBytes] apart,
  /// stepping per vertex by default.
  const BufferLayout({
    required this.strideInBytes,
    required this.attributes,
    this.stepMode = VertexStepMode.vertex,
  });

  /// Bytes from one element to the next. Not derived from the attributes,
  /// because padding is legitimate and a stride computed by summing sizes would
  /// silently disagree with a buffer that has any.
  final int strideInBytes;

  /// The attributes each element holds.
  final List<InputAttribute> attributes;

  /// Whether the buffer advances per vertex or per instance; per vertex by
  /// default.
  final VertexStepMode stepMode;
}

/// Every buffer a pipeline reads vertices from, in slot order.
final class VertexLayoutDescriptor {
  /// Creates a layout of [buffers], slot by slot.
  const VertexLayoutDescriptor(this.buffers);

  /// Slot *n* is `buffers[n]`, and there are no gaps — see the library comment.
  final List<BufferLayout> buffers;
}
