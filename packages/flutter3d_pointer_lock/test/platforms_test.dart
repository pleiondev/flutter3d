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
import 'package:flutter/services.dart';
import 'package:flutter3d_pointer_lock/flutter3d_pointer_lock.dart';
import 'package:flutter3d_pointer_lock/src/pointer_lock_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a desktop always answers yes, and a platform with no native side '
      'answers no', () {
    // The list that has to change the day another platform is written, which
    // is the point: a table nobody updates is one that goes stale.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const desktops = <TargetPlatform>{
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    };
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        MethodChannelPointerLock().isSupported,
        desktops.contains(platform),
        reason: '$platform, before any native side has spoken',
      );
    }
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    group('$platform follows the mouse the native side reports', () {
      late MethodChannelPointerLock channel;
      late List<String> calls;

      setUp(() {
        debugDefaultTargetPlatformOverride = platform;
        channel = MethodChannelPointerLock();
        calls = <String>[];
        // The event channel's own method channel: `listen` and `cancel`.
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel(channel.eventChannel.name),
              (MethodCall call) async {
                calls.add(call.method);
                return null;
              },
            );
      });

      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel(channel.eventChannel.name),
              null,
            );
      });

      Future<void> send(Object? event) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.eventChannel.name,
              const StandardMethodCodec().encodeSuccessEnvelope(event),
              (ByteData? _) {},
            );
        await Future<void>.delayed(Duration.zero);
      }

      test('no until a mouse is reported, yes while one is, no after it '
          'leaves', () async {
        final changes = <bool>[];
        final subscription = channel.supportChanges.listen(changes.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);

        expect(calls, contains('listen'), reason: 'nothing subscribed');
        expect(channel.isSupported, isFalse);

        await send(true);
        expect(channel.isSupported, isTrue);

        // A repeated answer is not a change.
        await send(true);
        await send(false);
        expect(channel.isSupported, isFalse);
        expect(changes, <bool>[true, false]);
      });

      test('the mouse is followed with nobody listening for the change, '
          'because capture state is listened to anyway', () async {
        final states = <CaptureState>[];
        final deltas = <Offset>[];
        final stateSubscription = channel.stateChanges.listen(states.add);
        final deltaSubscription = channel.deltas.listen(deltas.add);
        addTearDown(stateSubscription.cancel);
        addTearDown(deltaSubscription.cancel);
        await Future<void>.delayed(Duration.zero);

        await send(true);
        await send(1);
        await send(Float64List.fromList(<double>[2.5, -1]));
        await send(0);

        expect(channel.isSupported, isTrue);
        expect(states, <CaptureState>[
          CaptureState.captured,
          CaptureState.released,
        ]);
        expect(deltas, <Offset>[const Offset(2.5, -1)]);
      });

      test('a PointerLock above it announces the change', () async {
        final lock = PointerLock(platform: channel);
        addTearDown(lock.dispose);
        final changes = <bool>[];
        final subscription = lock.onSupportChanged.listen(changes.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);

        expect(lock.isSupported, isFalse);
        await send(true);
        expect(lock.isSupported, isTrue);
        expect(changes, <bool>[true]);
      });
    });
  }

  test('every platform the package declares has an implementation', () {
    // pub.dev reads the top-level `platforms:`; Flutter reads
    // `flutter: plugin: platforms:`. The two have to name the same native
    // platforms, each with a class some source declares, and the web is the
    // one left to the conditional export.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^platforms:\n((?:  \w+:\n)+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(
      RegExp(
        r'^  (\w+):$',
        multiLine: true,
      ).allMatches(declared).map((Match match) => match.group(1)).toSet(),
      <String>{'android', 'ios', 'linux', 'macos', 'web', 'windows'},
    );
    final plugin = pubspec.substring(pubspec.indexOf('\nflutter:\n'));
    for (final native in <String>[
      'android',
      'ios',
      'linux',
      'macos',
      'windows',
    ]) {
      expect(
        RegExp(
          '^      $native:\\n(?:\\s*#.*\\n)*        \\w*'
          '(?:pluginClass|package): ',
          multiLine: true,
        ).hasMatch(plugin),
        isTrue,
        reason: '$native has no plugin entry',
      );
    }
    expect(plugin, isNot(contains('\n      web:')));
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
    const iosSwift =
        'ios/flutter3d_pointer_lock/Sources/flutter3d_pointer_lock/'
        'Flutter3dPointerLockPlugin.swift';
    const kotlin =
        'android/src/main/kotlin/dev/flutter3d/flutter3d_pointer_lock/'
        'Flutter3dPointerLockPlugin.kt';
    final sides = <String, (String, String)>{
      swift: ('Flutter3dPointerLockPlugin', 'class Flutter3dPointerLockPlugin'),
      iosSwift: (
        'Flutter3dPointerLockPlugin',
        'class Flutter3dPointerLockPlugin',
      ),
      kotlin: (
        'Flutter3dPointerLockPlugin',
        'class Flutter3dPointerLockPlugin',
      ),
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
      iosSwift,
      kotlin,
      'windows/flutter3d_pointer_lock_plugin.cpp',
      'linux/flutter3d_pointer_lock_plugin.cc',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('"${channel.methodChannel.name}"'), reason: path);
      expect(source, contains('"${channel.eventChannel.name}"'), reason: path);
    }
  });

  test('a native side without the method answers nothing', () async {
    // No handler is registered on the channel, which is what a native side
    // that predates a method looks like: `invokeMethod` raises
    // `MissingPluginException`, and every call has to answer instead.
    // Mutation: drop the catch in `_call`, and these throw.
    final channel = MethodChannelPointerLock();
    await expectLater(channel.capture(), completes);
    await expectLater(channel.release(), completes);
    await expectLater(channel.reset(), completes);
  });
}
