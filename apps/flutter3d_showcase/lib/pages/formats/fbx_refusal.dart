/// An FBX file, recognised and refused with a reason.
///
/// Quoted by `fbx_refusal.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class _BytesSource extends AssetSource {
  const _BytesSource(this._bytes);

  final Uint8List _bytes;

  @override
  String get key => 'bytes:mystery.fbx';

  @override
  Future<Uint8List> read() async => _bytes;

  @override
  AssetUriResolver get resolveUri =>
      (request) async => throw StateError('this fixture has no siblings');
}

final class FbxRefusalDemo extends ShowcaseDemo {
  late final bool _recognised;
  late final String _refusalMessage;

  // #region magic
  // The first bytes of every binary FBX file ever written: the string
  // "Kaydara FBX Binary  ", two NUL bytes, then a version this page never
  // reaches, since the decoder refuses before reading that far.
  static final Uint8List _bytes = Uint8List.fromList(<int>[
    ...utf8.encode('Kaydara FBX Binary  '),
    0x00,
    0x1a,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  // #endregion magic

  @override
  Future<void> prepare(DemoContext context) async {
    // #region handles
    const decoder = FbxDecoder();
    _recognised = decoder.handles('mystery.fbx', _bytes);
    // #endregion handles

    // #region refuse
    final request = ModelLoadRequest(source: _BytesSource(_bytes));
    try {
      await decoder.decode(_bytes, request, request.source.resolveUri);
      _refusalMessage = '(did not refuse)';
    } on FormatException catch (error) {
      _refusalMessage = error.message;
    }
    // #endregion refuse
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, CuboidShape().build()),
        Material(baseColor: Vector4(0.6, 0.6, 0.6, 1.0)),
        name: 'block',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(
            'recognised as FBX by its magic: $_recognised\n\n'
            'refused with: $_refusalMessage',
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_recognised) {
      throw StateError('the decoder did not recognise its own magic');
    }
    if (!_refusalMessage.toLowerCase().contains('export')) {
      throw StateError('the refusal should say to export glTF instead');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the block was not drawn');
    }
    // #endregion check
  }
}
