/// `edu-01`'s panel: the ordered list an `edu_sequence` names, and the four
/// things a teacher does to it — add a step, reorder one, delete one, drop
/// an annotation or a clip plane. Field-by-field editing of whatever is
/// selected (a step's `caption`, an annotation's `widget`, a clip plane's
/// `at`) is not repeated here: `EditorInspector` already draws one row per
/// key for any entity the format has never heard of, `edu_*` included, and
/// a second inspector built to know these five keys by name would be the
/// thing `editor_inspector.dart`'s own doc comment already refused once —
/// "a hand-written inspector [that] would silently drop" the next field the
/// format grows. This panel selects; the inspector edits.
///
/// **Nothing here is a new command.** Every button below ends in `Place`,
/// `SetField`, `Delete` or `Turn` — the ten commands `editor_command.dart`
/// already had — run through [Editing.history] the same way an arrow key or
/// a click on the palette already does, so the result also undoes, and an
/// agent could reach the same document through the five MCP tools those
/// commands already have (proven in
/// `packages/flutter3d_editor_mcp/test/lesson_authoring_mcp_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef, Level;
import 'package:vector_math/vector_math.dart' show Vector3;

const Color _panelBackground = Color(0xFF14161A);
const Color _panelBorder = Color(0xFF2A2E36);
const Color _text = Color(0xFFE6EAF0);
const Color _dim = Color(0xFF9AA3AF);

/// The one `edu_sequence` in [level], by [name] if given or the first one
/// found otherwise — a document with more than one lesson is not something
/// this panel refuses, it just starts on the first.
EntityDef? _findSequence(Level level, {String? name}) {
  if (name != null) {
    final named = level.named(name);
    return named?.type == 'edu_sequence' ? named : null;
  }
  for (final entity in level.entities) {
    if (entity.type == 'edu_sequence') return entity;
  }
  return null;
}

final class StepPanel extends StatelessWidget {
  const StepPanel({super.key, required this.editing, required this.onChanged});

  final Editing editing;

  /// Told what happened, the same shape `EditorInspector.onChanged` takes —
  /// so `main.dart` wires both the same way.
  final void Function(String what) onChanged;

  void _run(EditorCommand command, String said) {
    if (editing.history.run(command)) onChanged(said);
  }

  void _selectByName(String name) {
    final index = indexOfNamed(editing.level, name);
    if (index == null) return;
    editing.select(Piece.entity, index);
    onChanged('selected $name');
  }

  void _addSequenceIfMissing() {
    if (_findSequence(editing.level) != null) return;
    _run(Place(Piece.entity, 'edu_sequence', Vector3.zero()), 'added a lesson');
    _run(const SetField('name', 'lesson'), 'named the lesson');
    _run(const SetField('steps', <String>[]), 'started an empty lesson');
  }

  void _addStep() {
    _addSequenceIfMissing();
    final sequence = _findSequence(editing.level)!;
    final name = freshName(editing.level, 'step');
    final eye = Vector3(
      editing.where?.x ?? 0.0,
      editing.where?.y ?? 1.6,
      editing.where?.z ?? 0.0,
    );
    _run(Place(Piece.entity, 'edu_step', eye), 'added $name');
    _run(SetField('name', name), 'named $name');
    _run(const SetField('caption', 'New step'), 'captioned $name');

    _selectByName(sequence.name!);
    final steps = List<String>.of(
      (editing.entity!.properties['steps'] as List?)?.cast<String>() ??
          const <String>[],
    )..add(name);
    _run(SetField('steps', steps), 'added $name to the lesson');
    _selectByName(name);
  }

  void _deleteStep(String name) {
    final sequence = _findSequence(editing.level);
    if (sequence != null) {
      _selectByName(sequence.name!);
      final steps = List<String>.of(
        (editing.entity!.properties['steps'] as List?)?.cast<String>() ??
            const <String>[],
      )..remove(name);
      _run(SetField('steps', steps), 'removed $name from the lesson');
    }
    _selectByName(name);
    _run(const Delete(), 'deleted $name');
  }

  void _moveStep(String sequenceName, int from, int to) {
    _selectByName(sequenceName);
    final steps = List<String>.of(
      (editing.entity!.properties['steps'] as List?)?.cast<String>() ??
          const <String>[],
    );
    final reordered = movedStep(steps, from, to);
    _run(SetField('steps', reordered), 'reordered the lesson');
  }

  void _addAnnotation(String stepName) {
    final at = editing.where ?? Vector3.zero();
    final name = freshName(editing.level, 'note');
    _run(Place(Piece.entity, 'edu_annotation', at), 'added $name');
    _run(SetField('name', name), 'named $name');
    _run(
      const SetField('widget', 'unnamed-widget'),
      'gave $name a widget name',
    );

    _selectByName(stepName);
    final annotations = List<String>.of(
      (editing.entity!.properties['annotations'] as List?)?.cast<String>() ??
          const <String>[],
    )..add(name);
    _run(SetField('annotations', annotations), 'attached $name to $stepName');
    _selectByName(name);
  }

  void _addClipPlane() {
    final at = editing.where ?? Vector3.zero();
    final name = freshName(editing.level, 'cutaway');
    _run(Place(Piece.entity, 'edu_clip_plane', at), 'added $name');
    _run(SetField('name', name), 'named $name');
    _selectByName(name);
  }

  @override
  Widget build(BuildContext context) {
    final sequence = _findSequence(editing.level);
    final steps = sequence == null
        ? const <EntityDef>[]
        : orderedSteps(editing.level, sequence.name!);
    final selectedName = editing.entity?.name;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _panelBackground,
        border: Border(left: BorderSide(color: _panelBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  sequence == null
                      ? 'No lesson yet'
                      : (sequence.string('title') ?? sequence.name!),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, color: _text, size: 18),
                  tooltip: 'Add a step',
                  onPressed: _addStep,
                ),
              ],
            ),
            if (steps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('No steps yet.', style: TextStyle(color: _dim)),
              ),
            for (var i = 0; i < steps.length; i++)
              _StepRow(
                step: steps[i],
                selected: steps[i].name == selectedName,
                onSelect: () => _selectByName(steps[i].name!),
                onMoveUp: i == 0
                    ? null
                    : () => _moveStep(sequence!.name!, i, i - 1),
                onMoveDown: i == steps.length - 1
                    ? null
                    : () => _moveStep(sequence!.name!, i, i + 1),
                onDelete: () => _deleteStep(steps[i].name!),
                onAddAnnotation: () => _addAnnotation(steps[i].name!),
              ),
            const Divider(color: _panelBorder),
            TextButton.icon(
              onPressed: _addClipPlane,
              icon: const Icon(Icons.content_cut, color: _text, size: 16),
              label: const Text(
                'Add a clip plane',
                style: TextStyle(color: _text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.selected,
    required this.onSelect,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onAddAnnotation,
  });

  final EntityDef step;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onAddAnnotation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF23272F) : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  step.string('caption') ?? step.name ?? '?',
                  style: const TextStyle(color: _text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.sticky_note_2_outlined,
                  color: _dim,
                  size: 16,
                ),
                tooltip: 'Add an annotation to this step',
                onPressed: onAddAnnotation,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward, color: _dim, size: 16),
                onPressed: onMoveUp,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, color: _dim, size: 16),
                onPressed: onMoveDown,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: _dim, size: 16),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
