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
/// **[ModifierContext] stayed almost empty until [BooleanModifier] needed
/// somewhere to read another object's mesh from.** [ArrayModifier],
/// [MirrorModifier], [SmoothModifier] and [SubdivisionModifier] all need
/// nothing beyond the base mesh `apply` is already handed. A boolean
/// operand is different: it is *another object's* mesh, and this package
/// cannot be handed a `ModelObject` or a `ModelProject` directly to fetch
/// one from — those are `flutter3d_model_core` types, one genre above this
/// package, and a mesh-level package reaching up to them would invert the
/// layering `tool/structure.dart` enforces everywhere else. So
/// [ModifierContext.operands] carries only what this package can already
/// name — an `EditMesh`, keyed by whatever id the caller and the modifier
/// both agree means the same object — and resolving that id to a real
/// object, and refusing a cycle where two objects each name the other as
/// an operand, is the caller's own job: this package sees a mesh it was
/// given or does not, never the graph that decided which.
library;

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'bsp.dart';
import 'edit_mesh.dart';
import 'merge.dart';
import 'mirror.dart';
import 'selection.dart';
import 'smooth.dart';
import 'subdivide.dart';

part 'array_modifier.dart';
part 'boolean_modifier.dart';
part 'mirror_modifier.dart';
part 'smooth_modifier.dart';
part 'subdivision_modifier.dart';

/// What a modifier's own `apply` may read besides the mesh it is folding.
final class ModifierContext {
  const ModifierContext({this.operands = const <int, EditMesh>{}});

  /// Another object's own mesh, by whatever id names it to whoever built
  /// this context — [BooleanModifier.operandId] is the one field that reads
  /// this map. An id with no entry here is not a mesh this evaluation could
  /// see: [BooleanModifier.apply] treats it exactly the way it treats a
  /// cycle a caller broke by leaving the cyclic operand out — as nothing to
  /// combine with, not an error.
  final Map<int, EditMesh> operands;
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
    'subdivision' => SubdivisionModifier.fromJson(json),
    'boolean' => BooleanModifier.fromJson(json),
    _ => null,
  };
}

/// A stack of [Modifier]s, evaluated in order over one base mesh.
///
/// **Memoized by the identity of the base mesh and of every operand mesh it
/// was last evaluated against, not by their content.** Two calls with the
/// identical `EditMesh` base — the ordinary case, since nothing between them
/// changed the object being modified — fold the stack once and hand the same
/// result back the second time, *provided* [ModifierContext.operands] also
/// still names the same mesh instances: a [BooleanModifier] reads another
/// object's own mesh out of that map, and that object can change — its own
/// modifier stack re-folded, its own edit applied — without this object's
/// `base` moving at all. Caching on `base` alone would then hand back a
/// combined mesh that no longer reflects what the operand currently is,
/// which is exactly the staleness `mesh-48`'s own acceptance ("changing the
/// operand's transform invalidates the cache") warns against one level up,
/// in `ModifierEvaluationCache`. Content equality is deliberately not the
/// test for either: `EditMesh` carries no `==` of its own (see `MeshData`'s
/// identical choice, for the identical reason — comparing thousands of
/// vertices to decide whether to skip recomputing them costs more than the
/// recomputation being skipped), so identity is the only free answer
/// available for both the base and every operand.
final class ModifierStack {
  ModifierStack(this.modifiers);

  final List<Modifier> modifiers;

  EditMesh? _lastBase;
  Map<int, EditMesh> _lastOperands = const <int, EditMesh>{};
  EditMesh? _lastResult;

  /// The mesh this stack's own modifiers produce over [base].
  EditMesh evaluate(EditMesh base, ModifierContext context) {
    if (identical(base, _lastBase) &&
        _sameOperands(context.operands, _lastOperands)) {
      return _lastResult!;
    }
    var current = base;
    for (final Modifier modifier in modifiers) {
      current = modifier.apply(current, context);
    }
    _lastBase = base;
    _lastOperands = context.operands;
    _lastResult = current;
    return current;
  }
}

/// Whether [a] and [b] name the same operand meshes — same keys, each
/// pointing to an `identical` `EditMesh` — the equality [ModifierStack.evaluate]
/// needs and `Map`'s own `==` cannot give it, since two maps are `==` only
/// when they are the same object here (`Map` has no structural equality by
/// default) and content equality on the values has to be `identical`, not
/// `EditMesh`'s absent `==`.
bool _sameOperands(Map<int, EditMesh> a, Map<int, EditMesh> b) {
  if (a.length != b.length) return false;
  for (final MapEntry<int, EditMesh> entry in a.entries) {
    if (!identical(b[entry.key], entry.value)) return false;
  }
  return true;
}
