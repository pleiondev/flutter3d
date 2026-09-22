/// Formats an [ExportReport] for a terminal — kept apart from
/// `bin/convert_asset.dart` so a test can check the text without
/// capturing real stdout.
library;

import 'package:flutter3d_core/formats.dart';

/// Writes [report] to [out], one line per warning and one per difference.
void writeReport(ExportReport report, StringSink out) {
  out.writeln('wrote ${report.files.keys.join(', ')}');
  if (report.writerWarnings.isEmpty) {
    out.writeln('no warnings');
  } else {
    out.writeln('${report.writerWarnings.length} warning(s):');
    for (final warning in report.writerWarnings) {
      out.writeln('  - $warning');
    }
  }
  if (report.differences.isEmpty) {
    out.writeln('read back clean: nothing differs from the source');
  } else {
    out.writeln('${report.differences.length} difference(s) reading it back:');
    for (final difference in report.differences) {
      out.writeln('  - $difference');
    }
  }
}
