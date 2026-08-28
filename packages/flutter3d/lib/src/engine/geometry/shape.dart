import 'mesh_data.dart';
import 'vertex_layout.dart';

/// A parameterized generator of geometry.
///
/// An abstraction rather than a bag of static factory methods, so a shape is a
/// *value*: it can be stored, passed around, compared, kept in a list of things
/// the UI offers, and swapped for a caller-defined implementation. A static
/// `Primitives.sphere(...)` call can only be invoked, never held.
///
/// Implementations are expected to be immutable and cheap to construct; the work
/// happens in [build].
abstract class Shape {
  const Shape();

  /// Name for diagnostics and UI labels.
  String get name;

  /// Generates the geometry for the requested [layout].
  ///
  /// Attributes the layout does not declare are simply not written, which lets
  /// one implementation serve several vertex formats.
  MeshData build({VertexLayout layout = VertexLayout.standard});
}

/// A shape defined by delegating to another one.
///
/// Useful where a shape is a special case of a more general generator — a cone
/// is a cylinder with a zero top radius, a sphere is a revolved arc — and the
/// relationship is worth expressing in the type rather than duplicating the
/// generation code.
abstract class DerivedShape extends Shape {
  const DerivedShape();

  /// The shape this one reduces to.
  Shape get delegate;

  @override
  MeshData build({VertexLayout layout = VertexLayout.standard}) =>
      delegate.build(layout: layout);
}
