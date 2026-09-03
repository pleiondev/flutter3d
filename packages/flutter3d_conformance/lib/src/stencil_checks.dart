/// The stencil test, in the shape the engine uses it.
///
/// A mark written where a mesh is, then two draws that read it back the two
/// ways — `equal` to land only on the mark, `notEqual` to land only off it —
/// which is the x-ray stage reduced to one triangle. The eight operations one
/// by one are the software backend's own test, where the buffer can be read;
/// what a hardware backend can be asked is only what it drew, so this asks
/// for the three answers a picture can give and names which of the three
/// rules each one would have broken.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// A stencil written by one draw decides what the next two draw.
///
/// Three pixels read back, three rules:
///
///  * **top left, green** — the mark was written and `equal` honoured it;
///  * **bottom left, red** — the marking draw, blended with
///    [BlendState.keepDestination], left the clear colour where it marked;
///  * **right, blue** — `notEqual` rejected the mark and passed everywhere
///    else, and the mark stayed inside the scissor that bounded its draw.
Future<void> checkStencilKeepsWhatItShould(GraphicsDevice device) async {
  // Honest, not lenient: a backend that says it has no stencil is asked
  // nothing about one, the way a backend without a compressed format is not
  // asked to sample it. What it is held to instead is drawing no silhouettes,
  // which is the renderer's side of the same answer.
  if (!device.supportsStencil) return;

  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw three times',
  );

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final depth = device.createTexture(
    RenderTargetSpec(
      width: size,
      height: size,
      format: device.defaultDepthStencilFormat,
      // Tile memory, as the scene pass's own attachment is: a stencil that
      // only worked on a texture nobody could read back would be a stencil
      // the engine could not use.
      storageMode: StorageMode.deviceTransient,
    ),
  );
  require(
    depth.format.hasStencil,
    'defaultDepthStencilFormat is ${depth.format.name}, which carries no '
    'stencil, yet supportsStencil answered true',
  );

  Float32List triangle(List<double> colour) => Float32List.fromList(<double>[
    -1, -1, 0.5, ...colour, //
    3, -1, 0.5, ...colour,
    -1, 3, 0.5, ...colour,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);
  final identity = Float32List.fromList(Matrix4.identity().storage);

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4(1.0, 0.0, 0.0, 1.0),
        ),
      ],
      depth: DepthTarget(texture: depth),
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..setDepthCompare(CompareFunction.always)
    ..setDepthWrite(false)
    ..bindPipeline(device.createPipeline(vertex!, fragment!));

  void draw(List<double> colour) {
    pass
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': identity,
      })
      ..bindVertexData(ByteData.sublistView(triangle(colour)), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw();
  }

  // The mark: the left half, in white nobody should see, writing one.
  pass
    ..setScissor(const ScreenRect(width: size ~/ 2, height: size))
    ..setStencilReference(1)
    ..setStencil(
      const StencilState(passOp: StencilOperation.setToReferenceValue),
    )
    ..setBlend(BlendState.keepDestination);
  draw(<double>[1, 1, 1, 1]);

  // On the mark only, and only its top half, so the bottom half still shows
  // what the marking draw left behind.
  pass
    ..setScissor(const ScreenRect(width: size ~/ 2, height: size ~/ 2))
    ..setBlend(null)
    ..setStencil(const StencilState(compare: CompareFunction.equal));
  draw(<double>[0, 1, 0, 1]);

  // Off the mark only, everywhere.
  pass
    ..setScissor(const ScreenRect(width: size, height: size))
    ..setStencil(const StencilState(compare: CompareFunction.notEqual));
  draw(<double>[0, 0, 1, 1]);

  pass
    ..setStencil(StencilState.disabled)
    ..submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  String at(int x, int y) {
    final i = (y * size + x) * 4;
    return 'r=${bytes[i]} g=${bytes[i + 1]} b=${bytes[i + 2]}';
  }

  bool isGreen(int x, int y) {
    final i = (y * size + x) * 4;
    return bytes[i + 1] > 128 && bytes[i] < 128 && bytes[i + 2] < 128;
  }

  bool isRed(int x, int y) {
    final i = (y * size + x) * 4;
    return bytes[i] > 128 && bytes[i + 1] < 128 && bytes[i + 2] < 128;
  }

  bool isBlue(int x, int y) {
    final i = (y * size + x) * 4;
    return bytes[i + 2] > 128 && bytes[i] < 128 && bytes[i + 1] < 128;
  }

  const left = size ~/ 4;
  const right = size * 3 ~/ 4;
  const top = size ~/ 4;
  const bottom = size * 3 ~/ 4;

  require(
    isGreen(left, top),
    'the draw that should land on the mark did not: the top-left came back '
    '${at(left, top)}. Either setToReferenceValue wrote nothing, or `equal` '
    'against a reference of one was not honoured. Red means the mark was '
    'never written; blue means `notEqual` passed where the mark was.',
  );
  require(
    isRed(left, bottom),
    'the marking draw changed the picture: the bottom-left came back '
    '${at(left, bottom)} where the clear colour should have survived. '
    'BlendState.keepDestination — zero from the source, one from the '
    'destination — is how a draw marks the stencil and leaves the colour '
    'alone, and this backend did not honour its factors.',
  );
  require(
    isBlue(right, top) && isBlue(right, bottom),
    'the draw that should land off the mark did not: the right half came '
    'back ${at(right, top)} and ${at(right, bottom)}. Green means `equal` '
    'passed where nothing was written, or the mark leaked past its '
    'scissor; red means `notEqual` failed against a stencil that should '
    'still hold its clear value of zero.',
  );
}
