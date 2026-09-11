part of 'modifier.dart';

/// A thin [Modifier] wrapper over [booleanOp] (`mesh-47`), the same split
/// every other concrete [Modifier] here already makes between "the
/// geometry" and "the stack step" — with one difference the others do not
/// have: its second operand is not a parameter of its own, it is *another
/// object's mesh*, read from [ModifierContext.operands] by [operandId]. See
/// the library doc comment for why that has to be a context lookup rather
/// than a `ModelObject` this package cannot be handed.
///
/// **[operandTransform] maps the operand's own mesh-local positions into
/// this modifier's own base mesh's local space** — typically
/// `baseObject.transform.inverse() * operandObject.transform`, worked out by
/// whoever builds this modifier, since only the project above this package
/// knows either object's own world transform. It is a field of the modifier
/// itself, not read from context: `mesh-48`'s own acceptance ("changing the
/// operand's transform invalidates the cache") falls out of that placement
/// for free, because `mat-18`'s `ModifierEvaluationCache` already keys on
/// every enabled modifier's own [toJson], and a changed matrix changes that
/// JSON the same way any other field would.
///
/// **A cycle is not this class's own concern to detect.** Two objects each
/// naming the other as an operand would need this package to see the whole
/// project's own dependency graph, which it cannot — `ModifierContext`
/// stays a mesh-level type. What this modifier does instead is treat a
/// missing [ModifierContext.operands] entry as nothing to combine with,
/// which is the mechanism a cycle-safe resolver above this package uses to
/// break one: never populate the cyclic operand's own entry, and every
/// `BooleanModifier` naming it passes its base straight through rather than
/// looping or refusing loudly.
final class BooleanModifier extends Modifier {
  const BooleanModifier({
    required this.operation,
    required this.operandId,
    required this.operandTransform,
  });

  final CsgOperation operation;
  final int operandId;
  final Matrix4 operandTransform;

  @override
  EditMesh apply(EditMesh base, ModifierContext context) {
    final operand = context.operands[operandId];
    if (operand == null) return base;

    final transformed = _transformedCopy(operand, operandTransform);
    final result = booleanOp(base, transformed, operation);
    // Refused (over the polygon budget) or genuinely empty (an intersect
    // sharing no volume with the base): the same "nothing to combine with"
    // answer a missing operand gets.
    return result?.mesh ?? base;
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'boolean',
    'operation': operation.name,
    'operandId': operandId,
    'operandTransform': operandTransform.storage.toList(),
  };

  /// [BooleanModifier] from its own [toJson], or null when a field is
  /// missing, [operation] names none of [CsgOperation]'s three, or
  /// [operandTransform] is not the 16 numbers a 4×4 matrix needs.
  static BooleanModifier? fromJson(Map<String, Object?> json) => switch (json) {
    {
      'operation': final String operationName,
      'operandId': final int operandId,
      'operandTransform': final List<Object?> matrix,
    } =>
      _fromFields(operationName, operandId, matrix),
    _ => null,
  };

  static BooleanModifier? _fromFields(
    String operationName,
    int operandId,
    List<Object?> matrix,
  ) {
    final operation = _operationNamed(operationName);
    if (operation == null || matrix.length != 16) return null;
    final values = List<double>.filled(16, 0.0);
    for (var i = 0; i < 16; i++) {
      final entry = matrix[i];
      if (entry is! num) return null;
      values[i] = entry.toDouble();
    }
    return BooleanModifier(
      operation: operation,
      operandId: operandId,
      operandTransform: Matrix4.fromList(values),
    );
  }
}

CsgOperation? _operationNamed(String name) {
  for (final operation in CsgOperation.values) {
    if (operation.name == name) return operation;
  }
  return null;
}

/// [mesh], with every live vertex moved by [transform] — a copy, since a
/// modifier must never mutate what `apply` is handed (the operand came out
/// of [ModifierContext.operands], which the caller may reuse for another
/// object's own evaluation).
EditMesh _transformedCopy(EditMesh mesh, Matrix4 transform) {
  final copy = EditMesh.fromBytes(mesh.toBytes());
  copy.beginStep();
  for (var v = 0; v < copy.vertexSlotCount; v++) {
    if (!copy.isVertexAlive(v)) continue;
    copy.moveVertex(v, transform.transformed3(copy.positionOf(v)));
  }
  copy.endStep();
  return copy;
}
