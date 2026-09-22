/// `report_problem`: `rel-15`'s own decision behind the button, without
/// Flutter.
///
///     dart test test/report_problem_test.dart
library;

import 'package:flutter3d_modeler/src/report_problem.dart';
import 'package:test/test.dart';

void main() {
  test('names the modeler\'s own template — the row\'s own "форма в '
      'chooser"', () {
    // Mutation: point at `bug_report.yml` instead. The row exists so a
    // modeler bug lands under its own label, not the engine's.
    final url = reportProblemUrl(environment: 'Flutter 3.99.0, macOS');
    expect(url.host, 'github.com');
    expect(url.path, '/pleiondev/flutter3d/issues/new');
    expect(url.queryParameters['template'], 'modeler_report.yml');
  });

  test(
    'prefills the environment field so nobody retypes flutter --version',
    () {
      final url = reportProblemUrl(environment: 'Flutter 3.99.0, macOS');
      expect(url.queryParameters['environment'], 'Flutter 3.99.0, macOS');
    },
  );

  test('leaves "what" unset when nothing concrete is known', () {
    final url = reportProblemUrl(environment: 'Flutter 3.99.0, macOS');
    expect(url.queryParameters.containsKey('what'), isFalse);
  });

  test('prefills "what" when the caller already knows something concrete', () {
    final url = reportProblemUrl(
      environment: 'Flutter 3.99.0, macOS',
      whatHappened: 'Opened teapot.f3dproj, the viewport went black.',
    );
    expect(
      url.queryParameters['what'],
      'Opened teapot.f3dproj, the viewport went black.',
    );
  });

  test('an empty "what" is the same as none — nothing to prefill', () {
    // Mutation: check `whatHappened != null` alone. A caller that passes ''
    // rather than null would then prefill an empty field, which reads to a
    // person as "this was supposed to say something and did not" rather
    // than as a field nobody touched.
    final url = reportProblemUrl(
      environment: 'Flutter 3.99.0, macOS',
      whatHappened: '',
    );
    expect(url.queryParameters.containsKey('what'), isFalse);
  });
}
