/// `HR5`: the devices Play can be pointed at, as the tool lists them.
///
///     dart test test/devices_test.dart
library;

import 'dart:io';

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:test/test.dart';

/// Trimmed from a real `flutter devices --machine` on a Mac with a phone on
/// the cable, with the line the tool prints first when it has news.
const String _printed = '''
A new version of Flutter is available!
[
  {
    "name": "Galaxy A55",
    "id": "R5CX10ABCDE",
    "isSupported": true,
    "targetPlatform": "android-arm64",
    "emulator": false
  },
  {
    "name": "macOS",
    "id": "macos",
    "isSupported": true,
    "targetPlatform": "darwin",
    "emulator": false
  },
  {
    "name": "Old iPad",
    "id": "00008",
    "isSupported": false,
    "targetPlatform": "ios"
  }
]
''';

void main() {
  test('reads the list past whatever the tool said first', () {
    final devices = parseFlutterDevices(_printed);

    expect(devices.map((it) => it.id), <String>['R5CX10ABCDE', 'macos']);
    expect(devices.first.name, 'Galaxy A55');
    expect(devices.first.platform, 'android-arm64');
  });

  test('an unsupported device is not offered', () {
    expect(
      parseFlutterDevices(_printed).where((it) => it.id == '00008'),
      isEmpty,
    );
  });

  test('an id flutter run -d could not be handed safely is not offered', () {
    // Mutation: offer every id the tool printed. An entry a hostile
    // `flutter` shim (or a device name echoed as an id) printed would be
    // offered to an agent that passes it straight back to `play`.
    expect(
      parseFlutterDevices(
        '[{"id": "macos & calc", "name": "Mac"}, '
        '{"id": "macos", "name": "macOS"}]',
      ).map((FlutterDevice it) => it.id),
      <String>['macos'],
    );
  });

  test('something that is not a list is no devices, not a crash', () {
    expect(parseFlutterDevices('No devices found'), isEmpty);
    expect(parseFlutterDevices('[{"id": '), isEmpty);
  });

  test('the tool failing is news of its own', () async {
    await expectLater(
      flutterDevices(
        run: (List<String> arguments) async =>
            ProcessResult(1, 1, '', 'flutter: command not found'),
      ),
      throwsA(
        isA<StateError>().having(
          (it) => it.message,
          'message',
          contains('command not found'),
        ),
      ),
    );
  });

  test('asks the tool the way an IDE does', () async {
    final asked = <List<String>>[];
    final devices = await flutterDevices(
      run: (List<String> arguments) async {
        asked.add(arguments);
        return ProcessResult(1, 0, _printed, '');
      },
    );

    expect(asked.single, <String>['devices', '--machine']);
    expect(devices, hasLength(2));
  });
}
