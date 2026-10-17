/// Writes a plugin suite's report as `<package>.conformance.json` in the
/// package the suite runs in.
library;

import 'dart:convert';
import 'dart:io';

/// The file the report of a suite run in [directory] is written to:
/// `<package>.conformance.json`, named by the package's pubspec, or by
/// [plugin] when there is none to read.
File conformanceReportFileIn(Directory directory, String plugin) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  final match = pubspec.existsSync()
      ? RegExp(
          r'^name:\s*([a-z0-9_]+)',
          multiLine: true,
        ).firstMatch(pubspec.readAsStringSync())
      : null;
  final name = match?.group(1);
  return File('${directory.path}/${name ?? plugin}.conformance.json');
}

/// The outcomes of the report already beside the pubspec of the package
/// the test runner was started in, as JSON; none where there is no report
/// or it does not read.
List<Object?> readConformanceReportOutcomes(String plugin) {
  final file = conformanceReportFileIn(Directory.current, plugin);
  if (!file.existsSync()) return const <Object?>[];
  try {
    return switch (jsonDecode(file.readAsStringSync())) {
      {'format': 'f3d.conformance', 'outcomes': final List<Object?> outcomes} =>
        outcomes,
      _ => const <Object?>[],
    };
  } on FormatException {
    return const <Object?>[];
  }
}

/// Writes [report] beside the pubspec of the package the test runner was
/// started in, which is the plugin's own: `dart test` runs from the
/// package root.
void writeConformanceReportFile(
  String plugin,
  Map<String, Object?> Function() report,
) {
  conformanceReportFileIn(Directory.current, plugin).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report())}\n',
  );
}
