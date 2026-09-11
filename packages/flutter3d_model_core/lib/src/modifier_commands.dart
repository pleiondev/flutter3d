part of 'command.dart';

/// Appends [modifier] to [id]'s own stack, enabled.
final class AddModifier extends ModelCommand {
  const AddModifier({required this.id, required this.modifier});

  final int id;
  final Modifier modifier;

  @override
  String get name => 'addModifier';

  @override
  String get says => 'add a modifier';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'modifier': modifier.toJson(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    return Outcome.done(
      project.withObject(
        object.copyWith(
          modifiers: <ModifierSlot>[
            ...object.modifiers,
            ModifierSlot(modifier: modifier),
          ],
        ),
      ),
    );
  }
}

/// One field of the modifier at [index] on [id]'s own stack, replaced.
///
/// The same shape `SetMaterialField` already is: a field name and a value
/// whose meaning depends on which modifier kind owns it — see
/// `_modifierFieldSet` for which names each kind answers to.
final class SetModifierField extends ModelCommand {
  const SetModifierField({
    required this.id,
    required this.index,
    required this.field,
    required this.value,
  });

  final int id;
  final int index;
  final String field;
  final Object? value;

  @override
  String get name => 'setModifierField';

  @override
  String get says => 'set $field';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'index': index,
    'field': field,
    'value': value,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (index < 0 || index >= object.modifiers.length) {
      return Outcome.refused('there is no modifier $index on object $id');
    }
    final ModifierSlot slot = object.modifiers[index];
    final Modifier? next = _modifierFieldSet(slot.modifier, field, value);
    if (next == null) {
      return Outcome.refused(
        '"$field" is not a field of this modifier, or its value is the '
        'wrong shape',
      );
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          modifiers: <ModifierSlot>[
            for (var i = 0; i < object.modifiers.length; i++)
              i == index ? slot.copyWith(modifier: next) : object.modifiers[i],
          ],
        ),
      ),
    );
  }
}

/// Flips whether the modifier at [index] on [id]'s own stack runs.
final class ToggleModifier extends ModelCommand {
  const ToggleModifier({required this.id, required this.index});

  final int id;
  final int index;

  @override
  String get name => 'toggleModifier';

  @override
  String get says => 'toggle the modifier';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'index': index,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (index < 0 || index >= object.modifiers.length) {
      return Outcome.refused('there is no modifier $index on object $id');
    }
    final ModifierSlot slot = object.modifiers[index];
    return Outcome.done(
      project.withObject(
        object.copyWith(
          modifiers: <ModifierSlot>[
            for (var i = 0; i < object.modifiers.length; i++)
              i == index
                  ? slot.copyWith(enabled: !slot.enabled)
                  : object.modifiers[i],
          ],
        ),
      ),
    );
  }
}

/// Moves the modifier at [from] on [id]'s own stack to [to], the rest
/// shifting to make room the way a list's own `insert` after a `removeAt`
/// would.
final class ReorderModifier extends ModelCommand {
  const ReorderModifier({
    required this.id,
    required this.from,
    required this.to,
  });

  final int id;
  final int from;
  final int to;

  @override
  String get name => 'reorderModifier';

  @override
  String get says => 'reorder the modifiers';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'from': from,
    'to': to,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    final int count = object.modifiers.length;
    if (from < 0 || from >= count || to < 0 || to >= count) {
      return Outcome.refused(
        'object $id has $count modifiers; $from and $to must both name one',
      );
    }
    if (from == to) {
      return Outcome.refused('the modifier is already there');
    }
    final modifiers = <ModifierSlot>[...object.modifiers];
    final ModifierSlot moved = modifiers.removeAt(from);
    modifiers.insert(to, moved);
    return Outcome.done(
      project.withObject(object.copyWith(modifiers: modifiers)),
    );
  }
}

/// Drops the modifier at [index] from [id]'s own stack.
final class RemoveModifier extends ModelCommand {
  const RemoveModifier({required this.id, required this.index});

  final int id;
  final int index;

  @override
  String get name => 'removeModifier';

  @override
  String get says => 'remove the modifier';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'index': index,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (index < 0 || index >= object.modifiers.length) {
      return Outcome.refused('there is no modifier $index on object $id');
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          modifiers: <ModifierSlot>[
            for (var i = 0; i < object.modifiers.length; i++)
              if (i != index) object.modifiers[i],
          ],
        ),
      ),
    );
  }
}

/// Bakes the modifiers at `0..index` (this session's row says "heavy" work —
/// a `subdivideSimple` at real resolution, say — moves to `doc-24`'s job
/// runner; nothing here is heavy yet, so this still runs where it is called)
/// into [id]'s own base mesh, and drops them from the stack. What is left
/// on `index` and after keeps running, now over the newly baked base.
///
/// **The modifier at [index] is folded in even if its own slot is
/// disabled.** This is the row's own acceptance, read literally: "apply" is
/// what export with that modifier switched on would give, not what the
/// stack as currently toggled gives — a disabled modifier can still be
/// applied, the same way a hidden layer in an image editor can still be
/// merged down on purpose.
final class ApplyModifier extends ModelCommand {
  const ApplyModifier({required this.id, required this.index});

  final int id;
  final int index;

  @override
  String get name => 'applyModifier';

  @override
  String get says => 'apply the modifier';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'index': index,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (index < 0 || index >= object.modifiers.length) {
      return Outcome.refused('there is no modifier $index on object $id');
    }
    final EditMesh? base = switch (object.geometry) {
      final EditedGeometry g => g.mesh,
      _ => null,
    };
    if (base == null) {
      return Outcome.refused(
        'object $id has no edited mesh for a modifier to bake into',
      );
    }
    final stack = ModifierStack(<Modifier>[
      for (var i = 0; i <= index; i++)
        if (i == index || object.modifiers[i].enabled)
          object.modifiers[i].modifier,
    ]);
    final EditMesh baked = stack.evaluate(base, const ModifierContext());
    return Outcome.done(
      project.withObject(
        object.copyWith(
          geometry: EditedGeometry(baked),
          modifiers: <ModifierSlot>[
            for (var i = index + 1; i < object.modifiers.length; i++)
              object.modifiers[i],
          ],
        ),
      ),
    );
  }
}

/// [modifier] with [field] set to [value], or null when [field] does not
/// name one of [modifier]'s own fields or [value] is the wrong shape for it.
Modifier? _modifierFieldSet(Modifier modifier, String field, Object? value) =>
    switch (modifier) {
      final ArrayModifier m => switch (field) {
        'count' =>
          value is int
              ? ArrayModifier(
                  count: value,
                  offset: m.offset,
                  mergeDistance: m.mergeDistance,
                )
              : null,
        'offset' => switch (_doubles(value, 3)) {
          final List<double> o => ArrayModifier(
            count: m.count,
            offset: Vector3(o[0], o[1], o[2]),
            mergeDistance: m.mergeDistance,
          ),
          _ => null,
        },
        'mergeDistance' => switch (value) {
          null => ArrayModifier(
            count: m.count,
            offset: m.offset,
            mergeDistance: null,
          ),
          final num d => ArrayModifier(
            count: m.count,
            offset: m.offset,
            mergeDistance: d.toDouble(),
          ),
          _ => null,
        },
        _ => null,
      },
      final MirrorModifier m => switch (field) {
        'normal' => switch (_doubles(value, 3)) {
          final List<double> n => MirrorModifier(
            normal: Vector3(n[0], n[1], n[2]),
            mergeDistance: m.mergeDistance,
            bisect: m.bisect,
            flipUv: m.flipUv,
          ),
          _ => null,
        },
        'mergeDistance' => switch (value) {
          null => MirrorModifier(
            normal: m.normal,
            mergeDistance: null,
            bisect: m.bisect,
            flipUv: m.flipUv,
          ),
          final num d => MirrorModifier(
            normal: m.normal,
            mergeDistance: d.toDouble(),
            bisect: m.bisect,
            flipUv: m.flipUv,
          ),
          _ => null,
        },
        'bisect' =>
          value is bool
              ? MirrorModifier(
                  normal: m.normal,
                  mergeDistance: m.mergeDistance,
                  bisect: value,
                  flipUv: m.flipUv,
                )
              : null,
        'flipUv' =>
          value is bool
              ? MirrorModifier(
                  normal: m.normal,
                  mergeDistance: m.mergeDistance,
                  bisect: m.bisect,
                  flipUv: value,
                )
              : null,
        _ => null,
      },
      final SmoothModifier m => switch (field) {
        'iterations' =>
          value is int && value > 0
              ? SmoothModifier(
                  iterations: value,
                  lambda: m.lambda,
                  preserveVolume: m.preserveVolume,
                )
              : null,
        'lambda' =>
          value is num
              ? SmoothModifier(
                  iterations: m.iterations,
                  lambda: value.toDouble(),
                  preserveVolume: m.preserveVolume,
                )
              : null,
        'preserveVolume' =>
          value is bool
              ? SmoothModifier(
                  iterations: m.iterations,
                  lambda: m.lambda,
                  preserveVolume: value,
                )
              : null,
        _ => null,
      },
    };
