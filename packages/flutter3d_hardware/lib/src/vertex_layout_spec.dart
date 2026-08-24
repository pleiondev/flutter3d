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
enum VertexFormat {
  float32(bytesPerElement: 4, componentCount: 1),
  float32x2(bytesPerElement: 8, componentCount: 2),
  float32x3(bytesPerElement: 12, componentCount: 3),
  float32x4(bytesPerElement: 16, componentCount: 4),
  uint32(bytesPerElement: 4, componentCount: 1),
  uint32x2(bytesPerElement: 8, componentCount: 2),
  uint32x3(bytesPerElement: 12, componentCount: 3),
  uint32x4(bytesPerElement: 16, componentCount: 4),
  sint32(bytesPerElement: 4, componentCount: 1),
  sint32x2(bytesPerElement: 8, componentCount: 2),
  sint32x3(bytesPerElement: 12, componentCount: 3),
  sint32x4(bytesPerElement: 16, componentCount: 4);

  const VertexFormat({
    required this.bytesPerElement,
    required this.componentCount,
  });

  /// Size of one whole attribute, not of one component.
  final int bytesPerElement;

  final int componentCount;
}

/// Whether a buffer advances once per vertex or once per instance.
///
/// [instance] is the whole point of the type. A buffer marked with it is read
/// once per instance, so a hundred instances of one mesh read a hundred
/// transforms from it while every instance reads the same vertices from the
/// buffer beside it.
enum VertexStepMode {
  vertex,
  instance,
}

/// One input of a vertex stage, and where in its buffer it starts.
///
/// Named [InputAttribute] rather than `VertexAttribute` because the engine's
/// mesh description already owns that name — see the library comment. "Input"
/// is what the shader calls it.
final class InputAttribute {
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

  final VertexFormat format;

  /// Where this attribute begins inside one element of its buffer.
  final int offsetInBytes;
}

/// One buffer's worth of attributes, and how far apart its elements are.
final class BufferLayout {
  const BufferLayout({
    required this.strideInBytes,
    required this.attributes,
    this.stepMode = VertexStepMode.vertex,
  });

  /// Bytes from one element to the next. Not derived from the attributes,
  /// because padding is legitimate and a stride computed by summing sizes would
  /// silently disagree with a buffer that has any.
  final int strideInBytes;

  final List<InputAttribute> attributes;

  final VertexStepMode stepMode;
}

/// Every buffer a pipeline reads vertices from, in slot order.
final class VertexLayoutSpec {
  const VertexLayoutSpec(this.buffers);

  /// Slot *n* is `buffers[n]`, and there are no gaps — see the library comment.
  final List<BufferLayout> buffers;
}
