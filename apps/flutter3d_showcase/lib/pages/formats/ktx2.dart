/// Reading a KTX2 container that carries Basis Universal ETC1S pixels.
///
/// Quoted by `ktx2.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Ktx2Texture;
// The engine's own `Ktx2Texture` (from `flutter3d/flutter3d.dart`) answers
// a `TextureFormat`, already resolved against a device. This page reads
// the container itself, which answers the file's own `vkFormat`.
import 'package:flutter3d_core/formats.dart' show Ktx2Texture, VkFormat;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class Ktx2Demo extends ShowcaseDemo {
  late final Ktx2Texture _texture;

  @override
  Future<void> prepare(DemoContext context) async {
    // #region parse
    // This file's pixels are Basis Universal, ETC1S under Basis-LZ: KTX2
    // says so by leaving `vkFormat` undefined and naming the codebooks in
    // its own data format descriptor. `Ktx2Texture.parse` transcodes them
    // to plain RGBA8 rather than handing back a block format nothing
    // asked the device about yet.
    const source = BundleAssetSource(
      'packages/flutter3d_samples/assets/ktx2/etc1s_field_mips.ktx2',
    );
    final bytes = await source.read();
    _texture = Ktx2Texture.parse(bytes);
    // #endregion parse
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          context.device,
          SphereShape(segments: 24, rings: 12).build(),
        ),
        Material(baseColor: Vector4(0.6, 0.6, 0.65, 1.0), roughness: 0.7),
        name: 'ball',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  // #region report
  String _report() =>
      'size: ${_texture.pixelWidth} x ${_texture.pixelHeight}\n'
      'vkFormat: ${_texture.vkFormat} '
      '(${_texture.vkFormat == VkFormat.r8g8b8a8UNorm ? 'RGBA8, transcoded' : 'raw block format'})\n'
      'mip levels: ${_texture.levels.length}\n'
      'level 0 bytes: ${_texture.levels.first.lengthInBytes}';
  // #endregion report

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFE8E8EC),
            fontSize: 16,
            fontFamily: 'monospace',
          ),
          child: Text(_report()),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_texture.vkFormat != VkFormat.r8g8b8a8UNorm) {
      throw StateError('a Basis file should transcode to plain RGBA8');
    }
    if (_texture.levels.length < 2) {
      throw StateError('this file is named for its mip chain and has none');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
