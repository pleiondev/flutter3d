import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// Where a picture of the level is taken from: the eye, and the point it
/// looks at.
typedef LevelCamera = ({Vector3 from, Vector3 at});

/// The level as the software rasteriser draws it, and what an agent can learn
/// from the drawing — `screenshot` and `report`.
///
/// **Drawn with no GPU and no Flutter**, which is what this server could not
/// do while the level's scene was built inside `flutter3d_app`: the scene
/// comes from `LevelScene`, the device is `CpuDevice`, and both resolve under
/// `dart run`. One draw per brush (`LevelBatching.perBrush`), so a pixel names
/// the brush it belongs to, and a small box stands in for every light and
/// entity, which have no geometry of their own in a level and would otherwise
/// be nothing a picture or a pixel count can find.
///
/// **Flat.** A level's textures are decoded by the application that ships
/// them, and this process has no image decoder of the engine's to hand, so
/// every surface is drawn in the colour its material names. The report is
/// about where things are and what covers them, which a texture does not
/// change.
///
/// Built fresh for every call, because the document is the state and the
/// last call may have moved half of it.
final class LevelView {
  LevelView._(this._device, this._renderer, this._scene, this._pieces);

  /// Draws [level] into a new scene, ready to be looked at.
  factory LevelView.of(Level level) {
    final it = cpuTestDevice(width: width, height: height);
    final parts = const LevelScene(
      batching: LevelBatching.perBrush,
    ).build(level, device: it.device);
    // Every surface is one brush's in this batching. A brush whose every face
    // is buried in its neighbours makes none, and is reported with no node.
    final brushNodes = <int, MeshNode>{
      for (final batch in parts.batches)
        if (batch.brush case final int brush) brush: batch.node,
    };
    // A box to be seen by, for everything a level places that has no shape.
    // Unlit, so the picture shows it in its own colour whatever the lights
    // are doing, and casting nothing, so a marker never darkens a wall.
    final marker = DeviceMesh.upload(
      it.device,
      CuboidShape(size: Vector3.all(1.0)).build(),
    );
    _Piece markerFor(Listed row) {
      final size = row.size ?? Vector3.all(markerSize);
      final node =
          MeshNode(
              marker,
              Material(
                name: row.what,
                lighting: LightingModel.unlit,
                baseColor: row.kind == Piece.light
                    ? Vector4(1.0, 0.85, 0.3, 1.0)
                    : Vector4(0.2, 0.8, 1.0, 1.0),
              ),
              name: row.what,
            )
            ..setPositionFrom(row.at)
            ..setScale(size.x, size.y, size.z)
            ..shadowCasting = ShadowCastingMode.off;
      parts.scene.add(node);
      return _Piece(row, _boxOf(row.at, size), node);
    }

    // In the listing's order — brushes, lights, entities, each by index — so
    // the report reads in the order `list` printed.
    final pieces = <_Piece>[
      for (final row in contentsOf(level))
        row.kind == Piece.brush
            ? _Piece(row, _boxOf(row.at, row.size!), brushNodes[row.index])
            : markerFor(row),
    ];
    return LevelView._(
      it.device,
      Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      ),
      parts.scene,
      pieces,
    );
  }

  static const int width = 320;
  static const int height = 200;

  /// The side of the box drawn for a light, or for an entity that states no
  /// size of its own: a torch-sized thing, large enough to own pixels across
  /// a room and small enough not to hide what it hangs on.
  static const double markerSize = 0.3;

  final CpuDevice _device;
  final Renderer _renderer;
  final Scene _scene;
  final List<_Piece> _pieces;

  /// A camera that sees the level whole when nobody names one: inside the
  /// bounds of what the level contains, near one upper corner, looking at the
  /// middle — so an indoor level is seen from inside its own room rather
  /// than as the outside of a box. Null for a level with nothing in it.
  static LevelCamera? defaultCamera(Level level) {
    final rows = contentsOf(level);
    if (rows.isEmpty) return null;
    final box = Aabb3.minMax(rows.first.at.clone(), rows.first.at.clone());
    for (final row in rows) {
      box.hullPoint(row.at);
      if (row.size case final Vector3 size) {
        box
          ..hullPoint(row.at - size * 0.5)
          ..hullPoint(row.at + size * 0.5);
      }
    }
    final centre = box.center;
    final half = (box.max - box.min) * 0.5;
    return (
      from: centre + Vector3(half.x * 0.8, half.y * 0.3, half.z * 0.8),
      at: centre,
    );
  }

  /// A PNG of the level from [camera].
  Future<Uint8List> picture(LevelCamera camera) async {
    final (eye, result) = _draw(camera);
    _scene.remove(eye);
    final pixels = await _device.readPixels(result.frame);
    if (pixels == null) throw StateError('the frame could not be read back');
    return encodePng(pixels.buffer.asUint8List(), width, height);
  }

  /// What is on the screen from [camera], piece by piece and in the order
  /// `list` prints: how many pixels each owns, where they are, how far away
  /// it is, and what covers the part of the screen it would fill.
  Future<List<PieceReport>> report(LevelCamera camera) async {
    final asked = _renderer.captureObjectIds();
    final (eye, _) = _draw(camera);
    _scene.remove(eye);
    final ids = await asked;
    final viewProjection = eye.viewProjection(width / height);
    final view = eye.viewMatrix;

    final owned = ids.pixelCounts();
    // Where each id's pixels are, as left, top, right, bottom.
    final boxes = <int, List<int>>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final id = ids.idAt(x, y);
        if (id == 0) continue;
        final box = boxes.putIfAbsent(id, () => <int>[x, y, x, y]);
        if (x < box[0]) box[0] = x;
        if (y < box[1]) box[1] = y;
        if (x > box[2]) box[2] = x;
        if (y > box[3]) box[3] = y;
      }
    }
    final idOf = <MeshNode, int>{
      for (var id = 1; id <= ids.nodes.length; id++) ids.nodes[id - 1]: id,
    };
    final pieceOf = <int, _Piece>{
      for (final piece in _pieces)
        if (idOf[piece.node] case final int id) id: piece,
    };
    final depths = <_Piece, ({double near, double far})?>{
      for (final piece in _pieces) piece: _depthOf(view, piece.box),
    };
    // The ray through the middle of each pixel, from the eye: two points of
    // the pixel's line unprojected, one on the near plane and one on the far.
    final unproject = Matrix4.inverted(viewProjection);
    final origin = camera.from;
    Vector3 rayThrough(int x, int y) {
      final ndcX = (x + 0.5) / width * 2.0 - 1.0;
      final ndcY = 1.0 - (y + 0.5) / height * 2.0;
      final nearPoint = unproject.transformed(Vector4(ndcX, ndcY, 0.0, 1.0));
      final farPoint = unproject.transformed(Vector4(ndcX, ndcY, 1.0, 1.0));
      return (farPoint.xyz / farPoint.w - nearPoint.xyz / nearPoint.w)
        ..normalize();
    }

    PieceReport reportOf(_Piece piece) {
      final id = idOf[piece.node];
      final depth = depths[piece];
      final bounds = depth == null
          ? null
          : screenBoundsOfBox(
              viewProjection,
              piece.box,
              width: width.toDouble(),
              height: height.toDouble(),
            );
      // The part of the frame the box would fill, in whole pixels.
      final left = bounds == null ? 0 : bounds.left.floor().clamp(0, width);
      final top = bounds == null ? 0 : bounds.top.floor().clamp(0, height);
      final right = bounds == null ? 0 : bounds.right.ceil().clamp(0, width);
      final bottom = bounds == null ? 0 : bounds.bottom.ceil().clamp(0, height);
      // Every pixel of that part whose ray passes through the piece's box is
      // a pixel the piece would own with nothing in the way — its silhouette.
      // One owned by something else is covered by it when that ray enters
      // the other's box first: every piece is a box, so the question has an
      // exact answer, and a wall behind a torch is not what hides it.
      var silhouette = 0;
      final inFront = <_Piece, int>{};
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final ray = rayThrough(x, y);
          final own = _entry(origin, ray, piece.box);
          if (own == null) continue;
          silhouette++;
          final other = ids.idAt(x, y);
          if (other == 0 || other == id) continue;
          final coverer = pieceOf[other];
          if (coverer == null) continue;
          final theirs = _entry(origin, ray, coverer.box);
          if (theirs != null && theirs < own) {
            inFront[coverer] = (inFront[coverer] ?? 0) + 1;
          }
        }
      }
      final covering = <({String who, double share})>[
        for (final entry in inFront.entries)
          (who: entry.key.row.label, share: entry.value / silhouette),
      ]..sort((a, b) => b.share.compareTo(a.share));
      final box = id == null ? null : boxes[id];
      return PieceReport(
        label: piece.row.label,
        pixels: id == null ? 0 : owned[id],
        screenBox: box == null
            ? null
            : (left: box[0], top: box[1], right: box[2], bottom: box[3]),
        depth: depth,
        inView: silhouette > 0,
        covering: covering,
      );
    }

    return <PieceReport>[for (final piece in _pieces) reportOf(piece)];
  }

  (CameraNode, FrameResult) _draw(LevelCamera camera) {
    final eye = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.2,
        near: 0.05,
        far: 200.0,
      ),
    )..setPositionFrom(camera.from);
    eye.lookAt(camera.at);
    _scene.add(eye);
    final result = _renderer.render(
      width: width,
      height: height,
      scene: _scene,
      views: <RenderView>[
        RenderView(camera: eye, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
    );
    return (eye, result);
  }

  /// How far in front of the eye [box] reaches, nearest and farthest, or
  /// null when all of it is behind the eye.
  static ({double near, double far})? _depthOf(Matrix4 view, Aabb3 box) {
    var near = double.infinity;
    var far = double.negativeInfinity;
    final corner = Vector3.zero();
    for (var i = 0; i < 8; i++) {
      corner.setValues(
        (i & 1) == 0 ? box.min.x : box.max.x,
        (i & 2) == 0 ? box.min.y : box.max.y,
        (i & 4) == 0 ? box.min.z : box.max.z,
      );
      // The eye looks down its own -Z, so distance ahead is minus that.
      final ahead = -view.transformed3(corner).z;
      if (ahead < near) near = ahead;
      if (ahead > far) far = ahead;
    }
    if (far <= 0.0) return null;
    return (near: near < 0.0 ? 0.0 : near, far: far);
  }

  /// How far along [ray] from [origin] it enters [box] — zero when it starts
  /// inside — or null when it misses. The slab test: the latest of the three
  /// entries, provided it comes before the earliest of the three exits.
  static double? _entry(Vector3 origin, Vector3 ray, Aabb3 box) {
    var enter = 0.0;
    var exit = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final from = origin[axis];
      final step = ray[axis];
      final low = box.min[axis];
      final high = box.max[axis];
      if (step.abs() < 1e-12) {
        if (from < low || from > high) return null;
        continue;
      }
      final a = (low - from) / step;
      final b = (high - from) / step;
      final (near, far) = a < b ? (a, b) : (b, a);
      if (near > enter) enter = near;
      if (far < exit) exit = far;
      if (enter > exit) return null;
    }
    return enter;
  }

  static Aabb3 _boxOf(Vector3 centre, Vector3 size) =>
      Aabb3.minMax(centre - size * 0.5, centre + size * 0.5);
}

/// One row of the listing, the box it fills in the world, and the node that
/// draws it — null for a brush buried whole in its neighbours.
final class _Piece {
  _Piece(this.row, this.box, this.node);

  final Listed row;
  final Aabb3 box;
  final MeshNode? node;
}

extension on Listed {
  /// What the report calls it: the kind and index `select` takes, and the
  /// word the document uses.
  String get label => '${kind.name} $index · $what';
}

/// What one piece of the level looks like from a camera.
final class PieceReport {
  const PieceReport({
    required this.label,
    required this.pixels,
    required this.screenBox,
    required this.depth,
    required this.inView,
    required this.covering,
  });

  /// The kind and index `select` takes, and the document's word for it.
  final String label;

  /// How many pixels of the frame it owns.
  final int pixels;

  /// The box around the pixels it owns, in pixels from the top left and
  /// inclusive; null when it owns none.
  final ({int left, int top, int right, int bottom})? screenBox;

  /// How far in front of the eye its box reaches, in metres; null when all of
  /// it is behind the eye.
  final ({double near, double far})? depth;

  /// Whether the box it fills in the world lands on the frame at all.
  final bool inView;

  /// What owns the pixels of the part of the screen its world box would fill
  /// — only the pieces that can be in front of it — with the share of that
  /// part each owns, most first.
  final List<({String who, double share})> covering;

  /// One line, the way the listing prints one.
  String get says {
    String metres(double it) => it.toStringAsFixed(1);
    final seen = pixels > 0
        ? '$pixels px'
        : depth == null
        ? 'behind the camera'
        : !inView
        ? 'outside the view'
        : 'hidden';
    final box = screenBox;
    final range = depth;
    // What rounds to no share at all is a pixel of a seam, not a cover.
    final covers = covering
        .where((it) => it.share >= 0.005)
        .take(3)
        .map((it) => '${it.who} ${(it.share * 100).round()}%');
    return <String>[
      label,
      seen,
      if (box != null) 'box ${box.left},${box.top}–${box.right},${box.bottom}',
      if (range != null) 'depth ${metres(range.near)}–${metres(range.far)} m',
      if (covers.isNotEmpty) 'covered by ${covers.join(', ')}',
    ].join(' · ');
  }
}
