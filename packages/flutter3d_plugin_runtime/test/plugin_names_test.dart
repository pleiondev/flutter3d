/// The names a plugin registers with the run-time registries are in its
/// namespace (D23): a data plugin's section and a world field.
///
///     dart test test/plugin_names_test.dart
///
/// Mutation: drop the `nameProblem` call from `DataSections` or
/// `WorldFields.add`, and two outside plugins that both register `heat`
/// meet: the second is refused for the first's name, or reads its rows.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

final class _Plugin extends Flutter3dPlugin {
  _Plugin(this.id, this.registers);

  final String id;
  final void Function(PluginHost host) registers;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) => registers(host);
}

final class _Section extends DataSection {
  const _Section(this.name);

  @override
  final String name;

  @override
  Object read(Object? written, DataSectionContext context) => written ?? 0;

  @override
  Object? write(Object section) => section;

  @override
  void install(PluginHost host, Object section, DataSectionContext context) {}
}

void _install(String id, void Function(PluginHost host) registers) {
  EngineLoop(
    input: InputState(),
    registries: <PluginRegistry>[DataSections(), WorldFields()],
    plugins: <Flutter3dPlugin>[_Plugin(id, registers)],
  );
}

final Map<String, void Function(PluginHost host, String name)> _registries =
    <String, void Function(PluginHost host, String name)>{
      'a data section': (host, name) =>
          host.registry<DataSectionRegistry>().register(_Section(name)),
      'a world field': (host, name) => host.registry<WorldFields>().add(
        ListWorldField(name, Float64List(4)),
      ),
    };

void main() {
  for (final MapEntry(key: what, value: register) in _registries.entries) {
    group(what, () {
      test('is refused outside the plugin\'s namespace, by name', () {
        expect(
          () => _install('acme', (h) => register(h, 'heat')),
          throwsA(
            isA<PluginException>().having(
              (e) => e.message,
              'message',
              allOf(contains('"heat"'), contains('acme.<name>')),
            ),
          ),
        );
      });

      test('is taken in the plugin\'s namespace', () {
        expect(
          () => _install('acme', (h) => register(h, 'acme.heat')),
          returnsNormally,
        );
      });

      test('is taken bare from one of the engine\'s own packages', () {
        expect(
          () => _install('flutter3d_elements', (h) => register(h, 'heat')),
          returnsNormally,
        );
      });
    });
  }

  test('the application names its world fields as it likes', () {
    expect(
      () => WorldFields(<WorldField>[ListWorldField('heat', Float64List(4))]),
      returnsNormally,
    );
  });
}
