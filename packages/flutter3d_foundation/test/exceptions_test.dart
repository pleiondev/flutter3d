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

  test('a refusal carries where it happened, for a tool to point at', () {
    // Mutation: drop `line` from the first diagnostic's fallback — an
    // exception built from a list would answer no line.
    const one = ShaderCompileException(
      shader: 'pbr.frag',
      backend: 'WebGL 2',
      log: "ERROR: 0:12: 'x' : undeclared identifier",
      stage: 'fragment',
      target: 'webgl',
      line: 12,
      column: 3,
      excerpt: '  x = 1.0;',
    );
    expect(one.stage, 'fragment');
    expect(one.target, 'webgl');
    expect(one.line, 12);
    expect(one.column, 3);
    expect(one.excerpt, '  x = 1.0;');
    expect(one.diagnostics, isEmpty);
    expect(one.message, contains('line 12'));

    final many = ShaderCompileException(
      shader: 'sky.wgsl',
      backend: 'WebGPU',
      log: 'two errors',
      target: 'webgpu',
      diagnostics: const <ShaderDiagnostic>[
        ShaderDiagnostic(
          'unknown type',
          line: 4,
          column: 9,
          excerpt: 'var a: flot;',
        ),
        ShaderDiagnostic('missing ;', line: 7),
      ],
    );
    expect(many.line, 4);
    expect(many.column, 9);
    expect(many.excerpt, 'var a: flot;');
    expect(many.diagnostics, hasLength(2));
    expect(many.toJson()['diagnostics'], hasLength(2));
    expect(many.toJson()['target'], 'webgpu');

    // The constructor of before keeps working and says nothing of a place.
    const bare = ShaderCompileException(shader: 'a', backend: 'b', log: '');
    expect(bare.line, isNull);
    expect(bare.stage, isNull);
    expect(bare.diagnostics, isEmpty);
  });

  test('reads the places out of a compiler log', () {
    // Mutation: read the GLSL source-string number as the line — every
    // ANGLE error would point at line 0.
    const source = 'void main() {\n  float a = b;\n  gl_FragColor = c;\n}\n';
    final glsl = ShaderDiagnostic.parseLog(
      "ERROR: 0:2: 'b' : undeclared identifier\n"
      "ERROR: 0:3: 'c' : undeclared identifier\n"
      'ERROR: 2 compilation errors.  No code generated.',
      stage: 'fragment',
      source: source,
    );
    expect(glsl, hasLength(2));
    expect(glsl.first.line, 2);
    expect(glsl.first.stage, 'fragment');
    expect(glsl.first.message, "'b' : undeclared identifier");
    expect(glsl.first.excerpt, '  float a = b;');
    expect(glsl.last.line, 3);

    final clang = ShaderDiagnostic.parseLog(
      'pbr.wgsl:14:7 error: unresolved identifier "foo"',
    );
    expect(clang.single.line, 14);
    expect(clang.single.column, 7);
    expect(clang.single.message, 'unresolved identifier "foo"');

    final unread = ShaderDiagnostic.parseLog('the driver gave up');
    expect(unread.single.line, isNull);
    expect(unread.single.message, 'the driver gave up');
    expect(ShaderDiagnostic.parseLog('  '), isEmpty);

    final back = ShaderDiagnostic.fromJson(glsl.first.toJson());
    expect(back, glsl.first);
  });

  test('a refused capability names it, who refused and how to ask first', () {
    // Mutation: drop `askedBy` from the message — a caller would not learn
    // where the question that avoids the throw is asked.
    const refused = UnsupportedCapability(
      _Shadows(),
      backend: 'the software renderer',
      reason: 'it draws no depth',
    );
    expect(refused, isA<CapabilityException>());
    expect(refused.feature.name, 'soft-shadows');
    expect(
      refused.message,
      'the software renderer does not support soft-shadows: it draws no '
      'depth. Ask whether `Renderer.capabilities` has it before calling.',
    );
    expect(
      const UnsupportedCapability(_Bare(), backend: 'x').message,
      'x does not support bare.',
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

final class _Shadows extends Capability {
  const _Shadows();

  @override
  String get name => 'soft-shadows';

  @override
  String get askedBy => '`Renderer.capabilities`';
}

final class _Bare extends Capability {
  const _Bare();

  @override
  String get name => 'bare';
}
