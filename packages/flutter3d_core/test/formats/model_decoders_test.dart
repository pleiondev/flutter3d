/// The `DecoderRegistry` the formats fill: a request's own decoders first,
/// then the registered ones in install order; a plugin's withdrawn with it;
/// and a path's scheme naming the source it is read through.
///
///     dart test test/formats/model_decoders_test.dart
///
/// Against a scope that keeps its registrations, so switching a plugin off
/// is cancelling what it tracked — what the plugin host does. Each test was
/// written by breaking what it covers; the mutation is named.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

/// A decoder that answers for every file and says who it is.
final class _Named extends ModelDecoder {
  const _Named(this.name);

  final String name;

  @override
  bool handles(String fileName, Uint8List bytes) => true;

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async => PlainModelDocument(warnings: <String>[name]);

  @override
  String toString() => name;
}

/// A source that holds its path and nothing else.
final class _Source extends AssetSource {
  const _Source(this.from, this.path);

  final String from;
  final String path;

  @override
  String get key => '$from:$path';

  @override
  Future<Uint8List> read() async => Uint8List(0);

  @override
  AssetUriResolver get resolveUri =>
      (AssetRequest request) async => Uint8List(0);
}

/// A plugin as the host sees it: an id, a place in the install order, and
/// the registrations to cancel when it goes.
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

  void switchOff() {
    for (final registration in tracked.reversed) {
      registration.cancel();
    }
  }
}

void main() {
  test('a request keeps its own decoders first; the registered follow, the '
      'application\'s, then each plugin\'s in install order', () {
    final decoders = ModelDecoders();
    final late = _Scope('late', 1);
    final early = _Scope('early', 0);
    // Registered out of install order, so the order read back is the
    // ranks' and not the calls'.
    decoders.forPlugin(late).addModelDecoder(const _Named('late'));
    decoders.forPlugin(early).addModelDecoder(const _Named('early'));
    decoders.addModelDecoder(const _Named('app'));

    final request = decoders.withDecoders(
      const ModelLoadRequest(
        source: _Source('file', 'crate.glb'),
        decoders: <ModelDecoder>[_Named('own')],
      ),
    );

    // Mutation: put the registered decoders before the request's own. A
    // loader that passed its own reader would find a plugin's answering
    // first, and the per-request list would stop meaning anything.
    // Mutation: sort by sequence alone. "late" would precede "early".
    expect(request.decoders.map((d) => d.toString()), <String>[
      'own',
      'app',
      'early',
      'late',
    ]);
    expect(request.source.key, 'file:crate.glb');
  });

  test(
    'switching a plugin off takes out what it registered, and only that',
    () {
      final decoders = ModelDecoders();
      final ply = _Scope('ply', 0);
      final pak = _Scope('pak', 1);
      decoders.forPlugin(ply).addModelDecoder(const _Named('ply'));
      decoders.forPlugin(pak)
        ..addModelDecoder(const _Named('pak'))
        ..addSource('pak', (String path) => _Source('pak', path));

      pak.switchOff();

      // Mutation: hand the scope nothing to track. The registrations would
      // outlive the plugin, and a switched-off format would still be read.
      expect(decoders.decoders.map((d) => d.toString()), <String>['ply']);
      expect(decoders.sources.schemes, isEmpty);
    },
  );

  test('a scheme taken twice is refused, naming who holds it', () {
    final decoders = ModelDecoders();
    decoders.forPlugin(_Scope('pak', 0)).addSource('pak', _pak);

    // Mutation: let the second replace the first. Which archive a path
    // read from would depend on the install order, silently.
    expect(
      () => decoders.forPlugin(_Scope('other', 1)).addSource('pak', _pak),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('plugin "pak"'),
        ),
      ),
    );
    expect(() => decoders.addSource('C', _pak), throwsArgumentError);
  });

  test('a path with a registered scheme goes to its source without the '
      'scheme; any other goes to the fallback whole', () {
    final sources = AssetSources(<String, AssetSourceFactory>{'pak': _pak});
    AssetSource fallback(String path) => _Source('bundle', path);

    // Mutation: hand the factory the whole path. An archive would look for
    // "pak:models/crate.glb" inside itself.
    expect(
      sources.resolve('pak:models/crate.glb', fallback: fallback).key,
      'pak:models/crate.glb',
    );
    expect(
      (sources.resolve('pak:models/crate.glb', fallback: fallback) as _Source)
          .path,
      'models/crate.glb',
    );
    // Mutation: throw for a scheme nobody registered. `https:` would stop
    // reaching a fallback that knows it.
    expect(
      sources.resolve('https://example.org/a.glb', fallback: fallback).key,
      'bundle:https://example.org/a.glb',
    );
    // Mutation: let one letter be a scheme. A Windows path would be read as
    // a source called "c".
    expect(AssetSources.schemeOf(r'C:\models\a.glb'), isNull);
    expect(AssetSources.schemeOf('models/a.glb'), isNull);
    expect(sources.handles('pak:a.glb'), isTrue);
    expect(sources.handles('zip:a.glb'), isFalse);
  });
}

AssetSource _pak(String path) => _Source('pak', path);
