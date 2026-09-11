/// A non-destructive step over an edited mesh, and the stack that folds them.
///
/// **A pure function from a mesh to a mesh, not an edit to `EditMesh`
/// itself.** `EditMesh`'s own operations — `extrudeFace`, `dissolveEdge`,
/// `mergeByDistance` — change the thing a person is looking at and go on the
/// undo stack one step at a time. A modifier is a different kind of change: it
/// sits *above* the base mesh, is re-evaluated from scratch every time the base
/// or an earlier modifier's parameters change, and can be reordered, disabled
/// or removed without touching what it was built from. `object.modifiers` (a
/// project-level list, not a mesh-level one — see `mat-18`) is what actually
/// holds the enabled/disabled state and the order; nothing here needs to know
/// about either.
///
/// **The one place [Modifier] is declared.** `flutter3d_model_core`'s own
/// modifier commands (`doc-23`) reach for this type rather than declaring
/// their own, the same way they reach for `EditMesh` itself — a mesh-level
/// concept belongs in the mesh-level package, and a second declaration of
/// "what a modifier is" in core would be the two-encodings problem this
/// repository's own `.f3d`/`.f3dproj` split was written to avoid elsewhere.
///
/// **[ModifierContext] stays almost empty on purpose.** Every modifier
/// shipping so far — [ArrayModifier], [MirrorModifier], [SmoothModifier] —
/// needs nothing beyond the base mesh `apply` is already handed. A modifier
/// that reads another object's mesh (a boolean operand) cannot be handed a
/// `ModelObject` or a `ModelProject`
/// directly: those are `flutter3d_model_core` types, one genre above this
/// package, and a mesh-level package reaching up to them would invert the
/// layering `tool/structure.dart` enforces everywhere else. Solving that is
/// the modifier that needs it to solve, not a reason to grow this file with a
/// shape nothing here uses yet.
library;

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'merge.dart';
import 'mirror.dart';
import 'selection.dart';
import 'smooth.dart';

part 'array_modifier.dart';
part 'mirror_modifier.dart';
part 'smooth_modifier.dart';

/// What a modifier's own `apply` may read besides the mesh it is folding —
/// today, nothing. See this file's own doc comment for why it stays this way.
final class ModifierContext {
  const ModifierContext();
}

/// One step of a modifier stack.
///
/// **Every concrete modifier lives in this same library**, `part` files
/// included, because [Modifier] is `sealed`: a stack's `evaluate` can `switch`
/// over every kind that exists without an `else`, and adding a new modifier
/// anywhere outside this file is a compile error rather than a case silently
/// falling through.
sealed class Modifier {
  const Modifier();

  /// The mesh this modifier's own change gives, applied to [base] under
  /// [context]. Never mutates [base] — every modifier shipped here builds its
  /// result fresh, through [EditMeshBuilder], the same way [mergeByDistance]
  /// itself does, so a stack evaluated twice from the same base never finds it
  /// changed by its own first evaluation.
  EditMesh apply(EditMesh base, ModifierContext context);

  /// This modifier's own fields, as JSON — the exact shape [modifierFromJson]
  /// reads back.
  Map<String, Object?> toJson();
}

/// A modifier from its own [toJson], or null when [json] names no modifier
/// this build has, or is missing a field one of them needs.
///
/// **Null and not an exception**, for the reason `modelCommandFromJson` gives
/// for the identical choice: a modifier stack saved by a newer build naming a
/// kind this one has never heard of is a modifier to skip, not a project to
/// refuse opening over.
Modifier? modifierFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  return switch (json['kind']) {
    'array' => ArrayModifier.fromJson(json),
    'mirror' => MirrorModifier.fromJson(json),
    'smooth' => SmoothModifier.fromJson(json),
    _ => null,
  };
}

/// A stack of [Modifier]s, evaluated in order over one base mesh.
///
/// **Memoized by the identity of the base mesh it was last evaluated
/// against, not by its content.** Two calls to [evaluate] with the identical
/// `EditMesh` instance — the ordinary case, since nothing between them
/// changed the object being modified — fold the stack once and hand the same
/// result back the second time; a different instance, `identical` or not,
/// always re-folds. Content equality is deliberately not the test: `EditMesh`
/// carries no `==` of its own (see `MeshData`'s identical choice, for the
/// identical reason — comparing thousands of vertices to decide whether to
/// skip recomputing them costs more than the recomputation being skipped),
/// so identity is the only free answer available.
final class ModifierStack {
  ModifierStack(this.modifiers);

  final List<Modifier> modifiers;

  EditMesh? _lastBase;
  EditMesh? _lastResult;

  /// The mesh this stack's own modifiers produce over [base].
  EditMesh evaluate(EditMesh base, ModifierContext context) {
    if (identical(base, _lastBase)) return _lastResult!;
    var current = base;
    for (final Modifier modifier in modifiers) {
      current = modifier.apply(current, context);
    }
    _lastBase = base;
    _lastResult = current;
    return current;
  }
}
