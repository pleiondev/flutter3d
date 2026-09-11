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
final class ModifierSlot {
  const ModifierSlot({required this.modifier, this.enabled = true});

  final Modifier modifier;
  final bool enabled;

  ModifierSlot copyWith({Modifier? modifier, bool? enabled}) => ModifierSlot(
    modifier: modifier ?? this.modifier,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'modifier': modifier.toJson(),
    'enabled': enabled,
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
    };
