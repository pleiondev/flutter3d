/// Where a plugin suite's report goes when there is no file system to put
/// it on: nowhere. A suite run in a browser still runs its checks; the
/// report is written by the same suite on the VM, where a plugin's author
/// and `plugin.report` read it.
library;

/// Writes nothing: a browser has no package directory.
void writeConformanceReportFile(
  String plugin,
  Map<String, Object?> Function() report,
) {}
