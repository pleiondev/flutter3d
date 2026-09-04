import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'sky_settings.dart';

/// Builds the cube a surface reflects: one environment, convolved by roughness.
///
/// **This is the whole of image-based lighting's data.** A rough surface does
/// not reflect one direction, it gathers a lobe around it — so the environment
/// is convolved once per roughness and the results become the mip levels of one
/// cube. The shader then samples the level that matches the surface, and a
/// mirror and a matte wall read the same texture at different levels.
///
/// **Convolved here on the host, and the same lobe is convolved on the
/// device.** The device does it for a reflection probe — a full-screen pass
/// per face per level, `ColorTarget.mipLevel` naming each, with the same fixed
/// spiral and cosine-power lobe as [prefilter] — because a probe is drawn on a
/// machine holding a frame budget and its picture never leaves the GPU. An
/// environment built from bytes the host already has stays here: the two
/// callers are a sky at thirty-two pixels and a studio at sixteen, where the
/// convolution is a fraction of a millisecond and the bytes are the same on
/// every backend, which is what keeps the golden sets comparable. The engine
/// builds 2D mip chains at the same seam — see `MipChain.build`.
///
/// The cost is stated rather than discovered: this is O(faces × texels × taps)
/// in Dart, so a 128-pixel environment is a fraction of a second and a
/// 512-pixel one is not something to do while a level is on screen — that
/// size wants uploading as a base level and filtering the way a probe is.
abstract final class EnvironmentMap {
  /// Faces in the order the hardware layer documents: +X, −X, +Y, −Y, +Z, −Z.
  ///
  /// [size] is the edge of the base level, which is also the sharpest
  /// reflection this can produce. [levels] is how many convolved levels follow
  /// it; the last is the roughest and doubles as the diffuse term — see
  /// [diffuseLevel].
  ///
  /// Returns null when the input does not describe six square faces, for the
  /// same reason the upload does: an environment that disagrees with itself
  /// should cost a texture rather than a frame.
  static List<List<ByteData>>? prefilter(
    List<ByteData> faces, {
    required int size,
    int levels = 4,
    int samples = 64,
  }) {
    if (faces.length != 6 || levels < 1) return null;
    for (final face in faces) {
      if (face.lengthInBytes != size * size * 4) return null;
    }

    final source = _Cube(faces, size);
    final chain = <List<ByteData>>[];
    var side = size;
    for (var level = 1; level <= levels; level++) {
      side = side > 1 ? side >> 1 : 1;
      // Roughness across the chain rather than across the mips a filter would
      // pick: level one is already blurred, and the last is fully rough. A
      // linear ramp is what the shader's `roughness * levels` assumes, so the
      // two have to agree or a surface reads the wrong lobe.
      final roughness = level / levels;
      chain.add(_convolve(source, side, roughness, samples));
    }
    return chain;
  }

  /// The environment a scene's own sky makes, uploaded and ready to reflect.
  ///
  /// **The cheapest environment there is: one a scene already has.** A sky is a
  /// function from direction to colour and that is exactly what an environment
  /// map holds, so a scene with a sky needs no photograph, no asset and no
  /// authoring — the six faces are rendered from [sky] by asking it the
  /// direction each texel looks along.
  ///
  /// Returns null when the device cannot hold a cube, when the sky is off, or
  /// when the upload refuses — in every case leaving the flat ambient doing the
  /// work it did before.
  ///
  /// **Low dynamic range, and that is a real limitation rather than an
  /// oversight.** The faces are eight bits a channel, so a sun bright enough to
  /// blow past white in the sky pass is clamped to white here and reflects less
  /// than it should. A float format would fix it and costs four times the
  /// memory and a conformance answer from every backend; this is the version
  /// worth having first.
  static ({TextureHandle texture, int levels})? fromSky(
    GraphicsDevice device,
    SkySettings sky, {
    int size = 32,
    int levels = 4,
  }) {
    if (!device.supportsCubeTextures || !sky.enabled) return null;

    final faces = <ByteData>[];
    final colour = Vector3.zero();
    for (var face = 0; face < 6; face++) {
      final data = ByteData(size * size * 4);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final u = (x + 0.5) / size * 2.0 - 1.0;
          final v = (y + 0.5) / size * 2.0 - 1.0;
          colour.setFrom(sky.sample(_directionFor(face, u, v)));
          final at = (y * size + x) * 4;
          data.setUint8(at, (colour.x * 255.0).round().clamp(0, 255));
          data.setUint8(at + 1, (colour.y * 255.0).round().clamp(0, 255));
          data.setUint8(at + 2, (colour.z * 255.0).round().clamp(0, 255));
          data.setUint8(at + 3, 255);
        }
      }
      faces.add(data);
    }

    final chain = prefilter(faces, size: size, levels: levels);
    if (chain == null) return null;
    final texture = device.createCubeTextureFromPixels(
      size: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: faces,
      mipLevels: chain,
    );
    return texture == null ? null : (texture: texture, levels: levels);
  }

  /// Which level of the chain a shader should treat as the diffuse term.
  ///
  /// The roughest one. **Not a true Lambert irradiance**, and the difference is
  /// worth naming: a cosine lobe is wider than the GGX lobe convolved here, so
  /// this is slightly too tight and a strongly directional environment will read
  /// a little more contrasty on matte surfaces than it should.
  ///
  /// Taken anyway, because the alternative is a second data set — nine
  /// spherical-harmonic coefficients in their own uniform block — for a term
  /// that is already the least directional thing in the frame. One cube, one
  /// binding, and the error is smaller than the one the flat ambient it
  /// replaces was making.
  static int diffuseLevel(int levels) => levels;
}

/// The six faces, sampled by direction.
final class _Cube {
  _Cube(this.faces, this.size);

  final List<ByteData> faces;
  final int size;

  /// Nearest-texel lookup along [dir].
  ///
  /// Nearest rather than bilinear on purpose: every tap of the convolution is
  /// averaged with sixty-three others, so filtering each one buys nothing an
  /// eye can find and costs four reads instead of one.
  void sample(Vector3 dir, Vector4 out) {
    final ax = dir.x.abs();
    final ay = dir.y.abs();
    final az = dir.z.abs();

    int face;
    double u;
    double v;
    double major;
    if (ax >= ay && ax >= az) {
      major = ax;
      face = dir.x > 0 ? 0 : 1;
      u = dir.x > 0 ? -dir.z : dir.z;
      v = -dir.y;
    } else if (ay >= az) {
      major = ay;
      face = dir.y > 0 ? 2 : 3;
      u = dir.x;
      v = dir.y > 0 ? dir.z : -dir.z;
    } else {
      major = az;
      face = dir.z > 0 ? 4 : 5;
      u = dir.z > 0 ? dir.x : -dir.x;
      v = -dir.y;
    }

    final inv = 0.5 / math.max(major, 1e-8);
    final sx = ((u * inv + 0.5) * size).floor().clamp(0, size - 1);
    final sy = ((v * inv + 0.5) * size).floor().clamp(0, size - 1);
    final at = (sy * size + sx) * 4;
    final data = faces[face];
    out.setValues(
      data.getUint8(at) / 255.0,
      data.getUint8(at + 1) / 255.0,
      data.getUint8(at + 2) / 255.0,
      data.getUint8(at + 3) / 255.0,
    );
  }
}

/// The direction a texel of [face] at ([u], [v]) in [-1, 1] looks along.
///
/// The inverse of `_Cube.sample`'s mapping, and the two have to stay inverses:
/// a convolution that gathers from directions its own faces do not produce is a
/// cube with six seams in it.
Vector3 _directionFor(int face, double u, double v) {
  switch (face) {
    case 0:
      return Vector3(1.0, -v, -u)..normalize();
    case 1:
      return Vector3(-1.0, -v, u)..normalize();
    case 2:
      return Vector3(u, 1.0, v)..normalize();
    case 3:
      return Vector3(u, -1.0, -v)..normalize();
    case 4:
      return Vector3(u, -v, 1.0)..normalize();
    default:
      return Vector3(-u, -v, -1.0)..normalize();
  }
}

/// One level: every texel gathers a cosine-power lobe about its own direction.
///
/// A Phong-style lobe rather than a GGX importance sample, which is the trade
/// this makes for being CPU-side: importance sampling needs a low-discrepancy
/// sequence and twice the taps to stop looking grainy, and the difference
/// between the two lobes is not visible on a reflection that is already blurred
/// this far.
List<ByteData> _convolve(
  _Cube source,
  int side,
  double roughness,
  int samples,
) {
  // Roughness to a specular power, the mapping Blinn-Phong and GGX are usually
  // reconciled with. Squared first because roughness is authored perceptually.
  final alpha = math.max(roughness * roughness, 1e-3);
  final power = 2.0 / (alpha * alpha) - 2.0;

  // A fixed spiral rather than random directions: the same input has to produce
  // the same bytes on every machine and every run, or a golden means nothing.
  final taps = <Vector3>[];
  final golden = math.pi * (3.0 - math.sqrt(5.0));
  for (var i = 0; i < samples; i++) {
    final z = 1.0 - (i + 0.5) / samples;
    final radius = math.sqrt(math.max(1.0 - z * z, 0.0));
    final theta = golden * i;
    // Concentrated towards the lobe's axis by the power, so a sharp level does
    // not spend sixty of its taps on directions it weights to nothing.
    final spread = math.pow(z, 1.0 / (power + 1.0)).toDouble();
    taps.add(
      Vector3(
        radius * math.cos(theta) * (1.0 - spread) + 0.0,
        radius * math.sin(theta) * (1.0 - spread) + 0.0,
        spread,
      )..normalize(),
    );
  }

  final out = <ByteData>[];
  final sampled = Vector4.zero();
  for (var face = 0; face < 6; face++) {
    final data = ByteData(side * side * 4);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final u = (x + 0.5) / side * 2.0 - 1.0;
        final v = (y + 0.5) / side * 2.0 - 1.0;
        final axis = _directionFor(face, u, v);

        // A frame about the axis, so the tap set is reused rather than rebuilt.
        final up = axis.z.abs() < 0.999
            ? Vector3(0.0, 0.0, 1.0)
            : Vector3(1.0, 0.0, 0.0);
        final right = up.cross(axis)..normalize();
        final ahead = axis.cross(right);

        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        var weight = 0.0;
        for (final tap in taps) {
          final dir = right * tap.x + ahead * tap.y + axis * tap.z;
          final cosine = dir.dot(axis);
          if (cosine <= 0.0) continue;
          source.sample(dir, sampled);
          r += sampled.x * cosine;
          g += sampled.y * cosine;
          b += sampled.z * cosine;
          weight += cosine;
        }
        final scale = weight > 0.0 ? 1.0 / weight : 0.0;
        final at = (y * side + x) * 4;
        data.setUint8(at, ((r * scale) * 255.0).round().clamp(0, 255));
        data.setUint8(at + 1, ((g * scale) * 255.0).round().clamp(0, 255));
        data.setUint8(at + 2, ((b * scale) * 255.0).round().clamp(0, 255));
        data.setUint8(at + 3, 255);
      }
    }
    out.add(data);
  }
  return out;
}
