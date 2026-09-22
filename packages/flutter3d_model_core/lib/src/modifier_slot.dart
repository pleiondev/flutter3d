/// A [Modifier] as it sits on [ModelObject.modifiers], plus what a modifier
/// panel needs to build a control for one.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'param_hint.dart';

/// One entry of [ModelObject.modifiers]: a [modifier] and whether the stack
/// runs it.
///
/// **`enabled` lives here, not on [Modifier] itself.** `flutter3d_mesh`'s own
/// `Modifier`/`ModifierStack` (`mesh-40`) is a pure function from a mesh to a
/// mesh; whether a particular step even runs is a fact about the *project*,
/// the same way `mesh-40`'s own doc comment already says — closed by Ж3
/// (2026-09-09): one flag, `enabled`, and no `showInViewport` in v1.
///
/// **`ux-13` reopened that and added the second flag, 2026-09-16.** The
/// reason Ж3 gave for one flag was that nobody had a use for two; the
/// review found the use, and it is the one every package in the field has:
/// a subdivision at four levels is what the model is *for* and is not what
/// anybody wants in the viewport while they work, and a cage a boolean cuts
/// with has to be drawn and must not reach the GLB. So [enabled] is the
/// viewport and [inExport] is the file, and a modifier can be either, both
/// or neither.
final class ModifierSlot {
  const ModifierSlot({
    required this.modifier,
    this.enabled = true,
    this.inExport = true,
  });

  /// Whether the stack runs it for the picture.
  final bool enabled;

  /// Whether the stack runs it for the file — `ux-13`.
  ///
  /// True by default, which is what every slot written before this existed
  /// means: a modifier a person added is a modifier they want in the model
  /// unless they say otherwise.
  final bool inExport;

  final Modifier modifier;

  ModifierSlot copyWith({Modifier? modifier, bool? enabled, bool? inExport}) =>
      ModifierSlot(
        modifier: modifier ?? this.modifier,
        enabled: enabled ?? this.enabled,
        inExport: inExport ?? this.inExport,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'modifier': modifier.toJson(),
    'enabled': enabled,
    // Written only when it is not the default, and absent reads back as
    // true — so a file written before `ux-13` says what it always said.
    if (!inExport) 'inExport': false,
  };

  /// A slot from its own [toJson], or null when [json] is missing a field or
  /// names a modifier kind this build does not have — the same "skip rather
  /// than refuse the whole file" rule `modifierFromJson` itself already
  /// gives a reason for.
  static ModifierSlot? fromJson(Object? json) => switch (json) {
    {'modifier': final Object? modifierJson, 'enabled': final bool enabled} =>
      switch (modifierFromJson(modifierJson)) {
        final Modifier modifier => ModifierSlot(
          modifier: modifier,
          enabled: enabled,
          inExport: (json as Map<String, Object?>)['inExport'] != false,
        ),
        null => null,
      },
    _ => null,
  };
}

/// What a modifier panel should offer a control for, per field of
/// [modifier]'s own kind.
///
/// **Lives in core, not in `flutter3d_mesh`, for the same reason
/// `ModelCommand.hints` does.** `ParamHint` is a core type — see its own doc
/// comment for why it is not `flutter3d_formats`' `MaterialHintKind` — and a
/// mesh-level package cannot depend on it without inverting the layering
/// every other genre in this repository keeps to. `mesh-40`'s row calls this
/// out directly: "здесь только `hints` и обёртки (§3)".
Map<String, ParamHint> hintsForModifier(Modifier modifier) =>
    switch (modifier) {
      ArrayModifier() => const <String, ParamHint>{
        'count': IntHint(min: 1, max: 64),
        'offset': Vector3Hint(step: 0.1, unit: 'm'),
        'mergeDistance': DoubleHint(min: 0.0, step: 0.001, unit: 'm'),
      },
      MirrorModifier() => const <String, ParamHint>{
        'normal': Vector3Hint(),
        'mergeDistance': DoubleHint(min: 0.0, step: 0.001, unit: 'm'),
        'bisect': BoolHint(),
        'flipUv': BoolHint(),
      },
      SmoothModifier() => const <String, ParamHint>{
        'iterations': IntHint(min: 1, max: 50),
        'lambda': DoubleHint(min: 0.0, max: 1.0, step: 0.05),
        'preserveVolume': BoolHint(),
      },
      SubdivisionModifier() => const <String, ParamHint>{
        'levels': IntHint(min: 1, max: 6),
        'viewLevels': IntHint(min: 1, max: 6),
      },
      // `operandTransform` has no entry: a 4×4 matrix is not a shape any
      // `ParamHint` here names, and nothing rebuilds it from a control
      // rather than from the operand object's own transform directly — the
      // same reason `SetModifierField` has no case for it either.
      BooleanModifier() => <String, ParamHint>{
        'operation': EnumHint([
          ...CsgOperation.values.map((CsgOperation o) => o.name),
        ]),
        'operandId': const IntHint(min: 0),
      },
    };
