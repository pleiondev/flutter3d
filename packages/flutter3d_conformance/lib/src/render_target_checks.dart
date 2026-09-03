/// A pass aimed at one face and one level of a cube lands there and nowhere
/// else.
///
/// **The check a reflection probe stands on.** A probe is six views drawn
/// into the six faces of a cube and a chain of levels convolved below them,
/// and every one of those is a `ColorTarget` naming a face and a level. Three
/// backends reach that subresource three different ways — Impeller by a
/// slice and a mip index on the attachment, WebGL2 by a face target and a
/// level in `framebufferTexture2D`, the software rasteriser by walking to the
/// array that face and level own — and a backend that got one wrong would not
/// error. It would clear the base level, or the whole cube, or face zero, and
/// the probe would reflect a plausible picture from the wrong direction.
///
/// Verified by sampling rather than by reading a face back, because reading
/// a face is not something the interface offers: the probe's own prefilter
/// stage, told to take one tap along the face's axis at a named level, is a
/// readback of one texel of one face of one level, and it is the very stage
/// the probe fills its chain with.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 8;

Future<void> checkRenderToCubeFaceAndMip(GraphicsDevice device) async {
  if (!device.supportsCubeTextures) return;

  // Two levels where the device will draw into one below the base, one where
  // it will not: a device that answers false is entitled to, and what is
  // checked of it is the face alone.
  final levels = device.supportsRenderToMip ? 2 : 1;
  final cube = device.createCubeRenderTarget(
    size: _size,
    format: TextureFormat.r8g8b8a8UNormInt,
    mipLevels: levels,
  );
  require(
    cube != null,
    'the device says it supports cube textures and then made no cube a pass '
    'could draw into',
  );
  require(
    cube!.type == TextureType.textureCube,
    'the cube came back as ${cube.type.name}',
  );

  // Three clears, each into its own face and level, in an order that makes a
  // backend clearing too much end up with the wrong colour everywhere: green
  // into face three's base, blue into face zero's base, and red into face
  // three's second level last — so a clear that covered every face, or every
  // level, leaves red where green was expected.
  void clear(int face, int mipLevel, Vector4 colour) => device
      .beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: cube,
              face: face,
              mipLevel: mipLevel,
              loadAction: LoadAction.clear,
              clearValue: colour,
            ),
          ],
        ),
      )
      .submit();

  clear(3, 0, Vector4(0.0, 1.0, 0.0, 1.0));
  clear(0, 0, Vector4(0.0, 0.0, 1.0, 1.0));
  if (levels > 1) clear(3, 1, Vector4(1.0, 0.0, 0.0, 1.0));

  final green = await _readFace(device, cube, face: 3, lod: 0);
  require(
    green[1] > 200 && green[0] < 50 && green[2] < 50,
    'face three, base level, came back $green where green was cleared: the '
    'pass did not draw into the face it named, or a later clear covered it',
  );
  final blue = await _readFace(device, cube, face: 0, lod: 0);
  require(
    blue[2] > 200 && blue[0] < 50 && blue[1] < 50,
    'face zero came back $blue where blue was cleared: a clear aimed at one '
    'face reached another',
  );
  if (levels > 1) {
    final red = await _readFace(device, cube, face: 3, lod: 1);
    require(
      red[0] > 200 && red[1] < 50 && red[2] < 50,
      'face three, level one, came back $red where red was cleared: the pass '
      'did not draw into the level it named — supportsRenderToMip says true '
      'and the attachment went to the base',
    );
  }
}

/// One texel at the centre of [face] of [cube] at level [lod], through the
/// probe prefilter stage with a single tap.
Future<List<int>> _readFace(
  GraphicsDevice device,
  TextureHandle cube, {
  required int face,
  required int lod,
}) async {
  const size = 4;
  final vertex = device.shaders['FullscreenVertex'];
  final fragment = device.shaders['ProbePrefilter'];
  require(
    vertex != null && fragment != null,
    'the full-screen and probe prefilter stages are missing, so nothing here '
    'can read a face',
  );

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  // Every vertex carries the face's centre as its uv, so every fragment looks
  // straight down the face's axis and the direction cannot depend on where a
  // backend puts row zero.
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 0.5, //
    3, -1, 0.5, 0.5,
    -1, 3, 0.5, 0.5,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindTexture(
      fragment,
      'capture_texture',
      cube,
      // Linear between levels, which is what lets the level be asked for at
      // all on a backend that folds the mip filter into minification.
      sampler: const SamplerOptions(
        minFilter: MinMagFilter.linear,
        magFilter: MinMagFilter.linear,
        mipFilter: MipFilter.linear,
      ),
    )
    ..bindUniformBlock(fragment, 'ProbeInfo', <String, Float32List>{
      'params': Float32List.fromList(<double>[
        face.toDouble(),
        0.0,
        lod.toDouble(),
        1.0,
      ]),
    })
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final at = ((size ~/ 2) * size + size ~/ 2) * 4;
  return <int>[bytes[at], bytes[at + 1], bytes[at + 2]];
}
