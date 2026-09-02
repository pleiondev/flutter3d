import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// A pass draws into the whole of its attachment, and no more.
///
/// **The check the pipeline-switch one was accidentally making**, and it took
/// two wrong diagnoses to find that out. `runDeviceConformance` builds a 64×64
/// device and several checks then draw into a 16×16 target; if a backend leaves
/// the viewport at the size of its canvas, clip space is stretched across four
/// times the attachment and every draw lands somewhere other than where its
/// matrix said. Nothing in the engine caught it because every one of its passes
/// sets a viewport before drawing, so the default was never exercised.
///
/// Half a quad rather than a full-screen triangle, because a shape that covers
/// everything looks the same at any viewport. The left half of clip space is
/// painted; the right half must come back as it was cleared.
Future<void> checkPassCoversItsAttachment(GraphicsDevice device) async {
  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  // x from −1 to 0, y over the whole of it: the left half of the frame.
  final leftHalf = Float32List.fromList(<double>[
    -1, -1, 0.5, 0, 1, 0, 1, //
    0, -1, 0.5, 0, 1, 0, 1,
    0, 1, 0.5, 0, 1, 0, 1,
    -1, 1, 0.5, 0, 1, 0, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]);

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
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
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(leftHalf), 4)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 6)
    ..draw();
  pass.submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the target could not be read back');
  final bytes = pixels!.buffer.asUint8List();
  int green(int x, int y) => bytes[((y * size + x) * 4) + 1];

  require(
    green(size ~/ 4, size ~/ 2) > 128,
    'the left quarter of the attachment is unpainted, so the pass drew into '
    'less than its attachment — a viewport smaller than what it renders to '
    '(came back ${green(size ~/ 4, size ~/ 2)})',
  );
  require(
    green(size * 3 ~/ 4, size ~/ 2) < 128,
    'the right quarter of the attachment is painted by a shape that stops at '
    'the middle of clip space, so the pass drew into more than its '
    'attachment — a viewport left at the size of something else, most likely '
    'the canvas or the previous pass '
    '(came back ${green(size * 3 ~/ 4, size ~/ 2)})',
  );
}

/// A readback of a region reads that region of a *drawn* picture, rows from
/// the top.
///
/// The core check settles the ordering with clears, and a clear is the same
/// colour everywhere — so it cannot tell a region from its mirror image, and a
/// mirror image is precisely what a backend whose framebuffer origin is at the
/// bottom produces when it forgets to turn a rendered region over. The
/// whole-texture [GraphicsDevice.readPixels] learned that lesson once; a
/// region has an extra way to get it wrong, because the rectangle's own y has
/// to be measured from the other edge as well as the rows inside it.
///
/// So: the top half of clip space is painted, and a region in the top-left
/// quarter must be painted while one in the bottom-left quarter must not. A
/// region straddling the middle then has its painted rows first.
Future<void> checkReadbackOfRegion(GraphicsDevice device) async {
  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  // y from 0 to 1, x over the whole of it: the top half of the picture on
  // every backend, since clip +y is up wherever row zero is stored.
  final topHalf = Float32List.fromList(<double>[
    -1, 0, 0.5, 0, 1, 0, 1, //
    1, 0, 0.5, 0, 1, 0, 1,
    1, 1, 0.5, 0, 1, 0, 1,
    -1, 1, 0.5, 0, 1, 0, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]);

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
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
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(topHalf), 4)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 6)
    ..draw();
  pass.submit();

  const quarter = size ~/ 4;
  final top = (await device.readback(
    target,
    region: const ScreenRect(x: 0, y: 0, width: quarter, height: quarter),
  )).buffer.asUint8List();
  final bottom = (await device.readback(
    target,
    region: const ScreenRect(
      x: 0,
      y: size - quarter,
      width: quarter,
      height: quarter,
    ),
  )).buffer.asUint8List();
  require(
    top[1] > 128,
    'a region in the top-left quarter of a picture whose top half is painted '
    'came back unpainted (green ${top[1]}): the region was measured from the '
    'wrong edge',
  );
  require(
    bottom[1] < 128,
    'a region in the bottom-left quarter came back painted (green '
    '${bottom[1]}): the region was measured from the wrong edge',
  );

  // Two rows above the middle and two below, in one region: the painted rows
  // have to come first, or the rows inside the region were not turned over.
  final straddling = (await device.readback(
    target,
    region: const ScreenRect(x: 0, y: size ~/ 2 - 2, width: 2, height: 4),
  )).buffer.asUint8List();
  int green(int row) => straddling[(row * 2) * 4 + 1];
  require(
    green(0) > 128 && green(1) > 128 && green(2) < 128 && green(3) < 128,
    'a region straddling the painted edge came back with rows '
    '${<int>[for (var r = 0; r < 4; r++) green(r)]} from the top; the '
    'painted two should be first',
  );
}

/// A pass does not inherit the rectangle the previous one was clipped to.
///
/// **The half of the last check that costs a whole frame rather than a corner.**
/// A backend that keeps the scissor test enabled between passes — which is the
/// reasonable thing to do, since the engine sets one per shadow tile — starts
/// each pass clipped to whatever tile the last one finished on. Everything drawn
/// outside it is discarded, silently, and the symptom is a frame that is correct
/// in one rectangle and untouched everywhere else.
///
/// Two passes on one device, because one pass cannot leak into itself.
Future<void> checkPassDoesNotInheritScissor(GraphicsDevice device) async {
  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  final everything = Float32List.fromList(<double>[
    -1, -1, 0.5, 0, 1, 0, 1, //
    3, -1, 0.5, 0, 1, 0, 1,
    -1, 3, 0.5, 0, 1, 0, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  Future<Uint8List> paintAll({ScreenRect? clippedTo}) async {
    final target = device.createTexture(
      const RenderTargetSpec(
        width: size,
        height: size,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
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
      ..setCullMode(CullMode.none);
    // Only the first pass narrows itself. The second sets nothing, which is the
    // whole question: what does a pass that says nothing about clipping get?
    if (clippedTo != null) pass.setScissor(clippedTo);
    pass
      ..bindPipeline(device.createPipeline(vertex!, fragment!))
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      })
      ..bindVertexData(ByteData.sublistView(everything), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw();
    pass.submit();
    final pixels = await device.readPixels(target);
    require(pixels != null, 'the target could not be read back');
    return pixels!.buffer.asUint8List();
  }

  // A tile in the top-left corner, the shape a shadow atlas draws into.
  await paintAll(
    clippedTo: const ScreenRect(
      x: 0,
      y: 0,
      width: size ~/ 4,
      height: size ~/ 4,
    ),
  );

  final second = await paintAll();
  final corner = second[((size ~/ 2) * size + (size ~/ 2)) * 4 + 1];
  require(
    corner > 128,
    'a pass that set no scissor was clipped to the tile the previous pass '
    'set: the middle of the attachment is unpainted by a draw that covers '
    'all of clip space (came back $corner)',
  );
}
