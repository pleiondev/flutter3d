/// The id stage, which no hardware backend had ever been asked to draw.
///
/// `Renderer.pickPixel` draws every visible mesh again through `ObjectId`, reads
/// one pixel of an RGBA8 target back and decodes `r + g·256 + b·65536`. That
/// round trip is exercised on the software rasteriser and nowhere else, and the
/// two things it depends on are exactly the two a hardware backend can get
/// wrong quietly: the standard five-attribute vertex layout — which no other
/// check in this suite draws through — and a `FrameInfo` and an `IdInfo` block
/// packed the way the compiled stage expects them.
///
/// A wrong answer here is not a wrong picture. It is a click that selects the
/// object next to the one under the cursor, or nothing at all, on a device
/// nobody was picking on.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 8;

/// One draw through `MeshVertex`/`ObjectId` carrying a known id decodes back to
/// that id.
///
/// The id is 197121 — `0x030201`, one byte per channel and each of them
/// different, so a backend that transposed two channels or dropped one is a
/// different number rather than a near miss. It is written into `IdInfo.id` as
/// thirds of 255 the way `renderer_pick_pass.dart` writes it, and read back
/// through the same arithmetic the renderer decodes with.
///
/// `IdInfo.mask.x` is negative: the material is not masked, so the stage does
/// not sample. The texture is bound anyway, because the stage declares the
/// sampler and a declared sampler with nothing in it is undefined on one
/// backend and a dropped draw on another — which is the rule the renderer's own
/// call site keeps and the reason it is worth keeping here.
///
/// **The five-attribute layout is half of what is being asked.** `MeshVertex`
/// reads position, normal, texcoord, tangent and colour in that order, 64 bytes
/// a vertex, and every other draw in this suite goes through the debug-line or
/// particle stages instead. A backend whose attribute offsets disagree with
/// that declaration reads the tangent as the position and draws nothing where
/// the triangle was — which this reports as the clear colour, id zero.
///
/// Mutations watched go red:
///
///  * the decode below, `+ green * 256` changed to `+ green` — the check
///    reports 196611 against 197121;
///  * `ObjectIdShader` in `cpu_shaders_debug.dart`, returning
///    `Vector4(id.x, id.z, id.y, 1)` — the check reports 131841 and names the
///    two channels that swapped.
Future<void> checkObjectIdDrawsAndDecodes(GraphicsDevice device) async {
  final vertex = device.shaders['MeshVertex'];
  final fragment = device.shaders['ObjectId'];
  require(
    vertex != null && fragment != null,
    'the MeshVertex or ObjectId stages are missing, so picking by pixel cannot '
    'be asked about at all',
  );

  const id = 1 + 2 * 256 + 3 * 65536;

  final white = ByteData(4)
    ..setUint8(0, 255)
    ..setUint8(1, 255)
    ..setUint8(2, 255)
    ..setUint8(3, 255);
  final albedo = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: white,
  );
  require(albedo != null, 'a one-pixel texture for the id stage was refused');

  final target = device.createTexture(
    const RenderTargetSpec(
      width: _size,
      height: _size,
      // Eight bits a channel and no more, which is what makes the encoding
      // exact: the renderer's decode is only right because a byte in is a byte
      // out.
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );

  final identity = Float32List.fromList(Matrix4.identity().storage);
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          // Zero is the id nothing has, exactly as the pick pass clears it.
          clearValue: Vector4.zero(),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    // No depth attachment, so no depth test — and the id stage never blends.
    ..setBlend(null)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'FrameInfo', <String, Float32List>{
      'mvp': identity,
      'model': identity,
      'normal_matrix': identity,
    })
    ..bindUniformBlock(fragment, 'IdInfo', <String, Float32List>{
      'id': Float32List.fromList(<double>[
        (id & 0xFF) / 255.0,
        ((id >> 8) & 0xFF) / 255.0,
        ((id >> 16) & 0xFF) / 255.0,
        1.0,
      ]),
      // Negative cutoff: not a masked material, so nothing is discarded.
      'mask': Float32List.fromList(<double>[-1.0, 1.0, 0.0, 0.0]),
    })
    ..bindTexture(fragment, 'base_color_texture', albedo!)
    ..bindVertexData(ByteData.sublistView(_fullFrameTriangle), 3)
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
      IndexType.int16,
      3,
    )
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  require(read != null, 'the id target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  final (red, green, blue) = (bytes[at], bytes[at + 1], bytes[at + 2]);
  final decoded = red + green * 256 + blue * 65536;

  require(
    decoded == id,
    'the id stage drew $decoded where $id was bound — the centre pixel came '
    'back ($red, $green, $blue) against the (1, 2, 3) that were written into '
    'IdInfo.id. Zero means the triangle never landed, which on this stage is '
    'the standard vertex layout or the FrameInfo block disagreeing with what '
    'MeshVertex declares; any other number is the three id bytes arriving in a '
    'different order or a channel of them being lost.',
  );
}

/// A triangle covering the frame in the layout `MeshVertex` declares: position,
/// normal, texcoord, tangent, colour — sixteen floats a vertex.
///
/// Written out rather than built, because the point of the check is that this
/// exact shape is what the stage reads. Opaque white vertex colour, because the
/// masked path multiplies by its alpha and a zero there would discard every
/// fragment on a backend that took the masked branch when it should not.
final Float32List _fullFrameTriangle = Float32List.fromList(<double>[
  // position       normal      texcoord   tangent          colour
  -1, -1, 0.5, /**/ 0, 0, 1, /**/ 0, 0, /**/ 1, 0, 0, 1, /**/ 1, 1, 1, 1,
  3, -1, 0.5, /* */ 0, 0, 1, /**/ 2, 0, /**/ 1, 0, 0, 1, /**/ 1, 1, 1, 1,
  -1, 3, 0.5, /* */ 0, 0, 1, /**/ 0, 2, /**/ 1, 0, 0, 1, /**/ 1, 1, 1, 1,
]);
