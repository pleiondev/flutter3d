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

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 32;

/// `PolygonMode.line` is drawn as edges, or refused; never filled instead.
///
/// **The one capability that differs across the backends** — listed on
/// Impeller over Metal and Vulkan, not on Impeller's OpenGL ES path, WebGL2,
/// WebGPU or the software rasteriser — and the contract attaches a promise to
/// each answer. `DeviceFeature.wireframe`'s doc says a backend that cannot
/// draw it "refuses loudly rather than filling the triangles
/// instead, because a silent substitution here looks exactly like the wireframe
/// setting having no effect"; nothing was checking either half.
///
/// Counted rather than sampled at a chosen pixel, because a count says the same
/// thing wherever a backend puts row zero. A filled triangle of this size is
/// about four hundred pixels and its outline about ninety, so the two answers
/// are not near each other and the threshold does not have to be delicate.
Future<void> checkWireframeIsDrawnOrRefused(GraphicsDevice device) async {
  final (:pass, :target, :draw) = _oneTriangle(device);

  if (!device.features.has(DeviceFeature.wireframe)) {
    var refused = false;
    try {
      pass.setPolygonMode(PolygonMode.line);
      draw();
      pass.submit();
    } on UnsupportedCapabilityException {
      // Deliberately not submitted, for the reason
      // `checkUniformMemberMismatchIsRefused` gives: a backend is entitled to
      // release the pass on the way out.
      refused = true;
    } on UnsupportedError {
      // The same, from a backend that refuses with a bare UnsupportedError
      // rather than the UnsupportedCapabilityException the contract asks for.
      refused = true;
    }
    require(
      refused,
      'wireframe is not listed and PolygonMode.line was accepted anyway. A '
      'backend that cannot draw edges must throw an UnsupportedError rather '
      'than fill the triangles, which looks exactly like the wireframe '
      'setting having no effect. See DeviceFeature.wireframe.',
    );
    return;
  }

  pass.setPolygonMode(PolygonMode.line);
  draw();
  pass.submit();

  final painted = await _paintedPixels(device, target);
  require(
    painted > 40,
    'wireframe is listed and PolygonMode.line drew $painted pixels — '
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
    'wireframe is listed and PolygonMode.line filled the triangle: '
    '$painted pixels came back where an outline is about ninety. A backend '
    'that answers true must draw edges; one that cannot must answer false and '
    'throw. See DeviceFeature.wireframe.',
  );
}

/// Every [PrimitiveType] is assembled as itself, or refused as one.
///
/// Every backend in the repository that draws assembles all five since
/// 1.0.0-rc.1+2, strips and points behind `DeviceFeature.primitiveStrips` and
/// `DeviceFeature.pointPrimitives`; one without them refuses from
/// `setPrimitiveType`. The interesting half is not the refusal — it is that
/// a backend which quietly assembled `point` as `triangle` would draw a
/// plausible frame and pass everything else here.
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
    } on UnsupportedCapabilityException {
      refused = true;
    } on UnsupportedError {
      refused = true;
    } on Object catch (error) {
      throw ConformanceFailureException(
        'drawing PrimitiveType.${type.name} failed with '
        '${error.runtimeType}: $error. A backend that cannot assemble a '
        'primitive type refuses with an UnsupportedCapabilityException (or at least an '
        'UnsupportedError) — a caller deciding '
        'between two ways of drawing cannot act on anything else. See '
        'PassEncoder.setPrimitiveType.',
      );
    }
    painted[type] = refused ? null : await _paintedPixels(device, target);
  }

  // **Refused exactly where unlisted**, since 1.0.0-rc.1+2: a strip or a
  // point is drawn by a device that lists its feature and refused by one
  // that does not, never the other way round.
  for (final (type, feature) in <(PrimitiveType, DeviceFeature)>[
    (PrimitiveType.triangleStrip, DeviceFeature.primitiveStrips),
    (PrimitiveType.lineStrip, DeviceFeature.primitiveStrips),
    (PrimitiveType.point, DeviceFeature.pointPrimitives),
  ]) {
    final listed = device.features.has(feature);
    require(
      listed == (painted[type] != null),
      'PrimitiveType.${type.name} was ${painted[type] == null ? 'refused' : 'drawn'} '
      'by a device that ${listed ? 'lists' : 'does not list'} ${feature.name}',
    );
  }

  final filled = painted[PrimitiveType.triangle];
  require(
    filled != null && filled > _size * _size ~/ 4,
    'PrimitiveType.triangle drew $filled pixels of a $_size by $_size target, '
    'so nothing below can be compared against it',
  );

  // Mutation: make `CpuEncoder._drawOnce` read three corners a primitive
  // whatever the topology, so the software rasteriser assembles a point or a
  // line strip as a triangle. Every count then equals the filled one and the
  // requires below fail — which is the silent substitution the contract
  // forbids, and which no picture would show.
  for (final type in <PrimitiveType>[
    PrimitiveType.line,
    PrimitiveType.lineStrip,
    PrimitiveType.point,
  ]) {
    final count = painted[type];
    if (count == null) continue;
    // Half the filled area: two line segments across the target are the
    // largest honest answer, and the substitution this is looking for lands
    // exactly on the filled count rather than near it. `debug_line.vert`
    // writes `gl_PointSize = 1.0` on Impeller and GLES, so a point is one
    // pixel wherever the size is honoured; a tighter bound for [point] alone
    // waits for a run of every backend on a tree with that write in it.
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

    // **Primitive restart is always on for strips**, since 1.0.0-rc.1+2:
    // the same two triangles drawn as a list and as one strip broken by an
    // all-ones index cover the same pixels. Mutation: treat 0xFFFF as an
    // index in the software rasteriser's `_assembleStrip`, and the strip
    // stops at the vertex that does not exist, the second triangle missing.
    final list = await _paintedPixels(
      device,
      _twoTriangles(device, PrimitiveType.triangle, <int>[0, 1, 2, 3, 4, 5]),
    );
    final restarted = await _paintedPixels(
      device,
      _twoTriangles(device, PrimitiveType.triangleStrip, <int>[
        0,
        1,
        2,
        IndexType.int16.restartIndex,
        3,
        4,
        5,
      ]),
    );
    require(
      (restarted - list).abs() * 20 <= list,
      'two triangles drawn as a strip broken by an all-ones index painted '
      '$restarted pixels where the same two as a list painted $list. A '
      'backend that lists primitive-strips restarts a strip at 0xFFFF; see '
      'PassEncoder.setPrimitiveType.',
    );
  }
}

/// Two triangles side by side, drawn as [type] through [indices] into a
/// fresh target, which is returned once the pass is submitted.
TextureHandle _twoTriangles(
  GraphicsDevice device,
  PrimitiveType type,
  List<int> indices,
) {
  final (:pass, :target, draw: _) = _oneTriangle(device);
  final vertex = device.shaders['DebugLineVertex']!;
  final vertices = Float32List.fromList(<double>[
    -0.9, -0.6, 0.5, 1, 1, 1, 1, //
    -0.1, -0.6, 0.5, 1, 1, 1, 1,
    -0.5, 0.6, 0.5, 1, 1, 1, 1,
    0.1, -0.6, 0.5, 1, 1, 1, 1,
    0.9, -0.6, 0.5, 1, 1, 1, 1,
    0.5, 0.6, 0.5, 1, 1, 1, 1,
  ]);
  pass
    ..setPrimitiveType(type)
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(vertices), 6)
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(indices)),
      IndexType.int16,
      indices.length,
    )
    ..draw()
    ..submit();
  return target;
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
    const RenderTargetDescriptor(
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
          clearValue: ClearColor.transparentBlack,
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(
      device.createPipelineFrom(
        PipelineDescriptor(vertex: vertex!, fragment: fragment!),
      ),
    );

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
  final read = await device.readback(target);
  final bytes = read.buffer.asUint8List();
  return <int>[
    for (var i = 0; i < bytes.length; i += 4)
      if (bytes[i] > 64 || bytes[i + 1] > 64 || bytes[i + 2] > 64) i,
  ].length;
}
