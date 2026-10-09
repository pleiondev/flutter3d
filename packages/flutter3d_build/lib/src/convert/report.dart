/// What `flutter3d convert` did with one input: what it wrote, what it
/// mapped, and what it left behind and why.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show DocumentFormatException, FormatSpec;

/// How one input ended.
///
/// A `final class` with const instances rather than an `enum`, the shape the
/// structure rule asks of a published set a later release may add to.
final class ConvertOutcome {
  const ConvertOutcome._(this.name, this.exitCode);

  /// The word the report prints.
  final String name;

  /// The process exit code an input ending this way asks for. The command
  /// exits with the most serious one any input asked for.
  final int exitCode;

  /// Converted. Exit code 0.
  static const ConvertOutcome converted = ConvertOutcome._('converted', 0);

  /// Could not be read or written. Exit code 1.
  static const ConvertOutcome failed = ConvertOutcome._('failed', 1);

  /// Needs a program that is not installed (FBX2glTF, Blender). Exit code 3.
  static const ConvertOutcome missingTool = ConvertOutcome._('missing-tool', 3);

  /// Would replace a file that differs, and `--overwrite` was not given.
  /// Exit code 4.
  static const ConvertOutcome wouldOverwrite = ConvertOutcome._(
    'would-overwrite',
    4,
  );

  @override
  String toString() => name;
}

/// The exit code for a whole run: 0 when every input converted, otherwise
/// the code of the most serious outcome — a failure (1) before a missing
/// tool (3) before a refusal to overwrite (4).
int exitCodeFor(Iterable<ConvertOutcome> outcomes) {
  const severity = <ConvertOutcome>[
    ConvertOutcome.failed,
    ConvertOutcome.missingTool,
    ConvertOutcome.wouldOverwrite,
  ];
  for (final outcome in severity) {
    if (outcomes.contains(outcome)) return outcome.exitCode;
  }
  return 0;
}

/// One input's report.
///
/// **Collected as the converter goes**, so it is the one mutable thing in a
/// conversion: every reader appends to it rather than threading a list back
/// through each return. [toJson] is what `--report` writes, sorted where
/// order is not meaning, so two runs over the same input write the same
/// bytes.
final class ConvertReport {
  ConvertReport(this.input, this.format);

  /// The input as it was named on the command line, or found by a glob.
  final String input;

  /// What it was read as: `gltf`, `unity-prefab`, `godot-scene` and so on.
  final String format;

  /// How it ended. [ConvertOutcome.converted] until something says
  /// otherwise.
  ConvertOutcome outcome = ConvertOutcome.converted;

  /// Why it failed, when it did.
  String? error;

  /// Every file this input produced, relative to the output directory.
  final List<String> written = <String>[];

  /// Each thing the source said that arrived in the output, in a line.
  final List<String> mapped = <String>[];

  /// Each thing the source said that did not arrive, with the reason.
  final List<String> dropped = <String>[];

  /// What arrived, but not exactly: an approximation, a guess, a default.
  final List<String> warnings = <String>[];

  /// Records [what] as mapped.
  void map(String what) => mapped.add(what);

  /// Records [what] as dropped, because of [why].
  void drop(String what, String why) => dropped.add('$what: $why');

  /// Records an approximation.
  void warn(String what) => warnings.add(what);

  /// Marks the input failed with [message].
  void fail(String message, {ConvertOutcome as = ConvertOutcome.failed}) {
    outcome = as;
    error = message;
  }

  /// The report as `--report` writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'input': input,
    'format': format,
    'outcome': outcome.name,
    'error': ?error,
    'written': <String>[...written]..sort(),
    'mapped': mapped,
    'dropped': dropped,
    'warnings': warnings,
  };

  /// The report as the terminal shows it.
  String describe() {
    final lines = <String>[
      '$input ($format): ${outcome.name}${error == null ? '' : ' — $error'}',
      for (final path in <String>[...written]..sort()) '  wrote    $path',
      for (final line in mapped) '  mapped   $line',
      for (final line in warnings) '  approx   $line',
      for (final line in dropped) '  dropped  $line',
    ];
    return lines.join('\n');
  }
}

/// The version of the document `--report` writes, and the newest
/// [convertReportsFrom] reads.
const int convertReportVersion = 1;

/// The file `flutter3d convert --report <file>` writes, for a
/// `FormatRegistry`: the envelope, then `reports`, one [ConvertReport] an
/// input.
///
/// Before 1.0 the file was the bare list of reports, which
/// [convertReportsFrom] still reads.
const FormatSpec convertReportFormat = FormatSpec(
  id: 'f3d.convertReport',
  version: convertReportVersion,
  suffixes: <String>['.report.json'],
  fixture: 'test/fixtures/v<N>/convert.report.json',
);

/// [reports] as `--report` writes them.
Map<String, Object?> convertReportDocument(Iterable<ConvertReport> reports) =>
    <String, Object?>{
      ...convertReportFormat.envelope(),
      'reports': <Object?>[for (final r in reports) r.toJson()],
    };

/// The reports a `--report` file holds, each as [ConvertReport.toJson]
/// wrote it: from the enveloped document, or from the bare list the file
/// was before 1.0.
///
/// Throws a [DocumentFormatException] for another format's document, a
/// newer version, or a document with no list of reports.
List<Map<String, Object?>> convertReportsFrom(Object? json) {
  final list = switch (json) {
    final List<Object?> bare => bare,
    final Map<String, Object?> document => switch (convertReportFormat.open(
      document,
      refuse: DocumentFormatException.new,
    )['reports']) {
      final List<Object?> reports => reports,
      _ => throw const DocumentFormatException(
        'a convert report with no "reports" list',
      ),
    },
    _ => throw const DocumentFormatException(
      'a convert report is a JSON object with "reports"',
    ),
  };
  return <Map<String, Object?>>[
    for (final each in list)
      if (each is Map<String, Object?>)
        each
      else
        throw DocumentFormatException('a convert report entry is $each'),
  ];
}
