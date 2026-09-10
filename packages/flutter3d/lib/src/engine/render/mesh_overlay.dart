import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'pass_contributor.dart';

/// What a modeller draws on top of the surface: edges, vertices, the selection.
///
/// **Why this is not `DebugDraw`.** That one answers "show me the normals" for
/// somebody looking for a bug, and it is lines only, always on top, rebuilt
/// from the scene every frame. A modeller's overlay is the interface: it is
/// looked at for hours, it has to sit *on* the surface rather than through it,
/// a vertex has to be a thing a finger can hit, and it is rebuilt when the
/// selection changes rather than when the camera moves. The two share a
/// pipeline and nothing else.
///
/// **Three batches, three draws, whatever is in them.** Lines, solid triangles
/// and translucent ones are three different pieces of state, and everything
/// inside one of them goes in a single buffer — so a hundred thousand edges
/// cost the same three draw calls as one. That is the whole reason the geometry
/// is built on the CPU into one array instead of being asked of the scene node
/// by node.
///
/// **Points and ribbons are sized in pixels, not in metres.** A vertex handle
/// that shrinks as the camera pulls back is a handle nobody can hit; the same
/// is true of a highlighted edge that thins to nothing. So [lookFrom] is told
/// how a pixel maps to the world, and a point stays the same size on screen
/// however far away it is — which is also why the batch has to be rebuilt when
/// the camera moves and the line batch does not.
///
/// **Nudged towards the eye, and tested with `lessEqual`.** An edge drawn
/// exactly on the surface it belongs to is a coin flip per pixel, and the coin
/// lands differently on every backend. Pushing the overlay a hair towards the
/// camera — by a distance that grows with depth, so it is a constant in screen
/// space — and letting equal depths pass is what makes an edge sit on its face
/// rather than flicker through it.
final class MeshOverlay extends PassContributor {
  /// Built with the two stages of the line pipeline, which the renderer holds
  /// as `debugLineVertexShader` and `debugLineFragmentShader`.
  ///
  /// Handed in rather than looked up, because a contributor is given a device
  /// and a pass and nothing else — and widening that interface so one overlay
  /// can find two shaders would be widening it for everybody.
  MeshOverlay({required this.vertexShader, required this.fragmentShader});

  final ShaderHandle vertexShader;
  final ShaderHandle fragmentShader;

  /// position.xyz + colour.rgba, which is [VertexLayout.positionColor] and what
  /// the `DebugLine` pipeline reads.
  static const int floatsPerVertex = 7;

  /// Thin lines: the wireframe, the grid, an unselected edge.
  final OverlayBatch lines = OverlayBatch();

  /// Triangles drawn solid: vertex handles and the ribbons of a selected edge.
  final OverlayBatch handles = OverlayBatch();

  /// Triangles drawn translucent: the wash over a selected face.
  final OverlayBatch fill = OverlayBatch();

  /// How much of the surface a fill lets through.
  ///
  /// **A number the design chose, not a taste.** A fill opaque enough to read
  /// as a selection and thin enough to leave the shading under it visible is
  /// the difference between "this face is selected" and "this face is a flat
  /// colour" — and the second tells a person nothing about the shape they are
  /// working on.
  static const double fillOpacity = 0.55;

  /// Drawn last, over everything the scene put down.
  @override
  int get order => 900;

  @override
  bool get isActive => !lines.isEmpty || !handles.isEmpty || !fill.isEmpty;

  Vector3 _eye = Vector3.zero();
  Vector3 _right = Vector3(1, 0, 0);
  Vector3 _up = Vector3(0, 1, 0);
  double _pixel = 0.0;
  bool _perspective = true;

  /// Where the camera is and how big a pixel is in the world.
  ///
  /// [pixel] is the world size of one logical pixel: at one unit of distance
  /// for a perspective camera, and everywhere for an orthographic one. A
  /// caller with a vertical field of view `f` over a viewport `h` pixels tall
  /// passes `2 * tan(f / 2) / h`; one with an orthographic height `H` passes
  /// `H / h`.
  void lookFrom({
    required Vector3 eye,
    required Vector3 right,
    required Vector3 up,
    required double pixel,
    bool perspective = true,
  }) {
    _eye = Vector3.copy(eye);
    _right = right.normalized();
    _up = up.normalized();
    _pixel = pixel;
    _perspective = perspective;
  }

  /// How far from the eye a point is, in the units [lookFrom]'s pixel scales by.
  double _depth(Vector3 at) => _perspective ? (at - _eye).length : 1.0;

  /// The world size of [pixels] logical pixels at [at].
  double worldSize(double pixels, Vector3 at) => pixels * _pixel * _depth(at);

  /// Empties all three batches, keeping the buffers they grew.
  void clear() {
    lines.clear();
    handles.clear();
    fill.clear();
  }

  /// A colour a design named, converted for the target it lands in.
  ///
  /// **An overlay drawn in the scene pass pays the composite's transfer
  /// function; `DebugDraw` does not, and that is the whole difference between
  /// the two.** `DebugDraw` is encoded after the composite, so a byte it writes
  /// is the byte that reaches the screen. This is encoded inside the scene pass
  /// — it has to be, or the depth test could not let an edge sit on its own
  /// face — and everything written there is treated as a light quantity and
  /// encoded on the way out. A grid line handed over as `#2A3234` and written
  /// literally comes back as `#717B7D`: the same hue, half again as bright, and
  /// nothing in the picture to say why. So the design colour is converted here,
  /// which is what the engine's own normals stage does and for the same reason.
  ///
  /// The alpha is left alone: it is a coverage, not a colour, and the fill's
  /// 55 per cent means 55 per cent of the way to the surface either way.
  ///
  /// What this does *not* undo is the exposure and the tone curve. A viewport
  /// lighting a scene at 1.6 shows the grid a little lighter than the hex says,
  /// and that is deliberate: the floor is in the picture rather than pasted on
  /// top of it, and a floor that ignored the exposure would be the one thing on
  /// screen that did.
  static Vector4 asDrawn(Vector4 colour) => Vector4(
    _toLinear(colour.x),
    _toLinear(colour.y),
    _toLinear(colour.z),
    colour.w,
  );

  /// sRGB to linear, per the engine's `color.glsl`. A copy rather than an
  /// import, the way `sky_settings.dart` keeps its own `smoothstep`: two lines
  /// of arithmetic against a dependency from the renderer to a backend.
  static double _toLinear(double c) =>
      c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// A line between two points.
  void edge(Vector3 from, Vector3 to, Vector4 colour) {
    final drawn = asDrawn(colour);
    lines
      ..vertex(_towardsEye(from), drawn)
      ..vertex(_towardsEye(to), drawn);
  }

  /// A square facing the camera, [size] logical pixels across.
  ///
  /// What a vertex is, and the reason a vertex is not a line: a point of one
  /// pixel is unhittable on a phone and invisible on a display that scales.
  void point(Vector3 at, Vector4 colour, {double size = 7}) {
    final half = worldSize(size, at) * 0.5;
    final x = _right * half;
    final y = _up * half;
    final middle = _towardsEye(at);
    _quad(
      handles,
      middle - x - y,
      middle + x - y,
      middle + x + y,
      middle - x + y,
      asDrawn(colour),
    );
  }

  /// A band from [from] to [to], [width] logical pixels across, turned to face
  /// the camera.
  ///
  /// A selected edge drawn as a line is a selected edge nobody can see against
  /// the wireframe beside it. The width is in pixels for the same reason a
  /// point's size is.
  void ribbon(Vector3 from, Vector3 to, Vector4 colour, {double width = 3}) {
    final along = to - from;
    if (along.length2 == 0) return;
    final middle = (from + to) * 0.5;
    var side = along.cross(middle - _eye);
    if (side.length2 == 0) side = _right.clone();
    side.normalize();
    final half = worldSize(width, middle) * 0.5;
    final offset = side * half;
    _quad(
      handles,
      _towardsEye(from) - offset,
      _towardsEye(to) - offset,
      _towardsEye(to) + offset,
      _towardsEye(from) + offset,
      asDrawn(colour),
    );
  }

  /// A translucent triangle over a face.
  void wash(Vector3 a, Vector3 b, Vector3 c, Vector4 colour) {
    final washed = asDrawn(Vector4(colour.x, colour.y, colour.z, fillOpacity));
    fill
      ..vertex(_towardsEye(a), washed)
      ..vertex(_towardsEye(b), washed)
      ..vertex(_towardsEye(c), washed);
  }

  /// How far towards the eye the overlay sits, in logical pixels of depth.
  ///
  /// Small enough that nothing looks detached and large enough to beat the
  /// float32 depth buffer at the distances a modeller works at.
  double biasPixels = 12;

  Vector3 _towardsEye(Vector3 at) {
    final away = _eye - at;
    final distance = away.length;
    if (distance == 0) return Vector3.copy(at);
    return at + away * (worldSize(biasPixels, at) / distance);
  }

  void _quad(
    OverlayBatch batch,
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Vector3 d,
    Vector4 colour,
  ) {
    batch
      ..vertex(a, colour)
      ..vertex(b, colour)
      ..vertex(c, colour)
      ..vertex(a, colour)
      ..vertex(c, colour)
      ..vertex(d, colour);
  }

  PipelineHandle? _pipeline;

  /// The index sequence 0, 1, 2, … that every draw here is made through.
  ///
  /// **Not an optimisation and not a formality: `CommandEncoder.draw` in this
  /// engine is always indexed, and there is no non-indexed path.** A draw with
  /// a vertex buffer and no index buffer bound is a draw of nothing — silently,
  /// with no refusal and no empty-frame report, because binding nothing is a
  /// legal state that the mesh loop passes through between draws. The overlay
  /// went a whole commit drawing nothing for exactly that reason, and every
  /// test it had still passed, because they all read the batch. `DebugDraw`
  /// keeps the same sequence for the same reason.
  GeometryBuffer? _indices;
  int _indexCapacity = 0;

  /// A view over that sequence long enough for [count] vertices.
  GeometryBuffer _identityIndices(GraphicsDevice device, int count) {
    if (count > _indexCapacity) {
      var capacity = math.max(_indexCapacity * 2, 1024);
      while (capacity < count) {
        capacity *= 2;
      }
      final indices = Uint32List(capacity);
      for (var i = 0; i < capacity; i++) {
        indices[i] = i;
      }
      _indices = device.uploadGeometry(
        indices.buffer.asByteData(),
        GeometryUsage.indices,
      );
      _indexCapacity = capacity;
    }
    return _indices!.slice(length: count * 4);
  }

  @override
  void encode(ContributorFrame frame) {
    final viewProjection = frame.viewProjection;
    if (viewProjection == null) return;

    // The mesh draws left an index buffer bound, and these are non-indexed:
    // a stale one would read triangle indices as overlay vertices.
    frame.encoder.clearBindings();
    frame.encoder.bindPipeline(
      _pipeline ??= frame.device.createPipeline(vertexShader, fragmentShader),
    );
    frame.state.invalidatePipeline();

    _draw(frame, lines, _kLineState, viewProjection);
    _draw(frame, handles, _kSolidState, viewProjection);
    _draw(frame, fill, _kFillState, viewProjection);
  }

  void _draw(
    ContributorFrame frame,
    OverlayBatch batch,
    PassState state,
    Matrix4 viewProjection,
  ) {
    if (batch.isEmpty) return;
    frame.encoder
      ..setState(state)
      ..bindVertexData(batch.vertexBytes, batch.vertexCount)
      ..bindIndexBuffer(
        _identityIndices(frame.device, batch.vertexCount),
        IndexType.int32,
        batch.vertexCount,
      )
      ..bindUniformBlock(vertexShader, 'LineInfo', {
        'view_projection': viewProjection.storage,
      })
      ..draw();
    frame.state.drawCalls++;
  }

  /// **`lessEqual` rather than `always`, which is the whole difference from
  /// `DebugDraw`.** An overlay drawn over everything shows the edges of the far
  /// side of a box as though they were on the near side, and a person reading a
  /// silhouette cannot tell which is which. Letting the depth buffer refuse the
  /// hidden ones — and letting equal depths through, because the overlay was
  /// nudged to exactly that — is what makes the picture readable.
  static const PassState _kLineState = PassState(
    primitiveType: PrimitiveType.line,
    polygonMode: PolygonMode.fill,
    cullMode: CullMode.none,
    blend: null,
    depthWrite: false,
    depthCompare: CompareFunction.lessEqual,
  );

  static const PassState _kSolidState = PassState(
    primitiveType: PrimitiveType.triangle,
    polygonMode: PolygonMode.fill,
    cullMode: CullMode.none,
    blend: null,
    depthWrite: false,
    depthCompare: CompareFunction.lessEqual,
  );

  static const PassState _kFillState = PassState(
    primitiveType: PrimitiveType.triangle,
    polygonMode: PolygonMode.fill,
    cullMode: CullMode.none,
    blend: BlendState.alphaBlend,
    depthWrite: false,
    depthCompare: CompareFunction.lessEqual,
  );
}

/// One buffer of overlay vertices, grown rather than reallocated.
///
/// A modeller rebuilds this every time a selection changes — which, while
/// somebody is dragging a box round part of a model, is every frame. A fresh
/// `Float32List` per rebuild on a mesh with two hundred thousand edges is five
/// megabytes a frame of garbage for numbers that are overwritten immediately.
final class OverlayBatch {
  OverlayBatch({int reserveVertices = 256})
    : _data = Float32List(
        math.max(1, reserveVertices) * MeshOverlay.floatsPerVertex,
      );

  Float32List _data;
  int _floats = 0;

  int get vertexCount => _floats ~/ MeshOverlay.floatsPerVertex;

  bool get isEmpty => _floats == 0;

  /// The used part of the buffer, ready to upload.
  ByteData get vertexBytes =>
      _data.buffer.asByteData(_data.offsetInBytes, _floats * 4);

  void clear() => _floats = 0;

  void vertex(Vector3 at, Vector4 colour) {
    if (_floats + MeshOverlay.floatsPerVertex > _data.length) {
      _grow(_floats + MeshOverlay.floatsPerVertex);
    }
    _data[_floats] = at.x;
    _data[_floats + 1] = at.y;
    _data[_floats + 2] = at.z;
    _data[_floats + 3] = colour.x;
    _data[_floats + 4] = colour.y;
    _data[_floats + 5] = colour.z;
    _data[_floats + 6] = colour.w;
    _floats += MeshOverlay.floatsPerVertex;
  }

  void _grow(int need) {
    var length = _data.length * 2;
    while (length < need) {
      length *= 2;
    }
    _data = Float32List(length)..setRange(0, _floats, _data);
  }
}
