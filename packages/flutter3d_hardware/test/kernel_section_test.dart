// The kernel section: each compute kernel's `.f3dmat compute` source by
// stage name, in a bundle every device with compute reads.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

void main() {
  test('kernel sources survive a bundle round trip, by name', () {
    // Mutation: write the payload under the material section's id, and a
    // device looking for kernels finds none.
    const source = 'compute Twice { kernel { } }';
    final bytes = ShaderBundle(
      name: 'kernels',
      sdk: '',
      stages: const <ShaderBundleStage>[
        ShaderBundleStage('Twice', fragment: false),
      ],
      sections: <String, ByteData>{
        ShaderBundle.kernelSection: encodeKernelSection(<String, String>{
          'Twice': source,
        }),
      },
    ).encode();
    final bundle = ShaderBundle.decode(bytes);
    expect(decodeKernelSection(bundle), <String, String>{'Twice': source});
    expect(decodeMaterialSection(bundle), isEmpty);
  });

  test('a kernel section from a newer build is stale, by name', () {
    // Mutation: read any version, and a payload whose shape moved is read
    // as this one's.
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'version': kernelSectionVersion + 1,
        'stages': <String, String>{},
      }),
    );
    final bundle = ShaderBundle(
      name: 'future',
      sdk: '',
      stages: const <ShaderBundleStage>[],
      sections: <String, ByteData>{
        ShaderBundle.kernelSection: ByteData.sublistView(
          Uint8List.fromList(payload),
        ),
      },
    );
    expect(
      () => decodeKernelSection(bundle),
      throwsA(
        isA<ShaderBundleException>()
            .having((e) => e.stale, 'stale', isTrue)
            .having((e) => e.reason, 'reason', contains('"kernel"')),
      ),
    );
  });
}
