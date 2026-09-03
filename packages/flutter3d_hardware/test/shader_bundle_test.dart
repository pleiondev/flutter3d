/// The bundle container: what `encode` writes, `decode` reads back, and what
/// it refuses.
///
/// A format is a fact only while something round-trips it. Every field goes
/// through here — the name a refusal carries, the SDK token the compiled
/// backends compare, the stage list the software backend answers from, and
/// the sections — and every way the bytes can be wrong comes back as a
/// `ShaderBundleRefused` that names the bundle when the name was readable.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

ShaderBundle _sample() => ShaderBundle(
  name: 'effects',
  sdk: '3.13.0',
  stages: const <ShaderBundleStage>[
    ShaderBundleStage('MeshVertex', fragment: false),
    ShaderBundleStage('Stripes', fragment: true),
  ],
  sections: <String, ByteData>{
    ShaderBundle.impellerSection: Uint8List.fromList(<int>[
      1,
      2,
      3,
      4,
      5,
    ]).buffer.asByteData(),
    ShaderBundle.webglSection: ByteData(0),
  },
);

void main() {
  test('a bundle survives the round trip field by field', () {
    // Mutation: swap the stage kind byte in `encode` — the fragment flag comes
    // back inverted and this fails on `Stripes`.
    final bytes = _sample().encode();
    final back = ShaderBundle.decode(bytes);

    expect(back.name, 'effects');
    expect(back.sdk, '3.13.0');
    expect(back.stages.map((s) => s.name), <String>['MeshVertex', 'Stripes']);
    expect(back.stages[0].fragment, isFalse);
    expect(back.stages[1].fragment, isTrue);
    expect(
      back.section(ShaderBundle.impellerSection)!.buffer.asUint8List(),
      <int>[1, 2, 3, 4, 5],
    );
    expect(back.section(ShaderBundle.webglSection)!.lengthInBytes, 0);
    expect(back.section('vulkan'), isNull);
  });

  test('a decoded section is a copy that starts at zero', () {
    // A backend hands its section to a native parser, and a view with an
    // offset into the whole bundle is the kind of thing a parser reads from
    // byte zero. Mutation: return `ByteData.sublistView` in `_Reader.bytes`
    // and the offset here stops being zero.
    final back = ShaderBundle.decode(_sample().encode());
    final section = back.section(ShaderBundle.impellerSection)!;
    expect(section.offsetInBytes, 0);
    expect(section.lengthInBytes, section.buffer.lengthInBytes);
  });

  test('bytes that are not a bundle are refused, and say so', () {
    // Zero bytes, short bytes, and a plausible-looking file with the wrong
    // magic. None has a name to give, so the refusal has none.
    for (final bytes in <ByteData>[
      ByteData(0),
      ByteData(3),
      ByteData(64),
      Uint8List.fromList('IPSB....'.codeUnits).buffer.asByteData(),
    ]) {
      expect(
        () => ShaderBundle.decode(bytes),
        throwsA(
          isA<ShaderBundleRefused>()
              .having((r) => r.name, 'name', isEmpty)
              .having((r) => r.reason, 'reason', contains('F3SB')),
        ),
      );
    }
  });

  test('a truncated bundle is refused by name', () {
    // Cut inside the sections, after the name is readable: the refusal must
    // carry the name, because "which file" is what the reader needs.
    // Mutation: drop the `catch` in `decode` that re-throws with the name and
    // this fails on the empty name.
    final whole = _sample().encode();
    final cut = ByteData.sublistView(whole, 0, whole.lengthInBytes - 3);
    expect(
      () => ShaderBundle.decode(cut),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', 'effects')
            .having((r) => r.reason, 'reason', contains('ends before')),
      ),
    );
  });

  test('a string field that is not UTF-8 is refused, not thrown through', () {
    // `utf8.decode` throws its own `FormatException`, which is the one
    // exception `decode` would otherwise let out that is not a refusal.
    // Mutation: drop the `on FormatException` in `_Reader.string` and the
    // second case throws a `FormatException` past the matcher. The first
    // corrupts the name, which is read before the name is known, so the
    // refusal has none to give; the second corrupts the SDK field, after it.
    final bytes = _sample().encode();
    const nameAt = 4 + 4 + 4; // magic, version, the name's length
    final badName = ByteData.sublistView(
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    )..setUint8(nameAt, 0xFF);
    expect(
      () => ShaderBundle.decode(badName),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', isEmpty)
            .having((r) => r.reason, 'reason', contains('UTF-8')),
      ),
    );
    const sdkAt = nameAt + 'effects'.length + 4;
    final badSdk = ByteData.sublistView(
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    )..setUint8(sdkAt, 0xFF);
    expect(
      () => ShaderBundle.decode(badSdk),
      throwsA(
        isA<ShaderBundleRefused>()
            .having((r) => r.name, 'name', 'effects')
            .having((r) => r.reason, 'reason', contains('UTF-8')),
      ),
    );
  });

  test('a format version this reader does not know is refused', () {
    final bytes = _sample().encode();
    bytes.setUint32(4, 99, Endian.little);
    expect(
      () => ShaderBundle.decode(bytes),
      throwsA(
        isA<ShaderBundleRefused>().having(
          (r) => r.reason,
          'reason',
          contains('format version 99'),
        ),
      ),
    );
  });

  test('compiledFor compares the SDK token and nothing after it', () {
    // The packer writes what `dart --version` says up to the first space; the
    // running application reads `Platform.version`, which carries the channel
    // and a date after the same token. Mutation: compare whole strings and the
    // second case fails.
    final bundle = _sample();
    expect(bundle.compiledFor('3.13.0'), isTrue);
    expect(
      bundle.compiledFor('3.13.0 (stable) (Wed Aug 5 2026) on "macos_arm64"'),
      isTrue,
    );
    expect(bundle.compiledFor('3.12.2 (stable)'), isFalse);
    // A bundle that does not say what compiled it matches nothing.
    const unstamped = ShaderBundle(
      name: 'unstamped',
      sdk: '',
      stages: <ShaderBundleStage>[],
    );
    expect(unstamped.compiledFor(''), isFalse);
    expect(unstamped.compiledFor('3.13.0'), isFalse);
  });

  test('a refusal reads as a sentence, with the name when there is one', () {
    expect(
      const ShaderBundleRefused(
        name: 'effects',
        reason: 'no such SDK',
      ).toString(),
      'the shader bundle "effects" was refused: no such SDK',
    );
    expect(
      const ShaderBundleRefused(name: '', reason: 'not a bundle').toString(),
      'a shader bundle was refused: not a bundle',
    );
  });

  test(
    'the fake device loads a bundle and keeps handle identity across a reload',
    () async {
      // The promise every real backend keeps and the conformance suite checks;
      // a fake has to keep it too, or a test of the reload path proves nothing.
      final device = FakeBackend();
      final loaded = await device.loadShaders(_sample().encode());
      expect(loaded.name, 'effects');
      final before = loaded['Stripes'];
      expect(before, isNotNull);
      expect(loaded['NoSuchStage'], isNull);

      loaded.refresh(_sample().encode());
      expect(identical(loaded['Stripes'], before), isTrue);
      expect(device.loadedLibraries.single.refreshes, 1);

      // And the other half: a bundle without the stage in hand is refused,
      // naming it, and counts as no refresh.
      expect(
        () => loaded.refresh(
          const ShaderBundle(
            name: 'v2',
            sdk: '',
            stages: <ShaderBundleStage>[
              ShaderBundleStage('MeshVertex', fragment: false),
            ],
          ).encode(),
        ),
        throwsA(
          isA<ShaderBundleRefused>()
              .having((r) => r.name, 'name', 'v2')
              .having((r) => r.reason, 'reason', contains('"Stripes"')),
        ),
      );
      expect(loaded.name, 'effects');
      expect(device.loadedLibraries.single.refreshes, 1);

      expect(
        () => device.loadShaders(ByteData(16)),
        throwsA(isA<ShaderBundleRefused>()),
      );
    },
  );
}
