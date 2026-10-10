/// `ShaderHandle.dispose` and `GraphicsDevice.releaseSampler`: giving back
/// what a library or a device keeps for a caller.
///
/// A stage belongs to the library that compiled it; dispose is the caller
/// handing its reference back, after which the library forgets the handle
/// and answers the name with a new one. A sampler is a value, and a device
/// that keeps an object per description drops it when asked.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart' show wrapShader;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

ShaderBundle _bundle(List<String> fragments) => ShaderBundle(
  name: 'looks',
  sdk: '3.13.0',
  stages: <ShaderBundleStage>[
    for (final name in fragments) ShaderBundleStage(name, fragment: true),
  ],
  sections: <String, ByteData>{ShaderBundle.webglSection: ByteData(0)},
);

void main() {
  group('a shader handle', () {
    test('disposed, the library forgets it and answers anew', () {
      final library = FakeShaderLibrary();
      final first = library['Pbr']!;
      expect(library['Pbr'], same(first));
      expect(first.isDisposed, isFalse);

      first.dispose();
      expect(first.isDisposed, isTrue);
      final second = library['Pbr']!;
      expect(second, isNot(same(first)));
      expect(second.isDisposed, isFalse);
    });

    test('a second dispose does nothing to the handle kept after it', () {
      final library = FakeShaderLibrary();
      final first = library['Pbr']!..dispose();
      final second = library['Pbr']!;
      first.dispose();
      expect(library['Pbr'], same(second));
    });

    test('a handle no library keeps has nothing to give back', () {
      final handle = wrapShader(backend: Object(), name: 'Bare')..dispose();
      handle.dispose();
      expect(handle.isDisposed, isTrue);
    });

    test('a refresh no longer counts a disposed stage as in use', () async {
      final device = FakeBackend();
      final loaded = await device.loadShaders(
        _bundle(<String>['Stripes', 'Dots']).encode(),
      );
      final stripes = loaded['Stripes']!;
      expect(loaded['Dots'], isNotNull);
      // Held, a stage the new bundle drops is a refusal naming it.
      expect(
        () => loaded.refresh(_bundle(<String>['Dots']).encode()),
        throwsA(isA<ShaderBundleException>()),
      );
      stripes.dispose();
      loaded.refresh(_bundle(<String>['Dots']).encode());
      expect(loaded['Stripes'], isNull);
    });
  });

  group('a sampler', () {
    test('released on a device that samples by value, nothing happens', () {
      final device = FakeBackend();
      expect(
        () => device.releaseSampler(SamplerDescriptor.linearRepeat),
        returnsNormally,
      );
    });
  });
}
