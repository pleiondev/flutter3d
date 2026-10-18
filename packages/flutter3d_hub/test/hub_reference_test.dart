import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hub/flutter3d_hub.dart';
import 'package:test/test.dart';

/// The reference format is fixed for good, so its fixture is the contract:
/// every text in `valid` parses to the parts beside it and prints back as
/// itself, and every text in `invalid` is refused with a sentence that says
/// what is wrong.
void main() {
  final fixture =
      jsonDecode(File('test/fixtures/references.json').readAsStringSync())
          as Map<String, Object?>;

  group('a valid reference', () {
    for (final entry in (fixture['valid']! as List).cast<Map>()) {
      final text = entry['text']! as String;
      test(text, () {
        final reference = HubReference.parse(text);
        expect(reference.uuid, entry['uuid']);
        expect(reference.version, entry['version']);
        expect(reference.sha256, entry['sha256']);
        expect(reference.toString(), text);
        expect(HubReference.tryParse(text), reference);
      });
    }
  });

  group('an invalid reference', () {
    for (final entry in (fixture['invalid']! as List).cast<Map>()) {
      final text = entry['text']! as String;
      test(jsonEncode(text), () {
        expect(
          () => HubReference.parse(text),
          throwsA(
            isA<HubReferenceFormatException>()
                .having((e) => e.source, 'source', text)
                .having((e) => e.message, 'message', contains(entry['says']))
                .having((e) => e.message, 'message', endsWith('.')),
          ),
        );
        expect(HubReference.tryParse(text), isNull);
      });
    }
  });

  test('a malformed reference is a format exception of the engine', () {
    expect(
      () => HubReference.parse('chair@1'),
      throwsA(isA<Flutter3dFormatException>()),
    );
  });

  test('the constructor holds the same rules as the parser', () {
    expect(
      () => HubReference(uuid: 'chair', version: 1),
      throwsA(isA<HubReferenceFormatException>()),
    );
    expect(
      () => HubReference(
        uuid: '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90',
        version: 0,
      ),
      throwsA(isA<HubReferenceFormatException>()),
    );
    expect(
      () => HubReference(
        uuid: '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90',
        version: 1,
        sha256: 'abc',
      ),
      throwsA(isA<HubReferenceFormatException>()),
    );
  });

  test('two references are equal when their three parts are', () {
    const uuid = '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90';
    const hash =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    final a = HubReference(uuid: uuid, version: 2);
    expect(a, HubReference.parse('$uuid@2'));
    expect(a.hashCode, HubReference.parse('$uuid@2').hashCode);
    expect(a == HubReference.parse('$uuid@3'), isFalse);
    expect(a == HubReference.parse('$uuid@2#sha256=$hash'), isFalse);
  });

  test('withoutChecksum keeps the model and the version', () {
    const text =
        '01928c3a-5b7e-7f00-8d2a-4c6b9e1f3a57@3#sha256='
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    expect(
      HubReference.parse(text).withoutChecksum.toString(),
      '01928c3a-5b7e-7f00-8d2a-4c6b9e1f3a57@3',
    );
  });

  test('the fixture says the format the parser documents', () {
    expect(fixture['format'], HubReference.formatDescription);
  });
}
