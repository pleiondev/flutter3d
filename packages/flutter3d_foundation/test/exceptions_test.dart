/// The two leaves every backend and loader share, under the root —
/// readiness review §2.2.6.
///
///     dart test test/exceptions_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('a shader the driver refused names the stage, the backend and the '
      'log, and is a format exception', () {
    // Mutation: drop `$shader` from `message` — the sentence no longer says
    // which of a bundle's hundred stages it was.
    const refused = ShaderCompileException(
      shader: 'pbr.frag',
      backend: 'WebGL 2',
      log: "ERROR: 0:12: 'x' : undeclared identifier",
    );
    expect(refused, isA<Flutter3dFormatException>());
    expect(refused.message, contains('pbr.frag'));
    expect(refused.message, contains('WebGL 2'));
    expect(refused.message, contains('undeclared identifier'));
    expect(
      refused.toString(),
      startsWith('ShaderCompileException: WebGL 2 could not compile'),
    );
    expect(
      const ShaderCompileException(
        shader: 'a with b',
        backend: 'WebGL 2',
        log: '',
      ).message,
      'WebGL 2 could not compile a with b',
    );
  });

  test('a missing asset names its key and keeps what the platform said', () {
    // Mutation: put the cause into `message` — the platform's own sentence
    // would then be said twice by `toString`.
    const missing = AssetNotFoundException(
      'assets/crate.f3d',
      detail: 'declare it',
      cause: 'Unable to load asset',
    );
    expect(missing, isA<ResourceException>());
    expect(missing.message, 'no asset "assets/crate.f3d": declare it');
    expect(
      missing.toString(),
      'AssetNotFoundException: no asset "assets/crate.f3d": declare it '
      '(caused by Unable to load asset)',
    );
    expect(const AssetNotFoundException('x').message, 'no asset "x"');
  });
}
