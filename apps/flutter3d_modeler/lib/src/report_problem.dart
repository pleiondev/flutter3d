/// The URL a "Report a problem" action opens — `rel-15`'s own decision
/// behind the button, without Flutter.
///
/// **No telemetry, and that is the whole design.** Nothing here reaches a
/// server on its own: the returned [Uri] is handed to whatever the caller
/// already opens a browser with, and the report is exactly what a person
/// types into the form that opens — nothing is sent before they choose to.
/// A caller that wants a button wires this to one; that button, and reading
/// `flutter --version` for [environment], belong to `main.dart`, not here.
library;

/// The prefilled GitHub issue draft for `.github/ISSUE_TEMPLATE/
/// modeler_report.yml` — one query parameter per field the template
/// declares by its own `id`, which is the convention GitHub's own issue
/// forms read a prefill from.
///
/// [environment] is `flutter --version`'s own output plus the platform, the
/// same thing every other template in this repository already asks a
/// person to paste by hand; filling it in for them is one fewer blank a
/// bug report goes out missing.
///
/// [whatHappened], when given, seeds the "what happens" field — a caller
/// that already knows something concrete (the file that was open, the
/// backend in use) can save a person retyping it.
Uri reportProblemUrl({
  required String environment,
  String? whatHappened,
}) => Uri.https('github.com', '/pleiondev/flutter3d/issues/new', <String, String>{
  'template': 'modeler_report.yml',
  'environment': environment,
  if (whatHappened != null && whatHappened.isNotEmpty) 'what': whatHappened,
});
