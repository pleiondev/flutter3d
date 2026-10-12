/// What the playground makes of the text in its editor: a level to draw, or
/// the problems that stop it, each with the line it is on where there is
/// one.
///
/// **No device and no widget in this file**, so a test reads exactly what a
/// visitor typed and holds the answer still.
library;

import 'dart:convert';

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One thing wrong with the document: an error stops it being drawn, a
/// warning is said beside a level that is drawn anyway.
final class Problem {
  const Problem(this.message, {this.line, this.column, this.isError = true});

  final String message;

  /// Where, counted from one, when the text itself is at fault.
  final int? line;
  final int? column;

  final bool isError;

  @override
  String toString() =>
      line == null ? message : 'line $line, column $column: $message';
}

/// What a reading came to: the level as it will be drawn (prefabs and
/// recipes expanded), or null, and the problems found on the way.
typedef Reading = ({Level? level, List<Problem> problems});

/// Reads [text] as a level document, or as a prefab document on its own
/// (an object with `entities` and no `format`), which is drawn as one
/// instance of itself at the origin.
Reading readDocument(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    final (line, column) = _where(text, error.offset);
    return (
      level: null,
      problems: <Problem>[Problem(error.message, line: line, column: column)],
    );
  }
  if (decoded is! Map<String, Object?>) {
    return (
      level: null,
      problems: const <Problem>[
        Problem('a level or a prefab is a JSON object, in braces'),
      ],
    );
  }
  try {
    final authored = _isPrefab(decoded)
        ? Level(
            name: 'prefab',
            prefabs: <String, Prefab>{'prefab': Prefab.fromJson(decoded)},
            entities: <EntityDef>[PrefabInstance.create('prefab')],
          )
        : Level.fromJson(decoded);
    final warnings = <Problem>[
      for (final LevelIssue issue in prefabIssues(authored))
        Problem(
          issue.where == null
              ? issue.message
              : '${issue.where}: ${issue.message}',
          isError: issue.severity == Severity.error,
        ),
    ];
    return (level: expandRecipes(authored), problems: warnings);
  } on LevelFormatException catch (error) {
    return (level: null, problems: <Problem>[Problem(error.message)]);
  } on TypeError catch (error) {
    // A field of the wrong shape that the reader did not name.
    return (level: null, problems: <Problem>[Problem('$error')]);
  }
}

bool _isPrefab(Map<String, Object?> json) =>
    !json.containsKey('format') && json['entities'] is List<Object?>;

/// The line and the column of [offset] in [text], from one.
(int?, int?) _where(String text, int? offset) {
  if (offset == null) return (null, null);
  final before = text.substring(0, offset.clamp(0, text.length));
  final lines = before.split('\n');
  return (lines.length, lines.last.length + 1);
}
