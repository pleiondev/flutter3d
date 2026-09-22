/// A decoder of your own, tried before every format this engine ships.
///
/// Quoted by `custom_decoder.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

// #region decoder
/// A made-up format this engine has never heard of: one line, three
/// numbers, a box of that size. `ModelDecoder` is the whole plugin
/// boundary — a project's own studio format arrives exactly this way.
final class _BoxTextDecoder implements ModelDecoder {
  const _BoxTextDecoder();

  @override
  bool handles(String fileName, Uint8List bytes) =>
      fileName.toLowerCase().endsWith('.box');

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async {
    final parts = utf8.decode(bytes).trim().split(RegExp(r'\s+'));
    if (parts.length != 3) {
      throw const FormatException('a .box file is three numbers: w h d');
    }
    final size = Vector3(
      double.parse(parts[0]),
      double.parse(parts[1]),
      double.parse(parts[2]),
    );
    return PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(mesh: CuboidShape(size: size).build()),
      ],
      nodes: <ModelNode>[
        ModelNode(surfaces: <int>[0]),
      ],
    );
  }
}
// #endregion decoder

final class _BytesSource extends AssetSource {
  const _BytesSource(this._bytes, this._fileName);

  final Uint8List _bytes;
  final String _fileName;

  @override
  String get key => 'bytes:$_fileName';

  @override
  String get fileName => _fileName;

  @override
  Future<Uint8List> read() async => _bytes;

  @override
  AssetUriResolver get resolveUri =>
      (request) async => throw StateError('a .box file has no siblings');
}

final class CustomDecoderDemo extends ShowcaseDemo {
  late final ModelDocument _decoded;

  @override
  Future<void> prepare(DemoContext context) async {
    // #region request
    // A byte-identical file this engine's own decoders would refuse:
    // three plain numbers, no glTF, no OBJ header, nothing recognisable.
    final bytes = Uint8List.fromList(utf8.encode('1.4 0.6 2.0'));
    final request = ModelLoadRequest(
      source: _BytesSource(bytes, 'crate.box'),
      decoders: const <ModelDecoder>[_BoxTextDecoder()],
    );
    // #endregion request

    // #region decode
    // An application's own decoders are tried before this package's
    // built-in ones, by file name and by magic — so a project can also
    // replace a built-in reader, not only add to it.
    _decoded = await decodeModelBytes(
      request,
      bytes,
      request.source.resolveUri,
    );
    // #endregion decode
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, _decoded.surfaces.single.mesh),
        Material(baseColor: Vector4(0.7, 0.55, 0.35, 1.0), roughness: 0.7),
        name: 'crate',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_decoded.surfaces.length != 1) {
      throw StateError('the custom decoder did not produce one surface');
    }
    final bounds = _decoded.computeBounds();
    final width = bounds.max.x - bounds.min.x;
    if ((width - 1.4).abs() > 1e-6) {
      throw StateError('the box did not come out the size the file named');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the crate was not drawn');
    }
    // #endregion check
  }
}
