/// The channel and the message words, held against every native side.
///
///     flutter test test/native_sources_test.dart
///
/// **The map is a wire, and two halves write it.** The Dart side reads
/// `event`, `device`, `slot`, `axes`, `code` and `down` out of a map the
/// Kotlin, Swift, Windows and Linux plugins build by hand, and a key spelled
/// differently on one of them reads as absent: a controller that never
/// connects, or a button that is never down. Nothing compiles the two halves
/// together, so this reads the native sources as text, the way
/// `flutter3d_pointer_lock` holds its channel names.
///
/// Mutation: spell `"device"` as `"deviceId"` in `GamepadPlugin.kt`, or the
/// channel `dev.flutter3d/gamepad` in `pad_input_plugin.cc`, and this names
/// the side.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/src/gamepad_method_channel.dart';

/// Each native side, and the words it has to send: the map keys and the
/// `event` values the Dart mirrors of that platform read.
const Map<String, List<String>> _sides = <String, List<String>>{
  'android/src/main/kotlin/dev/flutter3d/gamepad/GamepadPlugin.kt': <String>[
    'event',
    'device',
    'name',
    'axes',
    'code',
    'down',
    'connected',
    'disconnected',
    'relaxed',
    'key',
  ],
  'darwin/pad_input/Sources/pad_input/GamepadPlugin.swift': <String>[
    'event',
    'slot',
    'name',
    'connected',
    'disconnected',
    'relaxed',
  ],
  'windows/pad_input_plugin.cpp': <String>[
    'event',
    'slot',
    'connected',
    'disconnected',
    'relaxed',
  ],
  'linux/pad_input_plugin.cc': <String>[
    'event',
    'slot',
    'connected',
    'disconnected',
    'relaxed',
  ],
};

void main() {
  final channel = MethodChannelGamepad().eventChannel.name;

  test('the channel is the engine\'s', () {
    expect(channel, 'dev.flutter3d/gamepad/events');
  });

  for (final MapEntry(key: path, value: words) in _sides.entries) {
    test('$path answers on the channel and sends the words Dart reads', () {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('"$channel"'),
        reason: '$path does not open $channel',
      );
      for (final word in words) {
        expect(
          source,
          contains('"$word"'),
          reason: '$path never writes "$word", which the Dart side reads',
        );
      }
    });
  }

  test('every word a native side sends is one the Dart side reads', () {
    final dart = <String>[
      for (final file in Directory('lib/src').listSync())
        if (file is File && file.path.endsWith('.dart'))
          file.readAsStringSync(),
    ].join('\n');
    for (final word in _sides.values.expand((List<String> w) => w).toSet()) {
      // `name` is forwarded for a person reading a log; nothing maps it.
      if (word == 'name') continue;
      expect(
        dart,
        contains("'$word'"),
        reason: 'a native side sends "$word" and no Dart mirror reads it',
      );
    }
  });
}
