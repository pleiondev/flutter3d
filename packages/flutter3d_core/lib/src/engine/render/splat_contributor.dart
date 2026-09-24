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
import 'identity_indices.dart';
import 'pass_contributor.dart';

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
  SplatQuads(this.cloud);

  final SplatCloud cloud;

  /// The vertex floats, refilled in place every time the camera moves.
  Float32List _vertices = Float32List(0);

  /// Sort scratch, kept so a camera turn allocates nothing.
  Int32List _order = Int32List(0);
  Float32List _depths = Float32List(0);
  final Float32List _covariance = Float32List(6);

  /// How many vertices [vertices] currently holds.
  int vertexCount = 0;

  Float32List get vertices => _vertices;

  /// Fills the buffer for a camera at [eye] whose axes are [right], [up] and
  /// [forward].
  ///
  /// All three are expected orthonormal, which is what a camera's own basis is.
  void build({
    required Vector3 eye,
    required Vector3 right,
    required Vector3 up,
    required Vector3 forward,
  }) {
    final count = cloud.count;
    final needed = count * kSplatVerticesPerSplat * kSplatFloatsPerVertex;
    if (_vertices.length < needed) _vertices = Float32List(needed);
    if (_order.length < count) {
      _order = Int32List(count);
      _depths = Float32List(count);
    }

    final order = cloud.sortedBackToFront(
      eye,
      forward,
      into: _order,
      depths: _depths,
    );

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

      final rx = right.x, ry = right.y, rz = right.z;
      final ux = up.x, uy = up.y, uz = up.z;

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
      final axX = (e1x * sigma1) * rx + (e1y * sigma1) * ux;
      final axY = (e1x * sigma1) * ry + (e1y * sigma1) * uy;
      final axZ = (e1x * sigma1) * rz + (e1y * sigma1) * uz;
      final ayX = (-e1y * sigma2) * rx + (e1x * sigma2) * ux;
      final ayY = (-e1y * sigma2) * ry + (e1x * sigma2) * uy;
      final ayZ = (-e1y * sigma2) * rz + (e1x * sigma2) * uz;

      final cx = cloud.centres[i * 3];
      final cy = cloud.centres[i * 3 + 1];
      final cz = cloud.centres[i * 3 + 2];
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
}

/// Draws a cloud into the scene pass.
final class SplatContributor extends PassContributor {
  final ParticleInfoBlock _particleInfo = ParticleInfoBlock();

  SplatContributor(this.cloud) : quads = SplatQuads(cloud);

  final SplatCloud cloud;
  final SplatQuads quads;

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
  bool get isActive => cloud.count > 0;

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

    // The camera's own basis, out of its world matrix: local +X is right, +Y
    // is up, −Z is forward. Taken here rather than asked of the node, because
    // `CameraNode` publishes only the forward axis — the other two have had no
    // caller until now.
    final camera = view.camera;
    final m = camera.worldMatrix.storage;
    final right = Vector3(m[0], m[1], m[2])..normalize();
    final up = Vector3(m[4], m[5], m[6])..normalize();
    final forward = Vector3(-m[8], -m[9], -m[10])..normalize();
    final eye = camera.readWorldPosition();

    quads.build(eye: eye, right: right, up: up, forward: forward);
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
