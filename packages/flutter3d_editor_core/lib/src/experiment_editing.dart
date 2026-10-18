/// The editing side of the experiment document, `f3d.experiment`: what a
/// teacher in the editor and an agent through its MCP server do to one,
/// as values that can be named, sent and read back, and an undo that keeps
/// whole documents.
library;

import 'package:flutter3d_education/experiment.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show DocumentFormatException, Flutter3dFormatException;

/// One thing somebody can do to an experiment document, as a value.
///
/// **Every edit goes back through the reader.** An edit changes the
/// document as its file writes it and reads the result again with
/// [ExperimentDocument.fromJson], so what the reader refuses (a step that
/// sets a parameter the document does not declare, an expectation of a
/// probe it has not got, two parameters of one id, a tolerance in another
/// unit) is refused here by the same words, and nothing the editor writes
/// is a file the reader would not open.
///
/// `abstract final`, so only this package adds an edit, and not sealed: a
/// `switch` over the kinds ends with a wildcard, and an edit a later minor
/// adds breaks none.
abstract final class ExperimentEdit {
  const ExperimentEdit();

  /// What it is called on the wire: one word in lower camel case.
  String get name;

  /// What it does, read as a sentence: what a step of undo is called.
  String get says;

  /// Everything it carries except its [name].
  Map<String, Object?> get arguments;

  /// The edit as a map: [name] under `edit`, then [arguments].
  Map<String, Object?> toJson() => <String, Object?>{
    'edit': name,
    ...arguments,
  };

  /// [document] with this edit made. Throws a [DocumentFormatException]
  /// saying why, as the reader says it, when the result is not an
  /// experiment the reader opens, or when what the edit names is not there.
  ExperimentDocument applyTo(ExperimentDocument document) {
    final json = document.toJson();
    change(json);
    try {
      return ExperimentDocument.fromJson(json);
    } on Flutter3dFormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DocumentFormatException('$says: ${_message(error)}'),
        stackTrace,
      );
    }
  }

  /// Changes [json], the document as its file writes it.
  void change(Map<String, Object?> json);

  /// Reads an edit back from [json], or null when it names none or its
  /// arguments are not the shape it needs. Null rather than a throw, as
  /// `EditorCommand.fromJson` answers.
  static ExperimentEdit? fromJson(Map<String, Object?> json) {
    String? text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    Map<String, Object?>? object(String key) => switch (json[key]) {
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => null,
    };
    final value = json['value'];
    return switch (json['edit']) {
      'setExperimentField' => switch ((text('key'), value)) {
        (final String key, null || String()) when _fields.contains(key) =>
          SetExperimentField(key, value as String?),
        _ => null,
      },
      'setSubstance' => switch (text('id')) {
        final String id => SetSubstance(id, role: text('role')),
        null => null,
      },
      'removeSubstance' => switch (text('id')) {
        final String id => RemoveSubstance(id),
        null => null,
      },
      'setParameter' => switch ((text('id'), value)) {
        (final String id, final Object value) => SetParameter(
          id,
          value,
          min: json['min'],
          max: json['max'],
        ),
        _ => null,
      },
      'removeParameter' => switch (text('id')) {
        final String id => RemoveParameter(id),
        null => null,
      },
      'setProbe' => switch (object('probe')) {
        final Map<String, Object?> probe => SetProbe(probe),
        null => null,
      },
      'removeProbe' => switch (text('id')) {
        final String id => RemoveProbe(id),
        null => null,
      },
      'setStep' => switch (object('step')) {
        final Map<String, Object?> step => SetStep(
          step,
          at: switch (json['at']) {
            final int at => at,
            _ => null,
          },
        ),
        null => null,
      },
      'removeStep' => switch (text('step')) {
        final String step => RemoveStep(step),
        null => null,
      },
      'moveStep' => switch ((text('step'), json['to'])) {
        (final String step, final int to) => MoveStep(step, to),
        _ => null,
      },
      'setExpectation' => switch ((
        text('step'),
        text('probe'),
        value,
        json['tolerance'],
      )) {
        (
          final String step,
          final String probe,
          final Object value,
          final Object tolerance,
        ) =>
          SetExpectation(step, probe, value, tolerance),
        _ => null,
      },
      'removeExpectation' => switch ((text('step'), text('probe'))) {
        (final String step, final String probe) => RemoveExpectation(
          step,
          probe,
        ),
        _ => null,
      },
      _ => null,
    };
  }

  static const Set<String> _fields = <String>{
    'name',
    'title',
    'level',
    'profile',
  };
}

String _message(Flutter3dFormatException error) =>
    error is DocumentFormatException ? error.message : '$error';

/// Every edit's name, in the order a list of tools offers them.
const List<String> experimentEditNames = <String>[
  'setExperimentField',
  'setSubstance',
  'removeSubstance',
  'setParameter',
  'removeParameter',
  'setProbe',
  'removeProbe',
  'setStep',
  'removeStep',
  'moveStep',
  'setExpectation',
  'removeExpectation',
];

List<Map<String, Object?>> _rows(Map<String, Object?> json, String key) =>
    <Map<String, Object?>>[
      for (final row in (json[key] as List<Object?>?) ?? const <Object?>[])
        (row! as Map).cast<String, Object?>(),
    ];

/// [rows] under [key] of [json], or the key taken out when there are none.
void _put(
  Map<String, Object?> json,
  String key,
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) {
    json.remove(key);
  } else {
    json[key] = rows;
  }
}

/// [row] in place of the one whose [idKey] is the same, or added at the end.
List<Map<String, Object?>> _replaced(
  List<Map<String, Object?>> rows,
  Map<String, Object?> row,
  String idKey,
) {
  final at = rows.indexWhere((r) => r[idKey] == row[idKey]);
  return at < 0
        ? <Map<String, Object?>>[...rows, row]
        : <Map<String, Object?>>[...rows]
    ..[at < 0 ? rows.length : at] = row;
}

/// [rows] without the one whose [idKey] is [id]. Throws a
/// [DocumentFormatException] naming [what] when there is none.
List<Map<String, Object?>> _without(
  List<Map<String, Object?>> rows,
  String idKey,
  String id,
  String what,
) {
  final kept = <Map<String, Object?>>[
    for (final row in rows)
      if (row[idKey] != id) row,
  ];
  if (kept.length == rows.length) {
    throw DocumentFormatException('the experiment has no $what "$id"');
  }
  return kept;
}

Map<String, Object?> _scenario(Map<String, Object?> json) =>
    switch (json['scenario']) {
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => <String, Object?>{},
    };

List<Map<String, Object?>> _steps(Map<String, Object?> json) =>
    _rows(_scenario(json), 'steps');

void _putSteps(Map<String, Object?> json, List<Map<String, Object?>> steps) =>
    json['scenario'] = <String, Object?>{..._scenario(json), 'steps': steps};

/// One of the document's own words: its `name`, `title`, `level` (the level
/// file, relative to the document) or `profile`. Null takes out what may be
/// left out (`title`, `profile`).
final class SetExperimentField extends ExperimentEdit {
  /// A write of [value] under [key]; null takes the key out.
  const SetExperimentField(this.key, this.value);

  /// `name`, `title`, `level` or `profile`; any other is refused with a
  /// [DocumentFormatException] when applied.
  final String key;

  /// What the field says; null takes it out, and the reader then refuses a
  /// document left without a field it needs.
  final String? value;

  @override
  String get name => 'setExperimentField';

  @override
  String get says => value == null ? 'clear $key' : 'set $key to "$value"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'key': key,
    'value': value,
  };

  @override
  void change(Map<String, Object?> json) {
    if (!ExperimentEdit._fields.contains(key)) {
      throw DocumentFormatException('an experiment has no field "$key"');
    }
    if (value == null) {
      json.remove(key);
    } else {
      json[key] = value;
    }
  }
}

/// A substance the experiment uses, by catalog id, added or given a new
/// [role].
final class SetSubstance extends ExperimentEdit {
  /// The substance [id], in [role] when given.
  const SetSubstance(this.id, {this.role});

  /// The substance's id in the material catalog.
  final String id;

  /// What it is for in the experiment; null writes no role, dropping one
  /// it had.
  final String? role;

  @override
  String get name => 'setSubstance';

  @override
  String get says => role == null ? 'use $id' : 'use $id as $role';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'role': ?role,
  };

  @override
  void change(Map<String, Object?> json) => _put(
    json,
    'substances',
    _replaced(_rows(json, 'substances'), <String, Object?>{
      'id': id,
      'role': ?role,
    }, 'id'),
  );
}

/// The substance [id] taken out.
final class RemoveSubstance extends ExperimentEdit {
  /// The removal of [id]; refused when the experiment does not use it.
  const RemoveSubstance(this.id);

  /// The catalog id of the substance to take out.
  final String id;

  @override
  String get name => 'removeSubstance';

  @override
  String get says => 'stop using $id';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  void change(Map<String, Object?> json) => _put(
    json,
    'substances',
    _without(_rows(json, 'substances'), 'id', id, 'substance'),
  );
}

/// A parameter, added or given a new value and bounds: each a quantity as
/// the file writes one, `{"value": 1, "unit": "m"}`, or as text, `"1 m"`.
final class SetParameter extends ExperimentEdit {
  /// The parameter [id] at [value], bounded by [min] and [max] when given.
  const SetParameter(this.id, this.value, {this.min, this.max});

  /// The parameter's id, which steps set it by.
  final String id;

  /// Its value, a quantity in either form.
  final Object value;

  /// Its lower bound, a quantity in either form; null writes none.
  final Object? min;

  /// Its upper bound, a quantity in either form; null writes none.
  final Object? max;

  @override
  String get name => 'setParameter';

  @override
  String get says => 'set parameter $id to ${_said(value)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'value': value,
    'min': ?min,
    'max': ?max,
  };

  @override
  void change(Map<String, Object?> json) => _put(
    json,
    'parameters',
    _replaced(_rows(json, 'parameters'), <String, Object?>{
      'id': id,
      'value': value,
      'min': ?min,
      'max': ?max,
    }, 'id'),
  );
}

/// The parameter [id] taken out; refused while a step still sets it.
final class RemoveParameter extends ExperimentEdit {
  /// The removal of [id]; refused also when there is no such parameter.
  const RemoveParameter(this.id);

  /// The id of the parameter to take out.
  final String id;

  @override
  String get name => 'removeParameter';

  @override
  String get says => 'remove parameter $id';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  void change(Map<String, Object?> json) => _put(
    json,
    'parameters',
    _without(_rows(json, 'parameters'), 'id', id, 'parameter'),
  );
}

/// A probe, added or replaced by its id: the probe as the file writes it,
/// with `on` for the level entity carrying it.
final class SetProbe extends ExperimentEdit {
  /// The probe [probe], keyed by its `id`.
  const SetProbe(this.probe);

  /// The probe's JSON, written whole in place of the one with its `id`;
  /// the reader refuses one it cannot read.
  final Map<String, Object?> probe;

  @override
  String get name => 'setProbe';

  @override
  String get says => 'set probe ${probe['id']}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'probe': probe};

  @override
  void change(Map<String, Object?> json) =>
      _put(json, 'probes', _replaced(_rows(json, 'probes'), probe, 'id'));
}

/// The probe [id] taken out; refused while a step still expects it.
final class RemoveProbe extends ExperimentEdit {
  /// The removal of [id]; refused also when there is no such probe.
  const RemoveProbe(this.id);

  /// The id of the probe to take out.
  final String id;

  @override
  String get name => 'removeProbe';

  @override
  String get says => 'remove probe $id';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  void change(Map<String, Object?> json) =>
      _put(json, 'probes', _without(_rows(json, 'probes'), 'id', id, 'probe'));
}

/// A step of the scenario as the file writes it, in place of the one of
/// its name, or added: at [at] when given, at the end otherwise.
final class SetStep extends ExperimentEdit {
  /// The step [step], keyed by its `name`, added at [at] when new.
  const SetStep(this.step, {this.at});

  /// The step's JSON, written whole; its `name` says which step it
  /// replaces.
  final Map<String, Object?> step;

  /// Where a new step goes, from nought, clamped to the scenario; null for
  /// the end. Ignored when a step of the name is already there.
  final int? at;

  @override
  String get name => 'setStep';

  @override
  String get says => 'set step ${step['name']}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'step': step,
    'at': ?at,
  };

  @override
  void change(Map<String, Object?> json) {
    final steps = _steps(json);
    final had = steps.indexWhere((s) => s['name'] == step['name']);
    if (had >= 0) {
      steps[had] = step;
    } else {
      steps.insert((at ?? steps.length).clamp(0, steps.length), step);
    }
    _putSteps(json, steps);
  }
}

/// The step [step] taken out of the scenario.
final class RemoveStep extends ExperimentEdit {
  /// The removal of [step]; refused when the scenario has no such step.
  const RemoveStep(this.step);

  /// The `name` of the step to take out.
  final String step;

  @override
  String get name => 'removeStep';

  @override
  String get says => 'remove step $step';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'step': step};

  @override
  void change(Map<String, Object?> json) =>
      _putSteps(json, _without(_steps(json), 'name', step, 'step'));
}

/// The step [step] moved to position [to] of the scenario, from 0.
final class MoveStep extends ExperimentEdit {
  /// The move of [step] to [to]; refused when there is no such step.
  const MoveStep(this.step, this.to);

  /// The `name` of the step to move.
  final String step;

  /// Its new position, from nought, counted after it is taken out and
  /// clamped to the scenario.
  final int to;

  @override
  String get name => 'moveStep';

  @override
  String get says => 'move step $step to $to';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'step': step,
    'to': to,
  };

  @override
  void change(Map<String, Object?> json) {
    final steps = _steps(json);
    final from = steps.indexWhere((s) => s['name'] == step);
    if (from < 0) {
      throw DocumentFormatException('the experiment has no step "$step"');
    }
    final moved = steps.removeAt(from);
    steps.insert(to.clamp(0, steps.length), moved);
    _putSteps(json, steps);
  }
}

/// What the probe [probe] should read when the step [step] ends, in place
/// of what it expected before: [value] within [tolerance], each a quantity
/// as the file writes one.
final class SetExpectation extends ExperimentEdit {
  /// The expectation that [probe] reads [value] within [tolerance] after
  /// [step]; refused when there is no such step.
  const SetExpectation(this.step, this.probe, this.value, this.tolerance);

  /// The `name` of the step whose end it is checked at.
  final String step;

  /// The id of the probe read.
  final String probe;

  /// The reading expected, a quantity in either form.
  final Object value;

  /// How far the reading may be from [value], a quantity in the same unit;
  /// the reader refuses one in another.
  final Object tolerance;

  @override
  String get name => 'setExpectation';

  @override
  String get says =>
      'expect $probe to read ${_said(value)} ± ${_said(tolerance)} after '
      '$step';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'step': step,
    'probe': probe,
    'value': value,
    'tolerance': tolerance,
  };

  @override
  void change(Map<String, Object?> json) => _changeStep(
    json,
    step,
    (Map<String, Object?> row) => _put(
      row,
      'expect',
      _replaced(_rows(row, 'expect'), <String, Object?>{
        'probe': probe,
        'value': value,
        'tolerance': tolerance,
      }, 'probe'),
    ),
  );
}

/// The step [step] no longer expecting a reading of [probe].
final class RemoveExpectation extends ExperimentEdit {
  /// The removal of [step]'s expectation of [probe]; refused when either
  /// is not there.
  const RemoveExpectation(this.step, this.probe);

  /// The `name` of the step that expected the reading.
  final String step;

  /// The id of the probe it no longer reads.
  final String probe;

  @override
  String get name => 'removeExpectation';

  @override
  String get says => 'stop expecting $probe after $step';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'step': step,
    'probe': probe,
  };

  @override
  void change(Map<String, Object?> json) => _changeStep(
    json,
    step,
    (Map<String, Object?> row) => _put(
      row,
      'expect',
      _without(_rows(row, 'expect'), 'probe', probe, 'expectation of'),
    ),
  );
}

void _changeStep(
  Map<String, Object?> json,
  String name,
  void Function(Map<String, Object?> row) change,
) {
  final steps = _steps(json);
  final at = steps.indexWhere((s) => s['name'] == name);
  if (at < 0) {
    throw DocumentFormatException('the experiment has no step "$name"');
  }
  final row = Map<String, Object?>.of(steps[at]);
  change(row);
  steps[at] = row;
  _putSteps(json, steps);
}

/// A quantity as an edit carries it, for a sentence.
String _said(Object? quantity) => switch (quantity) {
  {'value': final Object value, 'unit': final Object unit} => '$value $unit',
  final Object other => '$other',
  null => 'nothing',
};

/// An experiment document open for editing: the document now, the edits
/// that made it, and the documents to go back and forward to.
///
/// **Undo keeps documents, not inverses.** An [ExperimentDocument] is
/// immutable, so a step back is the document before the edit, as the
/// level's history keeps whole snapshots and for the same reason: an undo
/// that reconstructs is an undo with its own bugs.
final class ExperimentEditing {
  /// The document given, open with no history and counted as saved;
  /// sixty-four steps back are kept unless [limit] says otherwise.
  ExperimentEditing(this._document, {this.path, this.limit = 64});

  /// Reads [text], a `.f3d.experiment` file, from [path]. Throws the
  /// reader's [DocumentFormatException] for one it does not open.
  factory ExperimentEditing.parse(String text, {String? path}) =>
      ExperimentEditing(ExperimentDocument.parse(text), path: path);

  /// Where the document was read from, or null for a new one.
  final String? path;

  /// How many steps back are kept.
  final int limit;

  ExperimentDocument _document;
  final List<({String says, ExperimentDocument document})> _back =
      <({String says, ExperimentDocument document})>[];
  final List<({String says, ExperimentDocument document})> _forward =
      <({String says, ExperimentDocument document})>[];
  int _savedAt = 0;
  int _edits = 0;

  /// The document now.
  ExperimentDocument get document => _document;

  /// Whether it changed since it was read or last [saved].
  bool get isDirty => _edits != _savedAt;

  /// What undo would take back, or null for nothing.
  String? get canUndo => _back.isEmpty ? null : _back.last.says;

  /// What redo would make again, or null for nothing.
  String? get canRedo => _forward.isEmpty ? null : _forward.last.says;

  /// Makes [edit]: null when it was made, and the reader's refusal, having
  /// changed nothing, when it was not.
  String? run(ExperimentEdit edit) {
    final ExperimentDocument next;
    try {
      next = edit.applyTo(_document);
    } on Flutter3dFormatException catch (error) {
      return _message(error);
    } on ArgumentError catch (error) {
      return '${edit.says}: ${error.message}';
    }
    _back.add((says: edit.says, document: _document));
    if (_back.length > limit) _back.removeAt(0);
    _forward.clear();
    _document = next;
    _edits++;
    return null;
  }

  /// Goes back one edit, answering what it was, or null for none.
  String? undo() {
    if (_back.isEmpty) return null;
    final step = _back.removeLast();
    _forward.add((says: step.says, document: _document));
    _document = step.document;
    _edits--;
    return step.says;
  }

  /// Makes the last undone edit again, answering what it was, or null.
  String? redo() {
    if (_forward.isEmpty) return null;
    final step = _forward.removeLast();
    _back.add((says: step.says, document: _document));
    _document = step.document;
    _edits++;
    return step.says;
  }

  /// The document as its file is written.
  String write() => _document.encode();

  /// Says the document now is what is on disk.
  void saved() => _savedAt = _edits;
}
