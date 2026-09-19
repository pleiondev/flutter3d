/// The plan's own account of itself, read from the two files that carry it.
///
/// `doc/plan-status.json` holds the rows that are `done` or `partial`, and a
/// row missing from it is `todo` by the rule `tool/verify_plan.dart` states. So
/// the total comes from the plan's tables, not from the status file: a status
/// file counted alone would say a hundred per cent of what it lists.
library;

import 'dart:convert';
import 'dart:io';

import 'model.dart';

/// A plan row's id, at the start of a table row: letters, digits and hyphens,
/// with at least one digit so a heading such as `| Step |` is not one.
final RegExp _rowId = RegExp(
  r'^\| ((?=[a-z0-9-]*\d)[a-z0-9]+(?:-[a-z0-9]+)+)\b',
);

/// The ids a plan document names as table rows.
Set<String> planRowIds(String plan) => <String>{
  for (final line in plan.split('\n'))
    if (_rowId.firstMatch(line) case final match?) match.group(1)!,
};

/// Reads `doc/model-editor-plan.md` and `doc/plan-status.json` under [root].
PlanSnapshot readPlan(Directory root) {
  final statusFile = File('${root.path}/doc/plan-status.json');
  final planFile = File('${root.path}/doc/model-editor-plan.md');
  if (!statusFile.existsSync()) return const PlanSnapshot.empty();

  final decoded = jsonDecode(statusFile.readAsStringSync());
  final status = decoded is Map<String, Object?> && decoded['status'] is Map
      ? (decoded['status']! as Map).cast<String, Object?>()
      : const <String, Object?>{};

  final ids = <String>{
    ...status.keys,
    if (planFile.existsSync()) ...planRowIds(planFile.readAsStringSync()),
  };

  final rows = <String, String>{
    for (final id in ids)
      id: switch (status[id]) {
        'done' => 'done',
        'partial' => 'partial',
        _ => 'todo',
      },
  };
  return PlanSnapshot(
    total: rows.length,
    done: rows.values.where((v) => v == 'done').length,
    partial: rows.values.where((v) => v == 'partial').length,
    rows: rows,
  );
}
