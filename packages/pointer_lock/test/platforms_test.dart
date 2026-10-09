/// Which native platforms the method channel answers for.
///
///     flutter test test/platforms_test.dart
///
/// The method channel is the native side; in a browser the web
/// implementation answers instead, and this one says no everywhere.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointer_lock/src/pointer_lock_method_channel.dart';

void main() {
  test('the whitelist is the platforms with a native side, and no more', () {
    // The list that has to change the day another platform is written, which
    // is the point: a table nobody updates is one that goes stale. The phones
    // have no pointer to capture and answer false, so a game shows its touch
    // controls instead of meeting a `MissingPluginException`.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const written = <TargetPlatform>{
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    };
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        MethodChannelPointerLock().isSupported,
        written.contains(platform),
        reason: '$platform',
      );
    }
  });
}
