/// `Decoders`: the `DecoderRegistry` with material decoders beside the model
/// ones — found under either type, a call's own decoders first, and a
/// plugin's withdrawn with it.
///
///     flutter test test/decoders_test.dart
///
/// No device and no file: what is under test is the registry. Each test was
/// written by breaking what it covers; the mutation is named.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginManifest, PluginScope, Registration;
import 'package:flutter_test/flutter_test.dart';

final class _Named extends MaterialDecoder {
  const _Named(this.name);

  final String name;

  @override
  bool handles(String fileName, Uint8List bytes) => true;

  @override
  MaterialDocument decode(Uint8List bytes, String fileName) =>
      MaterialDocument(surface: SurfaceMaterial(name: name));

  @override
  String toString() => name;
}

final class _Scope extends PluginScope {
  _Scope(String id, this.rank)
    : manifest = PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  final PluginManifest manifest;

  @override
  final int rank;

  final List<Registration> tracked = <Registration>[];

  @override
  void track(Registration registration) => tracked.add(registration);
}

void main() {
  test('a call\'s own material decoders come first, then the registered in '
      'install order', () {
    final decoders = Decoders();
    decoders
        .forPlugin(_Scope('late', 1))
        .addMaterialDecoder(const _Named('late'));
    decoders
        .forPlugin(_Scope('early', 0))
        .addMaterialDecoder(const _Named('early'));

    // Mutation: append the call's own after the registered. A loader that
    // passes its own `.fmat` reader would have a plugin's answer first.
    expect(
      decoders
          .withMaterialDecoders(const <MaterialDecoder>[_Named('own')])
          .map((d) => d.toString()),
      <String>['own', 'early', 'late'],
    );
  });

  test('a plugin\'s view is a Decoders, so it is found as either type, and '
      'what it adds goes when it is switched off', () {
    final decoders = Decoders();
    final scope = _Scope('studio', 0);

    // Mutation: drop the `forPlugin` override. The view would be a plain
    // ModelDecoders, and `host.registry<Decoders>()` would refuse it.
    final view = decoders.forPlugin(scope);
    expect(view, isA<Decoders>());
    view.addMaterialDecoder(const _Named('studio'));
    expect(decoders.materialDecoders, hasLength(1));

    // Mutation: forget to track. The decoder would outlive its plugin.
    for (final registration in scope.tracked) {
      registration.cancel();
    }
    expect(decoders.materialDecoders, isEmpty);
  });
}
