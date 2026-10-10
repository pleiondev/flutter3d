/// The registries plugin elements fill: the event kinds they publish and
/// the switches they answer to, each claimed once and given back with the
/// plugin.
///
///     dart test test/registries_test.dart
library;

import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

/// A plugin's scope, by id.
final class _Scope extends PluginScope {
  _Scope(String id)
    : manifest = PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  final PluginManifest manifest;

  @override
  int get rank => 0;

  final List<Registration> tracked = <Registration>[];

  @override
  void track(Registration registration) => tracked.add(registration);
}

void main() {
  group('ElementEventKinds', () {
    test('holds the core\'s kinds and refuses a plugin into them', () {
      final kinds = ElementEventKinds();
      expect(kinds.ownerOf(NativeEventKind.ignited), 'core');
      // Mutation: drop the `isPlugin` check in `_add` — a plugin then claims
      // a code the core will raise for something else.
      expect(
        () => kinds.add(NativeEventKind.of(42)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('refuses a second claim on a code or a name, naming both', () {
      final kinds = ElementEventKinds();
      kinds
          .forPlugin(_Scope('frost'))
          .add(const NativeEventKind.plugin(0x10001, 'frost.frozen'));
      // Mutation: compare names only in `_add` — the second claim on the
      // code goes through and one code means two things.
      expect(
        () => kinds
            .forPlugin(_Scope('gust'))
            .add(const NativeEventKind.plugin(0x10001, 'gust.toppled')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('frost'), contains('gust')),
          ),
        ),
      );
      expect(
        () => kinds.add(const NativeEventKind.plugin(0x10002, 'frost.frozen')),
        throwsA(isA<ArgumentError>()),
      );
      expect(kinds.of(0x10001).name, 'frost.frozen');
    });

    test('a plugin\'s kinds go when its registration is cancelled', () {
      final kinds = ElementEventKinds();
      final scope = _Scope('frost');
      kinds
          .forPlugin(scope)
          .add(const NativeEventKind.plugin(0x10001, 'frost.frozen'));
      // Mutation: forget `scope?.track` — switching the plugin off leaves
      // its kind claimed, and switching it on again throws.
      expect(scope.tracked, hasLength(1));
      scope.tracked.single.cancel();
      expect(kinds.named('frost.frozen'), isNull);
    });
  });

  group('ElementSwitches', () {
    test('refuses one id twice and fills in the defaults', () {
      final switches = ElementSwitches()
        ..declare(const ElementSwitch('frost', onByDefault: false));
      // Mutation: drop the duplicate check — two elements share a switch
      // and turning one off hides the other.
      expect(
        () => switches.declare(const ElementSwitch('frost')),
        throwsA(isA<ArgumentError>()),
      );
      final steps = switches.defaults(ElementsSteps.all);
      expect(steps.elements['frost'], isFalse);
      expect(steps.isOn('frost'), isFalse);
    });
  });
}
