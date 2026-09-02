import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// The checks a backend can run before it has compiled a single shader.
///
/// **This list is why the two exist separately.** The library used to say it
/// was shader-free as a whole, and it stopped being true the day the third
/// check needed a pipeline — so a new backend, following the promise, would
/// have hit five failures it had no way to act on yet. Clears, uploads and
/// readback only: the answers here are the cheapest ones to get, and they are
/// the ones worth having first.
Future<void> checkCapabilities(GraphicsDevice device) async {
  // Not assertions about the values — a backend is entitled to any of them.
  // Assertions that asking works at all, because the engine branches on these
  // and a throw here is a frame that never starts.
  // Reading them is the assertion: the engine branches on each, and a throw
  // here is a frame that never starts. The values themselves are the backend's
  // business.
  device.depthRange;
  device.framebufferOrigin;
  device.supportsWireframe;
  device.supportsOffscreenMsaa;
  device.supportsRenderToMip;
  // Every format, because the block-compressed tail is where a backend is
  // most tempted to throw from a lookup table instead of answering: a loader
  // asks this before uploading, and a throw here is a texture lost with no
  // reason given.
  for (final format in TextureFormat.values) {
    device.supportsTextureFormat(format);
  }
  require(
    device.supportsTextureFormat(TextureFormat.r8g8b8a8UNormInt),
    'r8g8b8a8UNormInt is not sampled, and every decoded image arrives in it',
  );
  require(
    device.preferredSampleCount >= 1,
    'preferredSampleCount is ${device.preferredSampleCount}; one means no '
    'multisampling and less than one means nothing',
  );
  require(
    device.defaultColorFormat != TextureFormat.unknown,
    'defaultColorFormat is unknown, so the frame has nowhere to go',
  );
}

Future<void> checkHdrRenderable(GraphicsDevice device) async {
  // The engine renders linear HDR and tone maps at the end, so it opens a pass
  // against whatever this getter names. A format that is samplable but not
  // renderable — RGBA16F on WebGL2 before EXT_color_buffer_float is asked for —
  // makes every framebuffer incomplete, every draw silently discarded, and a
  // frame of transparent black with every counter reporting success.
  final target = device.createTexture(
    RenderTargetSpec(width: 32, height: 32, format: device.hdrColorFormat),
  );
  device
      .beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: target,
              loadAction: LoadAction.clear,
              clearValue: Vector4(1.0, 1.0, 1.0, 1.0),
            ),
          ],
        ),
      )
      .submit();
}

Future<void> checkClearCoversAll(GraphicsDevice device) async {
  // The rule the point-light atlas depends on: it clears once and then draws
  // tile by tile, so a clear bounded by the scissor would leave most of it as
  // allocated. GL does not give this for free — clearBufferfv honours
  // SCISSOR_TEST — and the symptom was one cleared row out of four and shadows
  // that read as absent.
  const size = 64;
  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );

  device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: target,
            loadAction: LoadAction.clear,
            clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
          ),
        ],
      ),
    )
    // A scissor over one corner, set before submitting. A backend that clears
    // through it fails here and only here.
    ..setScissor(const ScreenRect(x: 0, y: 0, width: 8, height: 8))
    ..submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the cleared target could not be read back');
  final bytes = pixels!.buffer.asUint8List();

  // Every pixel, not a sample: a partial clear leaves a rectangle, and a spot
  // check placed inside it would pass.
  var wrong = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    if (bytes[i + 1] < 200) wrong++;
  }
  require(
    wrong == 0,
    '$wrong of ${bytes.length ~/ 4} pixels are not the clear colour — the '
    'clear was bounded by something, and the contract says it covers the '
    'whole attachment',
  );
}

Future<void> checkRowOrder(GraphicsDevice device) async {
  // Row zero is the top. A backend measuring from the bottom has to flip on the
  // way in, the way out, or both — and a caller cannot tell which way round it
  // was handed pixels, so a golden compared against a mirrored frame fails as
  // though rendering broke.
  const width = 4;
  const height = 4;
  final source = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      // Red increases downwards, so a mirrored readback is unmistakable.
      source[i] = y * 60;
      source[i + 3] = 255;
    }
  }

  final texture = device.createTextureFromPixels(
    width: width,
    height: height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(source),
  );
  require(
    texture != null,
    'the device made no texture from four by four '
    'RGBA8 pixels',
  );

  final read = await device.readPixels(texture!);
  require(read != null, 'the uploaded texture could not be read back');
  final bytes = read!.buffer.asUint8List();

  require(
    bytes[0] == source[0],
    'row zero came back as ${bytes[0]} where ${source[0]} was written: the '
    'image is upside down',
  );
  final last = (height - 1) * width * 4;
  require(
    bytes[last] == source[last],
    'the last row disagrees, which a flip would also cause',
  );
}

Future<void> checkGeometryUsage(GraphicsDevice device) async {
  // Not a hint. WebGL binds a buffer to its target for life, so one uploaded as
  // vertices can never be bound as indices — the attempt is an
  // INVALID_OPERATION, the draw is dropped, and the frame comes back the clear
  // colour with nothing logged.
  final bytes = ByteData(64);
  device.uploadGeometry(bytes, GeometryUsage.vertices);
  device.uploadGeometry(bytes, GeometryUsage.indices);
}

/// A cube takes the mip chain it is handed, and refuses a malformed one.
///
/// **The levels of a cube are a roughness scale, not a size optimisation.** A
/// prefiltered radiance map is exactly this: one cube whose levels are the
/// environment convolved further and further, sampled by how rough the surface
/// is. A backend that quietly drops the chain gives every rough metal a mirror
/// finish, which looks like a material bug and is a device one.
///
/// Two traps this exists for, one per backend that has hit them. WebGL fixes
/// the level count immutably at `texStorage2D`, so a backend that allocates one
/// level and then uploads four writes three of them into nothing. Impeller
/// allocates from a count it is told, so the same arithmetic done differently
/// there silently truncates the chain.
///
/// Sizes are not checked by drawing, deliberately: what a level *contains* is
/// the caller's business, and the pair that samples a cube already has a check
/// of its own. What is checked here is that a well-formed chain is accepted and
/// a malformed one is refused rather than half-uploaded.
Future<void> checkCubeMipLevels(GraphicsDevice device) async {
  if (!device.supportsCubeTextures) return;

  const size = 4;
  List<ByteData> faces(int side) => <ByteData>[
    for (var i = 0; i < 6; i++) ByteData(side * side * 4),
  ];

  final chained = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces(size),
    mipLevels: <List<ByteData>>[faces(2), faces(1)],
  );
  require(chained != null, 'a cube with a four-two-one chain was refused');

  // Refused rather than padded: a level of the wrong size is a caller that has
  // built its chain wrongly, and a device that accepts it hides the mistake
  // until something samples a rough reflection and finds noise.
  final ragged = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces(size),
    mipLevels: <List<ByteData>>[faces(size)],
  );
  require(
    ragged == null,
    'a level that is not half the one above it was accepted',
  );

  // Five faces in a level is the same class of mistake as five faces in the
  // base, which the interface already refuses.
  final short = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces(size),
    mipLevels: <List<ByteData>>[faces(2).sublist(0, 5)],
  );
  require(short == null, 'a level with five faces was accepted');
}
