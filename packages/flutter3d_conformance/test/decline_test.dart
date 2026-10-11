// A check that cannot be asked declines through `decline`, and only through
// it: never a silent return a harness counts as a pass, and never an
// exception built by hand that leaves out who declined.
import 'dart:io';

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

ConformanceCheck _check(String name) =>
    conformanceChecks.firstWhere((c) => c.name == name);

/// [name] run on [device] declines, and the line names the device's type.
Future<void> _declines(String name, GraphicsDevice device) async {
  await expectLater(
    _check(name).run(device),
    throwsA(
      isA<ConformanceDeclinedException>().having(
        (e) => e.reason,
        'reason',
        startsWith('${device.runtimeType} '),
      ),
    ),
    reason: '"$name" on a ${device.runtimeType} that cannot be asked it',
  );
}

void main() {
  group('a check a device cannot be asked declines, naming the device', () {
    // Mutation, for each: put back the `return` the check had, and it passes
    // on a device that was asked nothing.
    test('a stencil test, on a device without stencil', () async {
      await _declines(
        'a stencil test keeps what it should',
        FakeBackend(supportsStencil: false),
      );
      await _declines(
        'a pass starts with the stencil test off',
        FakeBackend(supportsStencil: false),
      );
    });

    test('a viewport of a mip level, on a device that renders to none', () {
      return _declines(
        'a pass\'s initial viewport covers the level',
        FakeBackend(supportsRenderToMip: false),
      );
    });

    test('a block a shader lacks, on a device that reflects no shader', () {
      // A fake with no stage table accepts every bind, which is what a
      // backend without reflection does.
      return _declines(
        'a block missing a member the caller named is refused',
        FakeBackend(),
      );
    });

    test('a sampler slot a stage lacks, on a device that reflects none', () {
      return _declines(
        'a texture bound to a slot the stage lacks is false',
        FakeBackend(),
      );
    });

    test('a compressed block, on a device that samples no family', () {
      // Mutation: drop the decline after the loop, and a device with none of
      // the three formats runs nothing and passes.
      return _declines(
        'a compressed format it supports samples its colour back',
        FakeBackend(
          unsupportedFormats: const <TextureFormat>{
            TextureFormat.bc1RGBAUNormInt,
            TextureFormat.etc2RGB8UNormInt,
            TextureFormat.astc4x4LDR,
          },
        ),
      );
    });

    test('a compute check, on a device without compute', () {
      // Mutation: build the exception by hand, and the line no longer says
      // which backend declined.
      return _declines('a compute pass scans a buffer in place', FakeBackend());
    });

    test('a float filter, on a device without one', () {
      return _declines(
        'a device that filters 32-bit floats filters and renders them',
        FakeBackend(),
      );
    });
  });

  test('no check builds a decline by hand or returns before asking', () {
    // The rule the cases above are instances of, held over every check file,
    // so a check written next year declines the same way.
    final source = Directory('lib/src');
    final found = <String>[];
    for (final file in source.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        final where = '${file.path}:${i + 1}';
        if (line.contains('ConformanceDeclinedException(')) {
          found.add('$where builds the exception; call decline(device, why)');
        }
        if (RegExp(
          r'!\s*device\.features\.has\([^)]*\)\)?\s*\)\s*return;',
        ).hasMatch(line)) {
          found.add('$where returns on a missing feature; decline instead');
        }
      }
    }
    expect(found, isEmpty);
  });
}
