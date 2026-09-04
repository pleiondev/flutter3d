/// What a backend that cannot do something must do instead.
///
/// ARCHITECTURE.md §7.2 states the rule once — "a backend refuses loudly rather
/// than substituting something that looks similar" — and until these ran,
/// nothing anywhere held a backend to it. The two capabilities that differ
/// across the three implementations are exercised here, and both are exercised
/// in the direction that matters: a backend that answers `false` and then
/// quietly draws something else passes every other check in the suite, because
/// what it draws is a plausible picture.
///
/// **The refusal is typed.** `UnsupportedError` and not a bare `Exception`,
/// because the caller that asks is deciding between two ways of drawing —
/// wireframe or an index buffer of lines — and a `catch` that cannot tell "this
/// backend will not" from "this frame went wrong" is not a decision it can act
/// on.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 32;

/// `PolygonMode.line` is drawn as edges, or refused; never filled instead.
///
/// **The one capability that differs across all three backends** — true on
/// Impeller, false on WebGL2 and on the software rasteriser — and the contract
/// attaches a promise to each answer. `supportsWireframe`'s doc says a backend
/// that cannot draw it "refuses loudly rather than filling the triangles
/// instead, because a silent substitution here looks exactly like the wireframe
/// setting having no effect"; nothing was checking either half.
///
/// Counted rather than sampled at a chosen pixel, because a count says the same
/// thing wherever a backend puts row zero. A filled triangle of this size is
/// about four hundred pixels and its outline about ninety, so the two answers
/// are not near each other and the threshold does not have to be delicate.
Future<void> checkWireframeIsDrawnOrRefused(GraphicsDevice device) async {
  final (:pass, :target, :draw) = _oneTriangle(device);

  if (!device.supportsWireframe) {
    var refused = false;
    try {
      pass.setPolygonMode(PolygonMode.line);
      draw();
      pass.submit();
    } on UnsupportedError {
      // Deliberately not submitted, for the reason
      // `checkUniformMemberMismatchIsRefused` gives: a backend is entitled to
      // release the pass on the way out.
      refused = true;
    }
    require(
      refused,
      'supportsWireframe is false and PolygonMode.line was accepted anyway. A '
      'backend that cannot draw edges must throw an UnsupportedError rather '
      'than fill the triangles, which looks exactly like the wireframe '
      'setting having no effect. See GraphicsDevice.supportsWireframe.',
    );
    return;
  }

  pass.setPolygonMode(PolygonMode.line);
  draw();
  pass.submit();

  final painted = await _paintedPixels(device, target);
  require(
    painted > 40,
    'supportsWireframe is true and PolygonMode.line drew $painted pixels — '
    'the outline of a triangle this size is about ninety, so nothing was '
    'drawn at all',
  );
  // Mutation: make `GpuCommandEncoder.setPolygonMode` ignore its argument on
  // the Impeller backend, which is the only one that answers true. The count
  // goes to the filled area and this fails; that substitution is what the
  // capability exists to forbid and what no other check in the repository
  // would have noticed.
  require(
    painted < 250,
    'supportsWireframe is true and PolygonMode.line filled the triangle: '
    '$painted pixels came back where an outline is about ninety. A backend '
    'that answers true must draw edges; one that cannot must answer false and '
    'throw. See GraphicsDevice.supportsWireframe.',
  );
}

/// Every [PrimitiveType] is assembled as itself, or refused as one.
///
/// The software rasteriser draws two of the five and throws for the other
/// three; both hardware backends draw all five. Neither half was checked, and
/// the interesting half is not the throw — it is that a backend which quietly
/// assembled `point` as `triangle` would draw a plausible frame and pass
/// everything else here.
///
/// Coverage is the discriminator and it is a blunt one on purpose: three
/// vertices make one filled triangle of some four hundred pixels, one or two
/// line segments of a few dozen, and three points of about three. A
/// substitution does not move that count, it lands *on* it — a backend
/// assembling a strip as a list draws the same pixels — so the comparison only
/// has to separate "the same picture" from "a much smaller one", and the
/// threshold below is set for the one primitive whose size a driver chooses.
Future<void> checkPrimitiveTypesAreDrawnOrRefused(GraphicsDevice device) async {
  final painted = <PrimitiveType, int?>{};

  for (final type in PrimitiveType.values) {
    final (:pass, :target, :draw) = _oneTriangle(device);
    var refused = false;
    try {
      pass.setPrimitiveType(type);
      draw();
      pass.submit();
    } on UnsupportedError {
      refused = true;
    } on Object catch (error) {
      throw ConformanceFailure(
        'drawing PrimitiveType.${type.name} failed with '
        '${error.runtimeType}: $error. A backend that cannot assemble a '
        'primitive type refuses with an UnsupportedError — a caller deciding '
        'between two ways of drawing cannot act on anything else. See '
        'PassEncoder.setPrimitiveType.',
      );
    }
    painted[type] = refused ? null : await _paintedPixels(device, target);
  }

  final filled = painted[PrimitiveType.triangle];
  require(
    filled != null && filled > _size * _size ~/ 4,
    'PrimitiveType.triangle drew $filled pixels of a $_size by $_size target, '
    'so nothing below can be compared against it',
  );

  // Mutation: delete the `_primitive != PrimitiveType.triangle` guard in
  // `CpuEncoder._drawOnce`, so the software rasteriser assembles a point or a
  // strip as a triangle instead of refusing. Every count then equals the
  // filled one and the three requires below fail — which is the silent
  // substitution the guard exists to prevent, and which no picture would show.
  for (final type in <PrimitiveType>[
    PrimitiveType.line,
    PrimitiveType.lineStrip,
    PrimitiveType.point,
  ]) {
    final count = painted[type];
    if (count == null) continue;
    // Half the filled area, not a tenth of it, and the slack is for [point]
    // alone: `debug_line.vert` writes no `gl_PointSize`, which ES leaves
    // undefined, so a driver is entitled to draw three points of some size
    // nobody chose. Three points at any size a driver would pick stay well
    // under half a triangle, and the substitution this is looking for lands
    // exactly on the filled count rather than near it.
    require(
      count * 2 < filled!,
      'PrimitiveType.${type.name} drew $count pixels where a filled triangle '
      'draws $filled. Three vertices make at most two line segments or three '
      'points, so this backend assembled the primitive as something else '
      'rather than refusing it.',
    );
  }

  final strip = painted[PrimitiveType.triangleStrip];
  if (strip != null) {
    require(
      strip * 2 > filled!,
      'PrimitiveType.triangleStrip drew $strip pixels where the same three '
      'vertices as a triangle list drew $filled. A strip of three vertices is '
      'one triangle, so this backend assembled it as edges or points.',
    );
  }
}

/// A pass open on a fresh target, and the one triangle to draw into it.
///
/// The triangle sits inside the target rather than covering it, so its interior
/// holds pixels no edge of it touches — which is the whole of the difference
/// between a fill and an outline.
({CommandEncoder pass, TextureHandle target, void Function() draw})
_oneTriangle(GraphicsDevice device) {
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  final target = device.createTexture(
    const RenderTargetSpec(
      width: _size,
      height: _size,
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
    ..bindPipeline(device.createPipeline(vertex!, fragment!));

  final triangle = Float32List.fromList(<double>[
    -0.9, -0.9, 0.5, 1, 1, 1, 1, //
    0.9, -0.9, 0.5, 1, 1, 1, 1,
    0.0, 0.9, 0.5, 1, 1, 1, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  return (
    pass: pass,
    target: target,
    draw: () => pass
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      })
      ..bindVertexData(ByteData.sublistView(triangle), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw(),
  );
}

/// How many of [target]'s pixels are not the black it was cleared to.
///
/// A count rather than a named pixel, because a count is the same number
/// whichever end of the target a backend calls row zero — and these two checks
/// are about how much was drawn, never about where.
Future<int> _paintedPixels(GraphicsDevice device, TextureHandle target) async {
  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  return <int>[
    for (var i = 0; i < bytes.length; i += 4)
      if (bytes[i] > 64 || bytes[i + 1] > 64 || bytes[i + 2] > 64) i,
  ].length;
}
