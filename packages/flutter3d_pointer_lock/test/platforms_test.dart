/// Which native platforms the method channel answers for.
///
///     flutter test test/platforms_test.dart
///
/// The method channel is the native side; in a browser the web
/// implementation answers instead, and this one says no everywhere.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter3d_pointer_lock/src/pointer_lock_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('every native side answers on the channels and the class the package '
      'names', () {
    // The package was published as `pointer_lock` up to 0.4.2+2, and an app
    // can still get that one through another dependency. Both register side
    // by side only if nothing native keeps the old name: a channel left at
    // `dev.flutter3d/pointer_lock` would answer the other plugin's calls, and
    // a `pluginClass` that no source declares fails the app's build, not
    // this package's tests.
    final channel = MethodChannelPointerLock();
    expect(channel.methodChannel.name, 'dev.flutter3d/flutter3d_pointer_lock');
    expect(channel.eventChannel.name, '${channel.methodChannel.name}/events');

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, startsWith('name: flutter3d_pointer_lock\n'));
    const swift =
        'macos/flutter3d_pointer_lock/Sources/flutter3d_pointer_lock/'
        'Flutter3dPointerLockPlugin.swift';
    final sides = <String, (String, String)>{
      swift: ('Flutter3dPointerLockPlugin', 'class Flutter3dPointerLockPlugin'),
      'windows/include/flutter3d_pointer_lock/'
          'flutter3d_pointer_lock_plugin_c_api.h': (
        'Flutter3dPointerLockPluginCApi',
        'void Flutter3dPointerLockPluginCApiRegisterWithRegistrar(',
      ),
      'linux/include/flutter3d_pointer_lock/flutter3d_pointer_lock_plugin.h': (
        'Flutter3dPointerLockPlugin',
        'void flutter3d_pointer_lock_plugin_register_with_registrar(',
      ),
    };
    for (final MapEntry(key: path, value: (pluginClass, declaration))
        in sides.entries) {
      expect(pubspec, contains('pluginClass: $pluginClass\n'), reason: path);
      expect(
        File(path).readAsStringSync(),
        contains(declaration),
        reason: path,
      );
    }
    for (final path in <String>[
      swift,
      'windows/flutter3d_pointer_lock_plugin.cpp',
      'linux/flutter3d_pointer_lock_plugin.cc',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('"${channel.methodChannel.name}"'), reason: path);
      expect(source, contains('"${channel.eventChannel.name}"'), reason: path);
    }
  });
}
