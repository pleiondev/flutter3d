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
/// **The ellipse is the perspective one, `J W Σ Wᵀ Jᵀ`, drawn in the plane
/// through the splat parallel to the glass.** `J` is the Jacobian of the
/// perspective divide at the splat's centre. A plane at constant depth `z`
/// reaches the screen at one uniform scale, `f / z`, so the quad can stay in
/// world units there and `J`'s two rows reduce to the camera's right and up
/// each leaned along the view axis by the splat's offset from it:
/// `r − (x/z)·forward` and `u − (y/z)·forward`. Leaving the lean out — the
/// covariance projected onto right and up alone — is exact at the middle of
/// the frame and loses everything a splat holds along the view ray toward
/// the edges, which is most of a ground disc seen at a grazing angle.
///
/// **Every footprint is widened by 0.3 px² on the screen**, the low-pass
/// filter of the EWA splatting the method comes from, which the captures
/// were trained with and so have in their look: a thin or distant splat
/// keeps at least about half a pixel of standard deviation rather than
/// eroding to nothing, or to a zero-width quad when seen edge on.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/typed_blocks.dart';
import 'package:vector_math/vector_math.dart';

import '../../formats/splat/splat_cloud.dart';
import '../scene/scene_node.dart';
import 'engine_tables.dart';
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

/// The screen-space low-pass filter every splat's footprint is widened by, in
/// pixels squared: the variance a Gaussian at least one pixel across has.
const double kSplatLowPass = 0.3;

/// How far off the view axis the perspective lean is taken, as a multiple of
/// the half field of view: a splat centred beyond the frame's edge is leaned
/// as if it sat at 1.3 times the edge, so one far off to the side and close
/// to the eye does not become a streak across the whole screen.
const double kSplatLeanLimit = 1.3;

/// What [SplatQuads.build] needs of a camera beyond its right and up axes:
/// its view axis, and how the projection turns depth into pixels.
///
/// Read out of the projection matrix rather than the camera's settings, so
/// that whatever matrix the frame is actually drawn with — jittered,
/// orthographic, handed in whole by an application — is the one the ellipses
/// follow.
final class SplatLens {
  const SplatLens({
    required this.forward,
    required this.focal,
    this.depthWeight = 1.0,
    this.depthOffset = 0.0,
    this.tanHalfWidth = 1.0,
    this.tanHalfHeight = 1.0,
  });

  /// The lens of [projection], drawn into a viewport [viewportHeight] pixels
  /// tall, looking along [forward].
  factory SplatLens.of(
    Matrix4 projection,
    Vector3 forward,
    double viewportHeight,
  ) {
    final p = projection.storage;
    return SplatLens(
      forward: forward,
      focal: 0.5 * p[5] * viewportHeight,
      // Clip w is `p[11]·z + p[15]` of an eye-space z, and the depth along
      // [forward] is `−z`: one for a perspective divide, nought for an
      // orthographic one, whose `w` is one everywhere.
      depthWeight: -p[11],
      depthOffset: p[15],
      tanHalfWidth: p[0] != 0.0 ? 1.0 / p[0].abs() : 1.0,
      tanHalfHeight: p[5] != 0.0 ? 1.0 / p[5].abs() : 1.0,
    );
  }

  /// The camera's view axis, unit length, in world space.
  final Vector3 forward;

  /// Pixels per unit of `x / w` on the screen: half the viewport's height
  /// times the projection's vertical scale.
  final double focal;

  /// Clip `w` as `depthWeight · depth + depthOffset`, depth measured along
  /// [forward]: `(1, 0)` for a perspective projection, `(0, 1)` for an
  /// orthographic one.
  final double depthWeight;
  final double depthOffset;

  /// The tangents of the half fields of view, which bound the lean.
  final double tanHalfWidth;
  final double tanHalfHeight;
}

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
  ///
  /// With [sorted] false there is no sort at all and the quads come out in
  /// the cloud's own order — `N5`'s hashed splats, which the depth test
  /// orders. The last sort is kept, so going back to sorting re-sorts only if
  /// the eye has moved since.
  ///
  /// [lens] is the rest of the camera: with it each ellipse is the
  /// perspective one and is widened by [kSplatLowPass] on the screen, which
  /// is how [SplatContributor] always builds. Without it the covariance is
  /// projected onto [right] and [up] alone and nothing is added — the exact
  /// ellipse on the view axis, and a quad whose size is the splat's own, for
  /// a caller with no projection to hand.
  void build({
    required Vector3 eye,
    required Vector3 right,
    required Vector3 up,
    Matrix4? model,
    bool sorted = true,
    SplatLens? lens,
  }) {
    // A tree's cut is chosen where the sort runs, so a hashed build still
    // sorts when the cut moves: the order and the cut have to agree.
    if ((sorted || lod != null) && _needsSort(eye, model)) {
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
    final order = sorted ? _sorter.order : null;
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

    // The view axis, in the world and in the cloud's space as above, when
    // there is a lens to lean the rows of `J` along it.
    final forward = lens?.forward;
    final wfx = forward?.x ?? 0.0;
    final wfy = forward?.y ?? 0.0;
    final wfz = forward?.z ?? 0.0;
    final fx = m == null ? wfx : m[0] * wfx + m[1] * wfy + m[2] * wfz;
    final fy = m == null ? wfy : m[4] * wfx + m[5] * wfy + m[6] * wfz;
    final fz = m == null ? wfz : m[8] * wfx + m[9] * wfy + m[10] * wfz;
    final leanX = lens == null ? 0.0 : kSplatLeanLimit * lens.tanHalfWidth;
    final leanY = lens == null ? 0.0 : kSplatLeanLimit * lens.tanHalfHeight;

    var at = 0;
    for (var n = 0; n < count; n++) {
      final i = order == null ? n : order[n];
      cloud.covarianceOf(i, _covariance);

      final lx = cloud.centres[i * 3];
      final ly = cloud.centres[i * 3 + 1];
      final lz = cloud.centres[i * 3 + 2];
      final cx = m == null ? lx : m[0] * lx + m[4] * ly + m[8] * lz + m[12];
      final cy = m == null ? ly : m[1] * lx + m[5] * ly + m[9] * lz + m[13];
      final cz = m == null ? lz : m[2] * lx + m[6] * ly + m[10] * lz + m[14];

      // Where the splat sits in the camera's frame, and so how far `J`'s rows
      // lean: `x/w` and `y/w` along the view axis, bounded as [kSplatLeanLimit]
      // says, and nothing for an orthographic lens, whose `w` does not move.
      // Its size in pixels is `focal / w` per world unit in the quad's plane.
      final double leanR, leanU, pixel;
      if (lens == null) {
        (leanR, leanU, pixel) = (0.0, 0.0, 0.0);
      } else {
        final tx = (cx - eye.x) * wrx + (cy - eye.y) * wry + (cz - eye.z) * wrz;
        final ty = (cx - eye.x) * wux + (cy - eye.y) * wuy + (cz - eye.z) * wuz;
        final tz = (cx - eye.x) * wfx + (cy - eye.y) * wfy + (cz - eye.z) * wfz;
        final w = lens.depthWeight * tz + lens.depthOffset;
        // Behind the eye nothing is drawn, and the divide means nothing.
        final ahead = w > 1e-6;
        leanR = ahead
            ? lens.depthWeight * (tx / w).clamp(-leanX, leanX).toDouble()
            : 0.0;
        leanU = ahead
            ? lens.depthWeight * (ty / w).clamp(-leanY, leanY).toDouble()
            : 0.0;
        pixel = ahead && lens.focal > 0.0 ? w / lens.focal : 0.0;
      }

      // The rows of `J`, rescaled to the quad's plane: right and up, each
      // leaned along the view axis by the splat's offset from it.
      final jrx = rx - leanR * fx, jry = ry - leanR * fy, jrz = rz - leanR * fz;
      final jux = ux - leanU * fx, juy = uy - leanU * fy, juz = uz - leanU * fz;

      // The 3D covariance seen from the camera: `J Σ Jᵀ`, the 2×2 the ellipse
      // comes from. Written out rather than multiplied as matrices because
      // two of the three rows of the result are never used.
      final sxx = _covariance[0], sxy = _covariance[1], sxz = _covariance[2];
      final syy = _covariance[3], syz = _covariance[4], szz = _covariance[5];

      // Σ·j1 and Σ·j2.
      final arx = sxx * jrx + sxy * jry + sxz * jrz;
      final ary = sxy * jrx + syy * jry + syz * jrz;
      final arz = sxz * jrx + syz * jry + szz * jrz;
      final aux = sxx * jux + sxy * juy + sxz * juz;
      final auy = sxy * jux + syy * juy + syz * juz;
      final auz = sxz * jux + syz * juy + szz * juz;

      // With the screen's low-pass filter added to the diagonal, taken from
      // pixels squared to the quad's world units squared.
      final dilation = kSplatLowPass * pixel * pixel;
      final a = jrx * arx + jry * ary + jrz * arz + dilation;
      final b = jrx * aux + jry * auy + jrz * auz;
      final d = jux * aux + juy * auy + juz * auz + dilation;

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

/// How a cloud's overlapping splats are combined — `N5`.
enum SplatComposite {
  /// [hashed] while a temporal resolve runs, [sorted] otherwise: the noise is
  /// only worth having when something averages it.
  automatic,

  /// Sorted back to front and alpha blended, the way a cloud has always been
  /// drawn. Exact in a single frame; costs a sort whenever the eye moves.
  sorted,

  /// Unsorted: each splat kept or dropped whole at a pixel against noise, with
  /// its opacity as the chance of keeping it, and written opaque with its
  /// depth. One frame of it is speckle; a temporal resolve averages it into
  /// the blended picture without the cloud ever being sorted.
  ///
  /// The cores come out as the sorted blend does. The faint tails come out
  /// darker: their kept pixels are sparse, and the resolve clips its history
  /// to each pixel's neighbourhood, which there often holds none of them.
  hashed,
}

/// Draws a cloud into the scene pass.
final class SplatContributor extends PassContributor {
  final ParticleInfoBlock _particleInfo = ParticleInfoBlock();
  final SplatHashInfoBlock _hashInfo = SplatHashInfoBlock();

  /// `FogInfo`'s two members as both splat stages declare them: the fog's
  /// colour and density, and the eye. Not `FogInfoBlock`, which is the lit
  /// stages' three-member layout.
  final Float32List _fog = Float32List(4);
  final Float32List _eye = Float32List(4);

  SplatContributor(
    SplatCloud cloud, {
    this.node,
    this.composite = SplatComposite.automatic,
  }) : quads = SplatQuads(cloud);

  /// Draws a splat tree at [lod]'s budget — the cut is chosen again each
  /// time the cloud is re-sorted, and pages [lod] asks for are drawn as they
  /// arrive. Off unless asked for: the plain constructor draws every splat.
  SplatContributor.lod(
    SplatLod lod, {
    this.node,
    this.composite = SplatComposite.automatic,
  }) : quads = SplatQuads.lod(lod);

  /// What is drawn: the cloud given, or the cut last chosen from a tree.
  SplatCloud get cloud => quads.cloud;
  final SplatQuads quads;

  /// Sorted, hashed, or whichever the frame's temporal setting calls for.
  SplatComposite composite;

  /// The node the cloud hangs from, when it has one: its world matrix places
  /// the cloud, and hiding it hides the cloud. Null draws [cloud] in world
  /// units as stored, which is what a PLY capture is.
  ///
  /// A glTF splat primitive belongs to the node that instantiates its mesh —
  /// `ModelSplat.node` names it — and the node's scale and rotation reach
  /// each splat's covariance, not only its centre, as the extension asks.
  final SceneNode? node;

  PipelineHandle? _pipeline;
  PipelineHandle? _hashedPipeline;

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
    final hashed = switch (composite) {
      SplatComposite.automatic => frame.temporal,
      SplatComposite.sorted => false,
      SplatComposite.hashed => true,
    };
    final vertexShader = frame.device.shaders['ParticleVertex'];
    final fragmentShader =
        frame.device.shaders[hashed ? 'SplatHashed' : 'Splat'];
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
    final forward = Vector3(-m[8], -m[9], -m[10])..normalize();

    // The projection the frame draws with, recovered from the matrix it was
    // handed — `P = (P V) V⁻¹`, and `V⁻¹` is the camera's world matrix — so
    // a jittered or application-supplied one is followed as it is. Pixels
    // are the view's own, not the whole target's.
    final projection = viewProjection.multiplied(camera.worldMatrix);
    final lens = SplatLens.of(
      projection,
      forward,
      frame.height * view.viewportFraction.height,
    );

    quads.build(
      eye: eye,
      right: right,
      up: up,
      model: node?.worldMatrix,
      sorted: !hashed,
      lens: lens,
    );
    if (quads.vertexCount == 0) return;

    frame.encoder
      ..clearBindings()
      ..bindPipeline(
        hashed
            ? _hashedPipeline ??= frame.device.createPipeline(
                vertexShader,
                fragmentShader,
              )
            : _pipeline ??= frame.device.createPipeline(
                vertexShader,
                fragmentShader,
              ),
      );
    frame.state.invalidatePipeline();

    final bytes = ByteData.view(
      quads.vertices.buffer,
      quads.vertices.offsetInBytes,
      quads.vertexCount * kSplatFloatsPerVertex * 4,
    );

    _particleInfo.viewProjection.setAll(0, viewProjection.storage);
    frame.encoder
      ..setState(hashed ? _kHashedState : _kSplatState)
      ..bindVertexData(bytes, quads.vertexCount)
      ..bindIndexBuffer(
        _identityIndices.view(frame.device, quads.vertexCount),
        IndexType.int32,
        quads.vertexCount,
      )
      ..bindBlock(vertexShader, _particleInfo);

    // **Fog, which both splat stages read and nothing bound.** An unbound
    // block reads as zeros, a density of zero is no fog, and so a cloud stood
    // out of the murk at full colour on every backend while the walls behind
    // it faded. WebGL2 was the one that said so, naming the block at the draw.
    final fog = frame.settings.fog;
    final colour = fog.resolvedColor;
    _fog
      ..[0] = colour.x
      ..[1] = colour.y
      ..[2] = colour.z
      ..[3] = fog.density;
    _eye
      ..[0] = eye.x
      ..[1] = eye.y
      ..[2] = eye.z;
    frame.encoder.bindUniformBlock(
      fragmentShader,
      'FogInfo',
      <String, Float32List>{'fog': _fog, 'eye': _eye},
    );
    if (hashed) {
      // The frame's slice of the engine's blue noise, the same slice the
      // post effects read; the eye and the view axis, from which each splat
      // measures the distance its offset into that noise is hashed from.
      _hashInfo.frame[0] = (frame.frameIndex % 32).toDouble();
      _hashInfo.eye
        ..[0] = eye.x
        ..[1] = eye.y
        ..[2] = eye.z;
      _hashInfo.forward
        ..[0] = forward.x
        ..[1] = forward.y
        ..[2] = forward.z;
      frame.encoder
        ..bindBlock(fragmentShader, _hashInfo)
        ..bindTexture(
          fragmentShader,
          'blue_noise_texture',
          EngineTables.of(frame.device).blueNoise,
          sampler: SamplerOptions.nearestClamp,
        );
    }
    frame.encoder.draw();
    frame.state.drawCalls++;
  }

  /// Marks the cloud reactive — `R4`: each splat by its own falloff and
  /// alpha, over the quads [encode] built for this frame's camera.
  ///
  /// Reused rather than rebuilt: the sort is the expensive half of a cloud,
  /// and the camera has not moved since the scene pass drew it.
  @override
  void encodeReactive(ReactiveFrame frame) {
    final vertexShader = frame.device.shaders['ParticleVertex'];
    final fragmentShader = frame.spriteStage;
    if (vertexShader == null || fragmentShader == null) return;
    if (quads.vertexCount == 0) return;

    final bytes = ByteData.view(
      quads.vertices.buffer,
      quads.vertices.offsetInBytes,
      quads.vertexCount * kSplatFloatsPerVertex * 4,
    );
    _particleInfo.viewProjection.setAll(0, frame.viewProjection.storage);
    frame.encoder
      ..clearBindings()
      ..bindPipeline(
        _reactivePipeline ??= frame.device.createPipeline(
          vertexShader,
          fragmentShader,
        ),
      )
      ..setState(ReactiveFrame.state)
      ..bindVertexData(bytes, quads.vertexCount)
      ..bindIndexBuffer(
        _identityIndices.view(frame.device, quads.vertexCount),
        IndexType.int32,
        quads.vertexCount,
      )
      ..bindBlock(vertexShader, _particleInfo);
    frame.bindSprite(fragmentShader, ReactiveShape.gaussian);
    frame.encoder.draw();
  }

  PipelineHandle? _reactivePipeline;

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

  /// **Unblended and depth written**, which is the whole of `N5`: a hashed
  /// splat is either wholly here or not at all, so the depth test can decide
  /// which of the ones that survived is nearest, and the sort is not needed.
  static const PassState _kHashedState = PassState(
    primitiveType: PrimitiveType.triangle,
    polygonMode: PolygonMode.fill,
    cullMode: CullMode.none,
    blend: null,
    depthWrite: true,
  );
}
