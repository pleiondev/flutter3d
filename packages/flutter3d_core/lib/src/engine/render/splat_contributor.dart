/// Drawing a fitted Gaussian cloud — `gfx-80n`.
///
/// **The quads are built on the CPU, and that is this engine's existing
/// answer rather than a shortcut.** A splat reaches the screen as an ellipse,
/// and turning a point into one needs either a geometry stage — flutter_gpu has
/// none — or four vertices carrying the same centre plus a corner index, which
/// is the same bandwidth with a reconstruction on top. `particle.vert`'s own
/// comment made that call for particles; splats reuse that vertex stage exactly,
/// so the whole of the GPU side is one fragment shader.
///
/// **The projection is orthographic about each splat, which is a stated
/// approximation.** The exact screen-space covariance is `J W Σ Wᵀ Jᵀ`, where
/// `J` is the Jacobian of the perspective divide at that splat's depth; this
/// drops `J` and projects the ellipsoid's own axes onto the camera's right and
/// up. The two agree at the middle of the frame and part company toward the
/// corners of a wide one, where a splat should shear slightly and here does
/// not. It is the difference between an ellipse and a slightly wrong ellipse,
/// on something whose whole extent is a few pixels, and it costs two dot
/// products a splat instead of a matrix triple product.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/typed_blocks.dart';
import 'package:vector_math/vector_math.dart';

import '../../formats/splat/splat_cloud.dart';
import '../scene/scene_node.dart';
import 'identity_indices.dart';
import 'pass_contributor.dart';
import 'splat_lod.dart';
import 'splat_sort.dart';

/// How far out the quad reaches, in standard deviations.
///
/// Three, where a Gaussian is under a hundredth of its peak. Further is quads
/// that cost fill rate to add nothing; nearer and the cut-off in `splat.frag`
/// starts clipping something visible, which shows as the quad's own square edge
/// — a field of faint rectangles.
const double kSplatReach = 3.0;

/// Floats per vertex in `VertexLayout.positionColorTexcoord`: xyz, rgba, uv.
const int kSplatFloatsPerVertex = 9;

/// Six vertices a splat: two triangles sharing no vertex between them, drawn
/// through the identity index buffer `MeshOverlay` also reaches for, since
/// this engine has no unindexed draw at all.
const int kSplatVerticesPerSplat = 6;

/// Builds the vertex data for [cloud], back to front, as [camera] sees it.
///
/// Separated from the drawing so that the part with arithmetic in it can be
/// checked without a device — the same split `MeshOverlay` makes between
/// filling a batch and encoding one.
final class SplatQuads {
  SplatQuads(SplatCloud cloud) : _cloud = cloud, lod = null;

  /// Draws a splat tree at [lod]'s budget instead of one fixed cloud: every
  /// time this would sort, the cut is chosen again first and the cut is what
  /// is sorted and drawn — see `splat_lod.dart`.
  SplatQuads.lod(SplatLod this.lod) : _cloud = _noSplats();

  static SplatCloud _noSplats() => SplatCloud(
    centres: Float32List(0),
    colours: Float32List(0),
    scales: Float32List(0),
    rotations: Float32List(0),
  );

  /// The tree and budget this draws from, or null for a fixed cloud.
  final SplatLod? lod;

  /// What is drawn: the cloud given, or the last cut [lod] chose.
  SplatCloud get cloud => _cloud;
  SplatCloud _cloud;

  /// The tree's page version and the budget at the last cut: either moving
  /// means a finer or coarser cut is on offer, so the next [build] sorts.
  int _sortedPageVersion = -1;
  int _sortedBudget = -1;

  /// How far the eye may travel before the cloud is sorted again, as a
  /// fraction of the distance between its nearest and farthest splat at the
  /// last sort.
  ///
  /// **Why a fraction of the cloud's own depth.** A move of `δ` changes the
  /// distance between the eye and any splat by at most `δ`, so two splats can
  /// only swap places if they were within `2δ` of each other; measured
  /// against the depth the sort quantised over, the default of 0.2 % is a
  /// few hundred of the sixteen-bit key's 65 536 steps — splats that close
  /// together are covering the same pixels at nearly the same depth, and
  /// which lands on top of the other is not something a viewer can see. Zero
  /// sorts on every move, the behaviour before this existed.
  double resortFraction = 0.002;

  final SplatSorter _sorter = SplatSorter();

  /// Where the eye was, and where the cloud was placed, at the last sort.
  /// Null until the first, and after [invalidateSort].
  Vector3? _sortedEye;
  final Float64List _sortedModel = Float64List(16);
  bool _sortedWithModel = false;

  /// How many times [build] has sorted. For the tests that hold it to not
  /// sorting on every frame.
  int get sorts => _sorts;
  int _sorts = 0;

  /// The vertex floats, refilled in place every time the camera moves.
  Float32List _vertices = Float32List(0);
  final Float32List _covariance = Float32List(6);

  /// How many vertices [vertices] currently holds.
  int vertexCount = 0;

  Float32List get vertices => _vertices;

  /// Makes the next [build] sort, however little the eye moved — for a
  /// caller that has edited [cloud]'s centres in place.
  void invalidateSort() => _sortedEye = null;

  /// Fills the buffer for a camera at [eye] whose axes are [right] and [up],
  /// with the cloud placed in the world by [model] when it is given.
  ///
  /// Both axes are expected orthonormal, which is what a camera's own basis
  /// is. The camera's forward axis is not needed: the order is by distance
  /// from [eye], which a turn does not change — see `splat_sort.dart`.
  ///
  /// The quads are rebuilt every call, since their axes follow the camera's
  /// own; the sort, which is most of the cost, runs only when the eye has
  /// moved further than [resortFraction] allows or [model] has changed.
  void build({
    required Vector3 eye,
    required Vector3 right,
    required Vector3 up,
    Matrix4? model,
  }) {
    if (_needsSort(eye, model)) {
      final lod = this.lod;
      if (lod != null) {
        // The cut is chosen by distance in the tree's own space, so the eye
        // is taken there once rather than every node taken to the world.
        _cloud = lod.choose(
          model == null ? eye : Matrix4.inverted(model).transformed3(eye),
        );
        _sortedPageVersion = lod.tree.pageVersion;
        _sortedBudget = lod.budget;
      }
      _sorter.sort(cloud, eye, model: model);
      _sorts++;
      _sortedEye = eye.clone();
      _sortedWithModel = model != null;
      if (model != null) _sortedModel.setAll(0, model.storage);
    }
    final order = _sorter.order;
    final count = cloud.count;
    final needed = count * kSplatVerticesPerSplat * kSplatFloatsPerVertex;
    if (_vertices.length < needed) _vertices = Float32List(needed);

    // The camera's axes as the cloud's own space sees them, when it has one.
    // The ellipse is `[r; u] M Σ Mᵀ [r; u]ᵀ` for a cloud placed by `M`, and
    // that is the unplaced formula with `Mᵀr` and `Mᵀu` in place of `r` and
    // `u` — so the placement costs six dot products once, not a matrix
    // product per splat. The quad's own corners stay in world space, built
    // from the world `r` and `u` below.
    final m = model?.storage;
    final rx = m == null
        ? right.x
        : m[0] * right.x + m[1] * right.y + m[2] * right.z;
    final ry = m == null
        ? right.y
        : m[4] * right.x + m[5] * right.y + m[6] * right.z;
    final rz = m == null
        ? right.z
        : m[8] * right.x + m[9] * right.y + m[10] * right.z;
    final ux = m == null ? up.x : m[0] * up.x + m[1] * up.y + m[2] * up.z;
    final uy = m == null ? up.y : m[4] * up.x + m[5] * up.y + m[6] * up.z;
    final uz = m == null ? up.z : m[8] * up.x + m[9] * up.y + m[10] * up.z;
    final wrx = right.x, wry = right.y, wrz = right.z;
    final wux = up.x, wuy = up.y, wuz = up.z;

    var at = 0;
    for (var n = 0; n < count; n++) {
      final i = order[n];
      cloud.covarianceOf(i, _covariance);

      // The 3D covariance seen from the camera, restricted to the plane of the
      // glass: `[right; up] Σ [right; up]ᵀ`, which is the 2×2 the ellipse comes
      // from. Written out rather than multiplied as matrices because two of the
      // three rows of the result are never used.
      final sxx = _covariance[0], sxy = _covariance[1], sxz = _covariance[2];
      final syy = _covariance[3], syz = _covariance[4], szz = _covariance[5];

      // Σ·right and Σ·up.
      final arx = sxx * rx + sxy * ry + sxz * rz;
      final ary = sxy * rx + syy * ry + syz * rz;
      final arz = sxz * rx + syz * ry + szz * rz;
      final aux = sxx * ux + sxy * uy + sxz * uz;
      final auy = sxy * ux + syy * uy + syz * uz;
      final auz = sxz * ux + syz * uy + szz * uz;

      final a = rx * arx + ry * ary + rz * arz;
      final b = rx * aux + ry * auy + rz * auz;
      final d = ux * aux + uy * auy + uz * auz;

      // The 2×2's eigenvectors and the standard deviations along them. A
      // closed form rather than an iteration: for a symmetric 2×2 the whole
      // decomposition is a half-sum, a half-difference and one square root.
      final half = 0.5 * (a + d);
      final spread = math.sqrt(math.max(0.25 * (a - d) * (a - d) + b * b, 0.0));
      final major = math.max(half + spread, 0.0);
      final minor = math.max(half - spread, 0.0);

      // The major axis, in the camera's own 2D frame. When the off-diagonal is
      // nothing the ellipse is already axis-aligned and the general formula
      // divides by zero, so that case is taken directly.
      final double e1x, e1y;
      if (b.abs() < 1e-12) {
        e1x = a >= d ? 1.0 : 0.0;
        e1y = a >= d ? 0.0 : 1.0;
      } else {
        final vx = major - d;
        final length = math.sqrt(vx * vx + b * b);
        e1x = vx / length;
        e1y = b / length;
      }

      final sigma1 = math.sqrt(major) * kSplatReach;
      final sigma2 = math.sqrt(minor) * kSplatReach;

      // The two quad axes, back in world space.
      final axX = (e1x * sigma1) * wrx + (e1y * sigma1) * wux;
      final axY = (e1x * sigma1) * wry + (e1y * sigma1) * wuy;
      final axZ = (e1x * sigma1) * wrz + (e1y * sigma1) * wuz;
      final ayX = (-e1y * sigma2) * wrx + (e1x * sigma2) * wux;
      final ayY = (-e1y * sigma2) * wry + (e1x * sigma2) * wuy;
      final ayZ = (-e1y * sigma2) * wrz + (e1x * sigma2) * wuz;

      final lx = cloud.centres[i * 3];
      final ly = cloud.centres[i * 3 + 1];
      final lz = cloud.centres[i * 3 + 2];
      final cx = m == null ? lx : m[0] * lx + m[4] * ly + m[8] * lz + m[12];
      final cy = m == null ? ly : m[1] * lx + m[5] * ly + m[9] * lz + m[13];
      final cz = m == null ? lz : m[2] * lx + m[6] * ly + m[10] * lz + m[14];
      final r = cloud.colours[i * 4];
      final g = cloud.colours[i * 4 + 1];
      final bl = cloud.colours[i * 4 + 2];
      final alpha = cloud.colours[i * 4 + 3];

      // Two triangles over the four corners. The texture coordinate is the
      // corner's position in the Gaussian's own frame, in standard deviations,
      // which is what `splat.frag` evaluates its falloff from — so the corners
      // carry ±[kSplatReach] rather than the zero-to-one a texture would want.
      void corner(double sx, double sy) {
        _vertices[at] = cx + axX * sx + ayX * sy;
        _vertices[at + 1] = cy + axY * sx + ayY * sy;
        _vertices[at + 2] = cz + axZ * sx + ayZ * sy;
        _vertices[at + 3] = r;
        _vertices[at + 4] = g;
        _vertices[at + 5] = bl;
        _vertices[at + 6] = alpha;
        _vertices[at + 7] = sx * kSplatReach;
        _vertices[at + 8] = sy * kSplatReach;
        at += kSplatFloatsPerVertex;
      }

      corner(-1, -1);
      corner(1, -1);
      corner(1, 1);
      corner(-1, -1);
      corner(1, 1);
      corner(-1, 1);
    }

    vertexCount = count * kSplatVerticesPerSplat;
  }

  bool _needsSort(Vector3 eye, Matrix4? model) {
    final last = _sortedEye;
    if (last == null) return true;
    final lod = this.lod;
    if (lod != null &&
        (lod.tree.pageVersion != _sortedPageVersion ||
            lod.budget != _sortedBudget)) {
      return true;
    }
    if ((model != null) != _sortedWithModel) return true;
    if (model != null) {
      final storage = model.storage;
      for (var k = 0; k < 16; k++) {
        if (storage[k] != _sortedModel[k]) return true;
      }
    }
    return last.distanceTo(eye) > resortFraction * _sorter.lastRange;
  }
}

/// Draws a cloud into the scene pass.
final class SplatContributor extends PassContributor {
  final ParticleInfoBlock _particleInfo = ParticleInfoBlock();

  SplatContributor(SplatCloud cloud, {this.node}) : quads = SplatQuads(cloud);

  /// Draws a splat tree at [lod]'s budget — the cut is chosen again each
  /// time the cloud is re-sorted, and pages [lod] asks for are drawn as they
  /// arrive. Off unless asked for: the plain constructor draws every splat.
  SplatContributor.lod(SplatLod lod, {this.node}) : quads = SplatQuads.lod(lod);

  /// What is drawn: the cloud given, or the cut last chosen from a tree.
  SplatCloud get cloud => quads.cloud;
  final SplatQuads quads;

  /// The node the cloud hangs from, when it has one: its world matrix places
  /// the cloud, and hiding it hides the cloud. Null draws [cloud] in world
  /// units as stored, which is what a PLY capture is.
  ///
  /// A glTF splat primitive belongs to the node that instantiates its mesh —
  /// `ModelSplat.node` names it — and the node's scale and rotation reach
  /// each splat's covariance, not only its centre, as the extension asks.
  final SceneNode? node;

  PipelineHandle? _pipeline;

  /// The index sequence 0, 1, 2, … every draw in this engine needs — see
  /// `MeshOverlay._identityIndices`, which keeps the same sequence for the
  /// same reason: `CommandEncoder.draw` has no unindexed path, and a draw
  /// left with a vertex buffer and no index buffer bound draws nothing, with
  /// no refusal to say so.
  final IdentityIndices _identityIndices = IdentityIndices();

  /// After the opaque scene, because every splat is translucent and has to
  /// land on top of whatever solid geometry is behind it.
  @override
  int get order => 100;

  @override
  bool get isActive =>
      // A tree has drawn nothing before its first cut, which is made in
      // encode; asking the cut would keep it from ever being made.
      (quads.lod != null || cloud.count > 0) &&
      (node?.visibleInHierarchy ?? true);

  @override
  void encode(ContributorFrame frame) {
    final viewProjection = frame.viewProjection;
    final view = frame.view;
    if (viewProjection == null || view == null) return;

    // Looked up by name from the frame's own bundle, the arrangement
    // `ParticleContributor` uses: the vertex stage is shared with particles and
    // a caller should not have to know that, nor that the fragment stage is
    // called `Splat` and not `SplatFragment`. A missing name draws nothing
    // rather than throwing, because a backend whose bundle predates this row is
    // a backend that should still start.
    final vertexShader = frame.device.shaders['ParticleVertex'];
    final fragmentShader = frame.device.shaders['Splat'];
    if (vertexShader == null || fragmentShader == null) return;

    // The camera's own basis, out of its world matrix: local +X is right and
    // +Y is up. Taken here rather than asked of the node, because
    // `CameraNode` publishes only the forward axis — which the quads do not
    // need, since the order is by distance.
    final camera = view.camera;
    final m = camera.worldMatrix.storage;
    final right = Vector3(m[0], m[1], m[2])..normalize();
    final up = Vector3(m[4], m[5], m[6])..normalize();
    final eye = camera.readWorldPosition();

    quads.build(eye: eye, right: right, up: up, model: node?.worldMatrix);
    if (quads.vertexCount == 0) return;

    frame.encoder
      ..clearBindings()
      ..bindPipeline(
        _pipeline ??= frame.device.createPipeline(vertexShader, fragmentShader),
      );
    frame.state.invalidatePipeline();

    final bytes = ByteData.view(
      quads.vertices.buffer,
      quads.vertices.offsetInBytes,
      quads.vertexCount * kSplatFloatsPerVertex * 4,
    );

    _particleInfo.viewProjection.setAll(0, viewProjection.storage);
    frame.encoder
      ..setState(_kSplatState)
      ..bindVertexData(bytes, quads.vertexCount)
      ..bindIndexBuffer(
        _identityIndices.view(frame.device, quads.vertexCount),
        IndexType.int32,
        quads.vertexCount,
      )
      ..bindBlock(vertexShader, _particleInfo)
      ..draw();
    frame.state.drawCalls++;
  }

  /// **Blended and depth tested, but not depth written.** A splat is
  /// translucent everywhere, so writing its depth would hide the splats behind
  /// it — which is the whole of what back-to-front ordering exists to get
  /// right. Testing against what the opaque pass left is still wanted: a cloud
  /// behind a wall should be behind it.
  ///
  /// [BlendState.alphaBlend] because the fragment stage writes premultiplied
  /// colour — that state's source factor is `one` and not `sourceAlpha`, which
  /// is what composites a stack of translucent layers correctly in one pass.
  static const PassState _kSplatState = PassState(
    primitiveType: PrimitiveType.triangle,
    polygonMode: PolygonMode.fill,
    cullMode: CullMode.none,
    blend: BlendState.alphaBlend,
    depthWrite: false,
  );
}
