/// A cloud cut into an octree of levels of detail, and the file it pages
/// from — `C7`.
///
/// **What the tree is for.** A capture is millions of Gaussians and most of
/// them, most of the time, are a pixel or less on screen. The leaves of this
/// tree are the original splats, a few hundred to a box; every node above
/// holds its children's splats *merged*, a few hundred Gaussians standing in
/// for the eight boxes below. Drawing a node instead of its children is
/// drawing the same shape with fewer, fatter splats — which from far enough
/// away is the same picture. `SplatLod` picks how deep to go where, under a
/// splat budget.
///
/// **Merged by moment matching, not by picking survivors.** Each merged
/// Gaussian is the one with the same weighted mean and covariance as the
/// splats it replaces, the weight being opacity times a splat's footprint.
/// Keeping one splat in eight instead would leave holes where the dropped
/// ones stood; a matched Gaussian covers what they covered. The splats are
/// grouped for merging by a grid over the node's own box, so what merges is
/// what sits together.
///
/// **Only band 0 of the spherical harmonics is kept in the tree.** Nothing in
/// the draw evaluates the higher bands yet, and averaging them across a
/// merge is a question for when something does.
///
/// **The file is the tree, breadth first.** A header, a table of every node,
/// then each node's splats as one contiguous page, coarse levels first. A
/// viewer reads the header and the table, then the root's page, and asks for
/// deeper pages only where the cut wants them — each one a single range
/// request (`PagedSplatOctree`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException, FormatSpec;
import 'package:vector_math/vector_math.dart';

import 'splat_cloud.dart';

/// One box of the tree.
final class SplatOctreeNode {
  SplatOctreeNode({
    required this.x,
    required this.y,
    required this.z,
    required this.radius,
    required this.firstChild,
    required this.childCount,
    required this.splatCount,
    required this.pageOffset,
    this.splats,
  });

  /// The centre of the box, in the cloud's own units.
  final double x, y, z;

  /// A sphere around every splat centre in the box: half the box's diagonal.
  /// In metres.
  final double radius;

  /// The children are nodes `firstChild .. firstChild + childCount - 1`,
  /// contiguous because the tree is stored breadth first.
  final int firstChild;
  final int childCount;

  /// How many splats this node draws when the cut stops here.
  final int splatCount;

  /// Where this node's page starts in the file.
  final int pageOffset;

  /// The node's own splats — the originals for a leaf, the merged ones above
  /// — or null while its page has not arrived.
  SplatCloud? splats;

  bool get isLeaf => childCount == 0;
  bool get isLoaded => splats != null;
}

/// A cloud as a tree of levels of detail. Node 0 is the root.
final class SplatOctree {
  SplatOctree(this.nodes)
    : leafSplatCount = nodes.fold(
        0,
        (int sum, SplatOctreeNode n) => n.isLeaf ? sum + n.splatCount : sum,
      );

  final List<SplatOctreeNode> nodes;

  /// Every leaf's splats together: the whole original cloud.
  final int leafSplatCount;

  /// Moves every time a page is attached, so a drawer holding a cut knows
  /// the tree can now offer a finer one.
  int get pageVersion => _pageVersion;
  int _pageVersion = 0;

  /// Gives node [index] its splats, when its page arrives.
  void attach(int index, SplatCloud splats) {
    final node = nodes[index];
    if (splats.count != node.splatCount) {
      throw ArgumentError(
        'node $index holds ${node.splatCount} splats; the page has '
        '${splats.count}',
      );
    }
    node.splats = splats;
    _pageVersion++;
  }
}

/// Builds the tree over [cloud].
///
/// A box of at most [leafCapacity] splats is a leaf. Above that, a node's
/// splats are its children's merged on a [grid]³ lattice over its box, so a
/// node holds at most `grid³` — at the defaults, 512 standing in for up to
/// 4096 below, an eighth a level.
SplatOctree buildSplatOctree(
  SplatCloud cloud, {
  int leafCapacity = 512,
  int grid = 8,
}) {
  if (leafCapacity < 1 || grid < 1) {
    throw ArgumentError('leafCapacity and grid must be at least 1');
  }
  final n = cloud.count;
  final c = cloud.centers;
  final lo = Vector3.all(double.infinity);
  final hi = Vector3.all(double.negativeInfinity);
  for (var i = 0; i < n; i++) {
    final p = Vector3(c[i * 3], c[i * 3 + 1], c[i * 3 + 2]);
    Vector3.min(lo, p, lo);
    Vector3.max(hi, p, hi);
  }
  final center = n == 0 ? Vector3.zero() : (lo + hi) * 0.5;
  final half = n == 0
      ? 0.0
      : math.max(math.max(hi.x - lo.x, hi.y - lo.y), hi.z - lo.z) * 0.5;

  final root = _build(
    cloud,
    Int32List.fromList(List<int>.generate(n, (int i) => i)),
    center,
    half,
    0,
    leafCapacity,
    grid,
  );

  // Breadth first, so each node's children are contiguous and the coarse
  // pages come first in the file.
  final order = <_Built>[root];
  for (var k = 0; k < order.length; k++) {
    order.addAll(order[k].children);
  }
  final firstChild = <_Built, int>{};
  var next = 1;
  for (final b in order) {
    firstChild[b] = next;
    next += b.children.length;
  }
  // Where each page will sit in the file `encodeSplatOctree` writes: after
  // the header and the table, one after another in this same order.
  final pageOffsets = <int>[
    splatOctreeHeaderBytes + order.length * splatOctreeNodeBytes,
  ];
  for (final b in order) {
    pageOffsets.add(pageOffsets.last + b.splats.count * splatPageBytesPerSplat);
  }
  return SplatOctree(<SplatOctreeNode>[
    for (final (k, b) in order.indexed)
      SplatOctreeNode(
        x: b.center.x,
        y: b.center.y,
        z: b.center.z,
        radius: b.half * math.sqrt(3),
        firstChild: b.children.isEmpty ? 0 : firstChild[b]!,
        childCount: b.children.length,
        splatCount: b.splats.count,
        pageOffset: pageOffsets[k],
        splats: b.splats,
      ),
  ]);
}

/// A node while the tree is being built: its box, its splats, its children.
final class _Built {
  _Built(this.center, this.half, this.splats, this.children);
  final Vector3 center;

  /// Half the box's side, in metres.
  final double half;
  final SplatCloud splats;
  final List<_Built> children;
}

/// Deep enough that a box has shrunk below any float's precision at any
/// sensible scale; a cloud of coincident splats stops here as one fat leaf
/// rather than recursing forever.
const int _kMaxDepth = 21;

_Built _build(
  SplatCloud cloud,
  Int32List indices,
  Vector3 center,
  double half,
  int depth,
  int leafCapacity,
  int grid,
) {
  if (indices.length <= leafCapacity || depth >= _kMaxDepth || half <= 0) {
    return _Built(center, half, _subset(cloud, indices), const <_Built>[]);
  }
  final c = cloud.centers;
  final octants = List<List<int>>.generate(8, (_) => <int>[]);
  for (final i in indices) {
    final o =
        (c[i * 3] >= center.x ? 1 : 0) |
        (c[i * 3 + 1] >= center.y ? 2 : 0) |
        (c[i * 3 + 2] >= center.z ? 4 : 0);
    octants[o].add(i);
  }
  final quarter = half * 0.5;
  final children = <_Built>[
    for (var o = 0; o < 8; o++)
      if (octants[o].isNotEmpty)
        _build(
          cloud,
          Int32List.fromList(octants[o]),
          center +
              Vector3(
                (o & 1) != 0 ? quarter : -quarter,
                (o & 2) != 0 ? quarter : -quarter,
                (o & 4) != 0 ? quarter : -quarter,
              ),
          quarter,
          depth + 1,
          leafCapacity,
          grid,
        ),
  ];
  return _Built(
    center,
    half,
    mergeSplats(
      <SplatCloud>[for (final child in children) child.splats],
      center: center,
      half: half,
      grid: grid,
    ),
    children,
  );
}

SplatCloud _subset(SplatCloud cloud, Int32List indices) {
  final n = indices.length;
  final centers = Float32List(n * 3);
  final colors = Float32List(n * 4);
  final scales = Float32List(n * 3);
  final rotations = Float32List(n * 4);
  for (var k = 0; k < n; k++) {
    final i = indices[k];
    centers.setRange(k * 3, k * 3 + 3, cloud.centers, i * 3);
    colors.setRange(k * 4, k * 4 + 4, cloud.colors, i * 4);
    scales.setRange(k * 3, k * 3 + 3, cloud.scales, i * 3);
    rotations.setRange(k * 4, k * 4 + 4, cloud.rotations, i * 4);
  }
  return SplatCloud(
    centers: centers,
    colors: colors,
    scales: scales,
    rotations: rotations,
  );
}

/// Floats a merge cell accumulates: weight, weighted mean (3), weighted
/// second moment (6), weighted colour (3), opacity × footprint.
const int _kCell = 14;

/// The splats of [parts] merged into at most `grid³`, one per occupied cell
/// of a [grid]³ lattice over the cube of half-size [half] about [center].
///
/// Each merged splat is the moment match of its cell: the mean and
/// covariance of the cell's Gaussians weighted by opacity times footprint,
/// the footprint being `(s₀s₁s₂)^⅔`, which is what a splat covers on screen
/// averaged over the directions it could be seen from. Its colour is the
/// same weighted mean, and its opacity is the cell's summed opacity-footprint
/// spread over the merged splat's own footprint, capped at one — so a lone
/// splat merges into itself, and many small faint ones into one larger one
/// that is as opaque as they were together.
SplatCloud mergeSplats(
  List<SplatCloud> parts, {
  required Vector3 center,
  required double half,
  required int grid,
}) {
  final cells = Float64List(grid * grid * grid * _kCell);
  final occupied = <int>[];
  final covariance = Float32List(6);
  final scale = half > 0 ? grid / (2 * half) : 0.0;
  int cellOf(double v, double at) =>
      ((v - at + half) * scale).floor().clamp(0, grid - 1);

  for (final part in parts) {
    for (var i = 0; i < part.count; i++) {
      final px = part.centers[i * 3] - center.x;
      final py = part.centers[i * 3 + 1] - center.y;
      final pz = part.centers[i * 3 + 2] - center.z;
      final cell =
          (cellOf(px, 0) * grid + cellOf(py, 0)) * grid + cellOf(pz, 0);
      final at = cell * _kCell;
      final footprint = math
          .pow(
            part.scales[i * 3] *
                part.scales[i * 3 + 1] *
                part.scales[i * 3 + 2],
            2 / 3,
          )
          .toDouble();
      final alpha = part.colors[i * 4 + 3];
      // Never zero, so a cell of fully transparent splats still has a place
      // and a shape — it merges into a transparent splat, not a division by
      // nothing.
      final w = math.max(alpha, 1e-6) * footprint + 1e-30;
      if (cells[at] == 0) occupied.add(cell);
      part.covarianceOf(i, covariance);
      cells[at] += w;
      cells[at + 1] += w * px;
      cells[at + 2] += w * py;
      cells[at + 3] += w * pz;
      cells[at + 4] += w * (covariance[0] + px * px);
      cells[at + 5] += w * (covariance[1] + px * py);
      cells[at + 6] += w * (covariance[2] + px * pz);
      cells[at + 7] += w * (covariance[3] + py * py);
      cells[at + 8] += w * (covariance[4] + py * pz);
      cells[at + 9] += w * (covariance[5] + pz * pz);
      cells[at + 10] += w * part.colors[i * 4];
      cells[at + 11] += w * part.colors[i * 4 + 1];
      cells[at + 12] += w * part.colors[i * 4 + 2];
      cells[at + 13] += alpha * footprint;
    }
  }

  occupied.sort();
  final n = occupied.length;
  final centers = Float32List(n * 3);
  final colors = Float32List(n * 4);
  final scales = Float32List(n * 3);
  final rotations = Float32List(n * 4);
  final sigma = Float64List(9);
  for (var k = 0; k < n; k++) {
    final at = occupied[k] * _kCell;
    final w = cells[at];
    final mx = cells[at + 1] / w;
    final my = cells[at + 2] / w;
    final mz = cells[at + 3] / w;
    // Second moment about the origin minus the mean's outer product: the
    // covariance about the mean. Computed about the node's centre, not the
    // world's, so the subtraction does not cancel away the precision.
    final xx = cells[at + 4] / w - mx * mx;
    final xy = cells[at + 5] / w - mx * my;
    final xz = cells[at + 6] / w - mx * mz;
    final yy = cells[at + 7] / w - my * my;
    final yz = cells[at + 8] / w - my * mz;
    final zz = cells[at + 9] / w - mz * mz;
    sigma
      ..[0] = xx
      ..[1] = xy
      ..[2] = xz
      ..[3] = xy
      ..[4] = yy
      ..[5] = yz
      ..[6] = xz
      ..[7] = yz
      ..[8] = zz;
    final (values, vectors) = symmetricEigen3(sigma);

    centers[k * 3] = mx + center.x;
    centers[k * 3 + 1] = my + center.y;
    centers[k * 3 + 2] = mz + center.z;
    var footprint = 1.0;
    for (var a = 0; a < 3; a++) {
      final s = math.sqrt(math.max(values[a], 1e-24));
      scales[k * 3 + a] = s;
      footprint *= s;
    }
    footprint = math.pow(footprint, 2 / 3).toDouble();
    final q = Quaternion.fromRotation(
      Matrix3(
        vectors[0],
        vectors[1],
        vectors[2], //
        vectors[3],
        vectors[4],
        vectors[5], //
        vectors[6],
        vectors[7],
        vectors[8],
      ),
    )..normalize();
    rotations
      ..[k * 4] = q.x
      ..[k * 4 + 1] = q.y
      ..[k * 4 + 2] = q.z
      ..[k * 4 + 3] = q.w;
    colors
      ..[k * 4] = cells[at + 10] / w
      ..[k * 4 + 1] = cells[at + 11] / w
      ..[k * 4 + 2] = cells[at + 12] / w
      ..[k * 4 + 3] = math.min(1.0, cells[at + 13] / footprint);
  }
  return SplatCloud(
    centers: centers,
    colors: colors,
    scales: scales,
    rotations: rotations,
  );
}

/// The eigenvalues and unit eigenvectors of the symmetric 3×3 [m] (row
/// major), by cyclic Jacobi rotations.
///
/// The vectors come back as the columns of a column-major 3×3 whose
/// determinant is +1 — a rotation, which is what a splat's axes have to be.
/// Jacobi rather than a closed form because a covariance is often nearly
/// degenerate (a flat splat, a line of them), which is exactly where the
/// cubic's closed form loses its digits and the rotations do not.
(Float64List, Float64List) symmetricEigen3(Float64List m) {
  final a = Float64List.fromList(m);
  final v = Float64List(9)
    ..[0] = 1
    ..[4] = 1
    ..[8] = 1; // row major while iterating
  for (var sweep = 0; sweep < 32; sweep++) {
    final off = a[1] * a[1] + a[2] * a[2] + a[5] * a[5];
    final diagonal = a[0] * a[0] + a[4] * a[4] + a[8] * a[8];
    if (off <= 1e-30 * diagonal || off == 0) break;
    for (final (p, q) in const <(int, int)>[(0, 1), (0, 2), (1, 2)]) {
      final apq = a[p * 3 + q];
      if (apq == 0) continue;
      final theta = (a[q * 3 + q] - a[p * 3 + p]) / (2 * apq);
      final t =
          (theta >= 0 ? 1.0 : -1.0) /
          (theta.abs() + math.sqrt(theta * theta + 1));
      final c = 1 / math.sqrt(t * t + 1);
      final s = t * c;
      // A ← Jᵀ A J, with J the rotation in the (p, q) plane.
      for (var k = 0; k < 3; k++) {
        final akp = a[k * 3 + p], akq = a[k * 3 + q];
        a[k * 3 + p] = c * akp - s * akq;
        a[k * 3 + q] = s * akp + c * akq;
      }
      for (var k = 0; k < 3; k++) {
        final apk = a[p * 3 + k], aqk = a[q * 3 + k];
        a[p * 3 + k] = c * apk - s * aqk;
        a[q * 3 + k] = s * apk + c * aqk;
      }
      for (var k = 0; k < 3; k++) {
        final vkp = v[k * 3 + p], vkq = v[k * 3 + q];
        v[k * 3 + p] = c * vkp - s * vkq;
        v[k * 3 + q] = s * vkp + c * vkq;
      }
    }
  }
  final values = Float64List.fromList(<double>[a[0], a[4], a[8]]);
  // Columns of the row-major V are the eigenvectors; laid out column major.
  final vectors = Float64List(9);
  for (var col = 0; col < 3; col++) {
    for (var row = 0; row < 3; row++) {
      vectors[col * 3 + row] = v[row * 3 + col];
    }
  }
  final det =
      vectors[0] * (vectors[4] * vectors[8] - vectors[7] * vectors[5]) -
      vectors[3] * (vectors[1] * vectors[8] - vectors[7] * vectors[2]) +
      vectors[6] * (vectors[1] * vectors[5] - vectors[4] * vectors[2]);
  if (det < 0) {
    for (var row = 0; row < 3; row++) {
      vectors[6 + row] = -vectors[6 + row];
    }
  }
  return (values, vectors);
}

// --- The file ------------------------------------------------------------

/// `F3DS` at the head of a paged splat tree.
const int _kMagic = 0x53443346;

/// The tree file's format version.
const int splatOctreeVersion = 1;

/// `.f3dsplat` in the format registry.
const FormatSpec f3dsplatFormat = FormatSpec(
  id: 'f3d.splat',
  version: splatOctreeVersion,
  suffixes: <String>['.f3dsplat'],
  fixture: 'test/fixtures/v<N>/one.f3dsplat',
  enveloped: false,
  magic: <int>[0x46, 0x33, 0x44, 0x53],
);

/// Bytes before the node table.
const int splatOctreeHeaderBytes = 32;

/// Bytes a node takes in the table.
const int splatOctreeNodeBytes = 36;

/// Bytes a splat takes in a page: centre, colour, scale, rotation as float32.
const int splatPageBytesPerSplat = 56;

/// The file suffix `flutter3d_build convert` writes a splat tree to.
const String splatOctreeExtension = '.f3dsplat';

/// Thrown when bytes are not a splat tree this can read.
final class SplatOctreeException extends Flutter3dFormatException {
  const SplatOctreeException(this.message);
  @override
  final String message;
  @override
  String toString() => 'SplatOctreeException: $message';
}

/// [tree] as a file: header, node table, then every page breadth first.
/// Every node must be loaded.
Uint8List encodeSplatOctree(SplatOctree tree) {
  final nodes = tree.nodes;
  final pagesAt = splatOctreeHeaderBytes + nodes.length * splatOctreeNodeBytes;
  final total = nodes.fold(
    pagesAt,
    (int sum, SplatOctreeNode n) => sum + n.splatCount * splatPageBytesPerSplat,
  );
  final out = ByteData(total)
    ..setUint32(0, _kMagic, Endian.little)
    ..setUint32(4, splatOctreeVersion, Endian.little)
    ..setUint32(8, nodes.length, Endian.little)
    ..setUint32(12, tree.leafSplatCount, Endian.little);

  var page = pagesAt;
  for (var k = 0; k < nodes.length; k++) {
    final node = nodes[k];
    final splats = node.splats;
    if (splats == null) {
      throw StateError('node $k has no splats to write');
    }
    final at = splatOctreeHeaderBytes + k * splatOctreeNodeBytes;
    out
      ..setFloat32(at, node.x, Endian.little)
      ..setFloat32(at + 4, node.y, Endian.little)
      ..setFloat32(at + 8, node.z, Endian.little)
      ..setFloat32(at + 12, node.radius, Endian.little)
      ..setUint32(at + 16, node.firstChild, Endian.little)
      ..setUint32(at + 20, node.childCount, Endian.little)
      ..setUint32(at + 24, node.splatCount, Endian.little)
      ..setUint32(at + 28, page % 0x100000000, Endian.little)
      ..setUint32(at + 32, page ~/ 0x100000000, Endian.little);
    page = _writePage(out, page, splats);
  }
  return out.buffer.asUint8List();
}

int _writePage(ByteData out, int at, SplatCloud splats) {
  var p = at;
  for (final array in <Float32List>[
    splats.centers,
    splats.colors,
    splats.scales,
    splats.rotations,
  ]) {
    for (final v in array) {
      out.setFloat32(p, v, Endian.little);
      p += 4;
    }
  }
  return p;
}

/// How many bytes of the file [parseSplatOctreeIndex] needs, given its
/// first [splatOctreeHeaderBytes].
int splatOctreeIndexBytes(Uint8List header) {
  final nodeCount = _readHeader(header);
  return splatOctreeHeaderBytes + nodeCount * splatOctreeNodeBytes;
}

int _readHeader(Uint8List bytes) {
  if (bytes.length < splatOctreeHeaderBytes) {
    throw const SplatOctreeException('shorter than a splat tree header');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _kMagic) {
    throw const SplatOctreeException('no F3DS magic: not a splat tree');
  }
  // Every version up to this build's; only the future is refused (decision 8
  // of `tasks/1.0-stability.md`). A later layout reads an older node record
  // the older way in `_node`. Mutation: put back `!=` and bump the constant,
  // and `test/fixtures/v1/one.f3dsplat` stops opening.
  final version = data.getUint32(4, Endian.little);
  if (version < 1 || version > splatOctreeVersion) {
    throw SplatOctreeException(
      'splat tree version $version; this reads up to $splatOctreeVersion. '
      'Update flutter3d to open it',
    );
  }
  return data.getUint32(8, Endian.little);
}

/// The tree's nodes out of the header and table, every page still to load.
SplatOctree parseSplatOctreeIndex(Uint8List bytes) {
  final nodeCount = _readHeader(bytes);
  final needed = splatOctreeHeaderBytes + nodeCount * splatOctreeNodeBytes;
  if (bytes.length < needed || nodeCount == 0) {
    throw SplatOctreeException(
      '$nodeCount nodes need a $needed-byte index; got ${bytes.length}',
    );
  }
  final data = ByteData.sublistView(bytes);
  final nodes = <SplatOctreeNode>[
    for (var k = 0; k < nodeCount; k++)
      _node(data, splatOctreeHeaderBytes + k * splatOctreeNodeBytes),
  ];
  for (final (k, node) in nodes.indexed) {
    if (node.childCount > 8 ||
        (node.childCount > 0 &&
            (node.firstChild <= k ||
                node.firstChild + node.childCount > nodeCount))) {
      throw SplatOctreeException('node $k names children outside the tree');
    }
  }
  return SplatOctree(nodes);
}

SplatOctreeNode _node(ByteData d, int at) => SplatOctreeNode(
  x: d.getFloat32(at, Endian.little),
  y: d.getFloat32(at + 4, Endian.little),
  z: d.getFloat32(at + 8, Endian.little),
  radius: d.getFloat32(at + 12, Endian.little),
  firstChild: d.getUint32(at + 16, Endian.little),
  childCount: d.getUint32(at + 20, Endian.little),
  splatCount: d.getUint32(at + 24, Endian.little),
  pageOffset:
      d.getUint32(at + 28, Endian.little) +
      d.getUint32(at + 32, Endian.little) * 0x100000000,
);

/// One node's page, [count] splats, as a cloud.
SplatCloud decodeSplatPage(Uint8List bytes, int count) {
  if (bytes.length < count * splatPageBytesPerSplat) {
    throw SplatOctreeException(
      'a page of $count splats is ${count * splatPageBytesPerSplat} bytes; '
      'got ${bytes.length}',
    );
  }
  final data = ByteData.sublistView(bytes);
  var at = 0;
  Float32List read(int length) {
    final out = Float32List(length);
    for (var i = 0; i < length; i++, at += 4) {
      out[i] = data.getFloat32(at, Endian.little);
    }
    return out;
  }

  return SplatCloud(
    centers: read(count * 3),
    colors: read(count * 4),
    scales: read(count * 3),
    rotations: read(count * 4),
  );
}

/// A whole tree file read at once, every page attached.
SplatOctree parseSplatOctree(Uint8List bytes) {
  final tree = parseSplatOctreeIndex(bytes);
  for (final (k, node) in tree.nodes.indexed) {
    final end = node.pageOffset + node.splatCount * splatPageBytesPerSplat;
    if (end > bytes.length) {
      throw SplatOctreeException('node $k\'s page runs past the end');
    }
    tree.attach(
      k,
      decodeSplatPage(
        Uint8List.sublistView(bytes, node.pageOffset, end),
        node.splatCount,
      ),
    );
  }
  return tree;
}
