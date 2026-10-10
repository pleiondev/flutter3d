import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

/// A plugin with nothing to install, told apart by its id and, for `set`,
/// by a setting.
final class _Glow extends Flutter3dPlugin {
  _Glow({this.strength = 1});

  final double strength;

  @override
  PluginManifest get manifest =>
      const PluginManifest(id: 'glow', apiVersion: PluginApiVersion(1, 0));

  @override
  void install(PluginHost host) {}
}

final class _Fog extends Flutter3dPlugin {
  @override
  PluginManifest get manifest =>
      const PluginManifest(id: 'fog', apiVersion: PluginApiVersion(1, 0));

  @override
  void install(PluginHost host) {}
}

/// Two plugins of one class with ids of their own, as data plugins are.
final class _Named extends Flutter3dPlugin {
  _Named(this.id);

  final String id;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: const PluginApiVersion(1, 0));

  @override
  void install(PluginHost host) {}
}

List<String> _ids(PluginGroup group) => <String>[
  for (final p in group.plugins) p.manifest.id,
];

void main() {
  test('a group keeps its plugins in order', () {
    final group = PluginGroup(<Flutter3dPlugin>[_Glow(), _Fog()]);
    expect(_ids(group), <String>['glow', 'fog']);
  });

  test('two plugins with one id are refused', () {
    // Mutation: drop the check, and the second `glow` would be installed
    // and refused by the manager later, far from the line that added it.
    expect(
      () => PluginGroup(<Flutter3dPlugin>[_Glow(), _Glow()]),
      throwsArgumentError,
    );
    expect(
      () => PluginGroup(<Flutter3dPlugin>[_Glow()]).add(_Glow()),
      throwsArgumentError,
    );
  });

  test('set replaces the member with the same id, in place', () {
    final group = PluginGroup(<Flutter3dPlugin>[
      _Glow(),
      _Fog(),
    ]).set(_Glow(strength: 3));
    expect(_ids(group), <String>['glow', 'fog']);
    expect((group.plugins.first as _Glow).strength, 3);
  });

  test('set adds a plugin the group does not have, at the end', () {
    // A group that drops a plugin in a minor release must not break the
    // application that configured it.
    final group = PluginGroup(<Flutter3dPlugin>[_Fog()]).set(_Glow());
    expect(_ids(group), <String>['fog', 'glow']);
  });

  test('without removes by type, withoutId by id', () {
    final group = PluginGroup(<Flutter3dPlugin>[
      _Glow(),
      _Fog(),
      _Named('a'),
      _Named('b'),
    ]);
    expect(_ids(group.without<_Fog>()), <String>['glow', 'a', 'b']);
    expect(_ids(group.without<_Named>()), <String>['glow', 'fog']);
    expect(_ids(group.withoutId('a')), <String>['glow', 'fog', 'b']);
    // What the group does not hold is not an error, for the same reason.
    expect(_ids(group.withoutId('nothing')), _ids(group));
  });

  test('every change is a new group, the old one untouched', () {
    final group = PluginGroup(<Flutter3dPlugin>[_Glow()]);
    final more = group.add(_Fog());
    expect(_ids(group), <String>['glow']);
    expect(_ids(more), <String>['glow', 'fog']);
    expect(() => group.plugins.add(_Fog()), throwsUnsupportedError);
  });

  test('a group can be named by a class of its own', () {
    final standard = _Standard();
    expect(_ids(standard.without<_Glow>()), <String>['fog']);
    expect(standard.plugins, hasLength(2));
  });
}

/// What a package's own group looks like: `StandardPlugins` and the rest
/// are written this way.
final class _Standard extends PluginGroup {
  _Standard() : super(<Flutter3dPlugin>[_Glow(), _Fog()]);
}
