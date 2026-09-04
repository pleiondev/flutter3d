/// A format the engine does not ship, read by a decoder the application brings.
///
///     flutter test test/model_decoder_test.dart
///
/// **The plugin boundary for reading.** The engine knows glTF, OBJ and its own
/// container; anything else used to mean editing this package. One interface
/// and a list on the request is the whole of what that took.
///
/// The awkward part is not the interface — it is *where the list lives*, and
/// this file pins that too. Decoding runs on a background isolate, and statics
/// are not shared across isolates in Dart: the obvious design, a registry filled
/// at startup, is empty by the time the reading happens. It would pass a test
/// that decoded on the main isolate and fail in the application.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The smallest thing that answers [ModelDocument]: a name and nothing to draw.
///
/// Three getters are abstract — surfaces, materials, images — and the rest of
/// the class derives from them. An empty document is a legitimate one: a decoder
/// that reads a file describing no geometry has read it correctly.
final class _NamedDocument extends ModelDocument {
  const _NamedDocument(this.label);

  final String label;

  @override
  List<ModelSurface> get surfaces => const <ModelSurface>[];

  @override
  List<SurfaceMaterial> get materials => const <SurfaceMaterial>[];

  @override
  List<EncodedImage> get images => const <EncodedImage>[];

  @override
  List<ModelNode> get nodes => <ModelNode>[ModelNode(name: label)];

  /// Nothing went wrong reading a file with nothing in it.
  @override
  List<String> get warnings => const <String>[];
}

/// A format invented for this test: the four bytes `TOY!`, then nothing.
///
/// Deliberately not a real format. What is being checked is that the engine
/// hands the file over and takes back a document, not that anybody can parse
/// anything.
final class _ToyDecoder implements ModelDecoder {
  const _ToyDecoder();

  static bool isToy(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x54 &&
      bytes[1] == 0x4F &&
      bytes[2] == 0x59 &&
      bytes[3] == 0x21;

  @override
  bool handles(String fileName, Uint8List bytes) =>
      fileName.endsWith('.toy') || isToy(bytes);

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async => const _NamedDocument('toy');
}

/// Claims everything, so it can be shown to win against a built-in format.
final class _GreedyDecoder implements ModelDecoder {
  const _GreedyDecoder();

  @override
  bool handles(String fileName, Uint8List bytes) => true;

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async => const _NamedDocument('greedy');
}

/// No siblings: this format has none, and asking for one is a test bug.
Future<Uint8List> _noSiblings(AssetRequest request) async =>
    throw StateError('nothing here asks for a sibling file, but ${request.uri} was');

Uint8List _toyBytes() => Uint8List.fromList(<int>[0x54, 0x4F, 0x59, 0x21]);

void main() {
  group('a decoder an application brings', () {
    test('reads a format the engine never heard of', () async {
      // Mutation: drop the decoder loop from `decodeModelBytes` — the file falls
      // through to the sniffer, which does not know `TOY!`, and the decode
      // fails instead of producing a node.
      final document = await decodeModelBytes(
        ModelLoadRequest(
          source: const BundleAssetSource('toys/duck.toy'),
          decoders: const <ModelDecoder>[_ToyDecoder()],
        ),
        _toyBytes(),
        _noSiblings,
      );

      expect(document.nodes, hasLength(1));
      expect(document.nodes.single.name, 'toy');
    });

    test('and is asked before the suffix table', () async {
      // The file is named `.glb` and is not one. A decoder that recognises its
      // own bytes is a better authority than a table this package wrote, so it
      // is asked first — otherwise a format sharing a suffix with a built-in
      // could never be added at all.
      //
      // Mutation: resolve the format before consulting the decoders — the glTF
      // reader is handed four bytes of nonsense and this fails.
      final document = await decodeModelBytes(
        ModelLoadRequest(
          source: const BundleAssetSource('models/duck.glb'),
          decoders: const <ModelDecoder>[_ToyDecoder()],
        ),
        _toyBytes(),
        _noSiblings,
      );

      expect(document.nodes.single.name, 'toy');
    });

    test('and can replace a format the engine does ship', () async {
      // Adding is the common case; replacing is the one worth allowing. A
      // project with its own glTF reader should get its own glTF reader.
      //
      // Mutation: consult the built-ins first — the engine's reader wins and
      // this fails.
      final document = await decodeModelBytes(
        ModelLoadRequest(
          source: const BundleAssetSource('models/duck.glb'),
          decoders: const <ModelDecoder>[_GreedyDecoder()],
        ),
        _toyBytes(),
        _noSiblings,
      );

      expect(document.nodes.single.name, 'greedy');
    });

    test('and the first that wants the file gets it', () async {
      // Order is the application's to decide, so it has to be respected rather
      // than sorted. Mutation: iterate the list backwards — `greedy` wins and
      // this fails.
      final document = await decodeModelBytes(
        ModelLoadRequest(
          source: const BundleAssetSource('toys/duck.toy'),
          decoders: const <ModelDecoder>[_ToyDecoder(), _GreedyDecoder()],
        ),
        _toyBytes(),
        _noSiblings,
      );

      expect(document.nodes.single.name, 'toy');
    });

    test('and a request with none behaves as it always did', () async {
      // The promise everything else rests on: an empty list changes nothing.
      // Mutation: make the loop run once with a default decoder — every model
      // in the repository loads differently and this fails first.
      expect(
        const ModelLoadRequest(source: BundleAssetSource('a.glb')).decoders,
        isEmpty,
      );
    });
  });
}
