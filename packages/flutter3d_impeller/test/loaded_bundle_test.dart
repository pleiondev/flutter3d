/// What this backend refuses before flutter_gpu ever sees a byte.
///
/// The section selection and the SDK check are pure, and this is the only
/// place they can be tested: the device itself needs Impeller, which a
/// headless `flutter test` does not provide, so the loading path proper is
/// covered by `tool/conformance.sh` and the `loaded-shader` golden.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:flutter_test/flutter_test.dart';

ShaderBundle _bundle({String sdk = '3.13.0', bool withSection = true}) =>
    ShaderBundle(
      name: 'effects',
      sdk: sdk,
      stages: const <ShaderBundleStage>[
        ShaderBundleStage('Stripes', fragment: true),
      ],
      sections: <String, ByteData>{
        if (withSection) ShaderBundle.impellerSection: ByteData(8),
      },
    );

void main() {
  test('the running SDK reads as a version token', () {
    // `Platform.version` starts with the same token `dart --version` prints,
    // which is what the packer writes. Pinned here so a Dart that changes the
    // shape of its version string fails a test and not a bundle load.
    expect(runningSdk, matches(RegExp(r'^\d+\.\d+\.\d+')));
    expect(runningSdk, isNot(contains(' ')));
  });

  test('a bundle compiled on this SDK yields its impeller section', () {
    final section = impellerSectionOf(
      _bundle(sdk: runningSdk),
      running: runningSdk,
    );
    expect(section.lengthInBytes, 8);
  });

  test('a bundle from another SDK is refused by name, naming both SDKs', () {
    // Mutation: drop the `compiledFor` check and the section comes back for
    // a bundle nobody should trust.
    expect(
      () => impellerSectionOf(_bundle(sdk: '3.9.9'), running: '3.13.0'),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', 'effects')
            .having((r) => r.reason, 'reason', contains('"3.9.9"'))
            .having((r) => r.reason, 'reason', contains('"3.13.0"')),
      ),
    );
  });

  test('a bundle that does not say what compiled it is refused', () {
    expect(
      () => impellerSectionOf(_bundle(sdk: ''), running: '3.13.0'),
      throwsA(isA<ShaderBundleRefused>()),
    );
  });

  test('a bundle with no impeller section is refused by name', () {
    expect(
      () => impellerSectionOf(
        _bundle(withSection: false, sdk: '3.13.0'),
        running: '3.13.0',
      ),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', 'effects')
            .having((r) => r.reason, 'reason', contains('impeller')),
      ),
    );
  });
}
