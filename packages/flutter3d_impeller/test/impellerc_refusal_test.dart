/// What `impellerc` says when it refuses a stage, read as a tool reads a
/// `ShaderCompileException`.
///
///     flutter test test/impellerc_refusal_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:flutter_test/flutter_test.dart';

const String _said =
    'shaders/pbr.frag:14:7: error: \'vex3\' : undeclared identifier\n'
    'shaders/pbr.frag:20:3: error: \'out_color\' : undeclared identifier\n';

void main() {
  test('each error impellerc placed is a diagnostic, with the stage', () {
    // Mutation: the build exception left without a cause, as it was — a
    // tool reading a refused build gets one string and no place.
    final refusal = impellercRefusal(_said, bundle: 'flutter3d.shaderbundle');
    expect(refusal.backend, 'Impeller');
    expect(refusal.target, 'impeller');
    expect(refusal.stage, 'fragment');
    expect(refusal.line, 14);
    expect(refusal.column, 7);
    expect(<int?>[for (final d in refusal.diagnostics) d.line], <int?>[14, 20]);
  });

  test('the build exception carries it as its cause', () {
    final error = ShaderBundleBuildException(
      'impellerc failed (1)',
      cause: impellercRefusal(_said, bundle: 'flutter3d.shaderbundle'),
    );
    expect(error.cause, isA<ShaderCompileException>());
  });
}
