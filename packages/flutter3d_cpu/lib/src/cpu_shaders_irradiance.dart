/// `lib/irradiance.glsl`, on the software rasteriser — `L3`.
///
/// The same read over the same uploaded atlas: four nearest taps a bilinear
/// read inside each tile, eight probes weighted trilinearly, by facing and by
/// Chebyshev's bound. Not `IrradianceField.sample`, which reads the field's
/// own arrays nearest-texel and unbiased — that stays the bake's reference,
/// and this is the shader's.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

const String _block = 'IrradianceInfo';

/// `ProbeOctahedral`.
Vector2 _octahedral(Vector3 d) {
  final sum = d.x.abs() + d.y.abs() + d.z.abs();
  if (sum <= 0.0) return Vector2(0.5, 0.5);
  var x = d.x / sum;
  var y = d.y / sum;
  if (d.z < 0.0) {
    final ax = x;
    final ay = y;
    x = (1.0 - ay.abs()) * (ax >= 0.0 ? 1.0 : -1.0);
    y = (1.0 - ax.abs()) * (ay >= 0.0 ? 1.0 : -1.0);
  }
  return Vector2(x * 0.5 + 0.5, y * 0.5 + 0.5);
}

/// `probe/irradiance_convolve.frag` — `L4`: one probe's two tiles updated
/// from its capture, everything else copied through.
final class IrradianceConvolveShader implements CpuFragmentShader {
  const IrradianceConvolveShader();

  /// `CubeTexel`, normalised, with its solid angle, for every texel of a
  /// capture [side] texels wide — the same list for every fragment, so
  /// built once per side.
  static final Map<int, List<(Vector3, double)>> _texels =
      <int, List<(Vector3, double)>>{};

  static List<(Vector3, double)> _cubeTexels(int side) =>
      _texels[side] ??= <(Vector3, double)>[
        for (var face = 0; face < 6; face++)
          for (var row = 0; row < side; row++)
            for (var column = 0; column < side; column++)
              _cubeTexel(
                face,
                (column + 0.5) * (2.0 / side) - 1.0,
                (row + 0.5) * (2.0 / side) - 1.0,
              ),
      ];

  static (Vector3, double) _cubeTexel(int face, double a, double b) {
    final side = (face & 1) == 0 ? 1.0 : -1.0;
    final inverse = 1.0 / math.sqrt(1.0 + a * a + b * b);
    final ray = switch (face >> 1) {
      0 => Vector3(side, a, b),
      1 => Vector3(a, side, b),
      _ => Vector3(a, b, side),
    };
    return (ray * inverse, inverse * inverse * inverse);
  }

  static Vector3 _decode(double u, double v) {
    final x = u * 2.0 - 1.0;
    final y = v * 2.0 - 1.0;
    final z = 1.0 - x.abs() - y.abs();
    final t = math.max(-z, 0.0);
    return Vector3(x + (x >= 0.0 ? -t : t), y + (y >= 0.0 ? -t : t), z)
      ..normalize();
  }

  static (double, double) _interiorOf(double lx, double ly, double interior) {
    final last = interior - 1.0;
    final ix = lx - 1.0;
    final iy = ly - 1.0;
    final left = lx < 0.5;
    final right = lx > interior + 0.5;
    final top = ly < 0.5;
    final bottom = ly > interior + 0.5;
    if ((left || right) && (top || bottom)) {
      return (left ? last : 0.0, top ? last : 0.0);
    }
    if (top) return (last - ix, 0.0);
    if (bottom) return (last - ix, last);
    if (left) return (0.0, last - iy);
    if (right) return (last, last - iy);
    return (ix, iy);
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final field = b.textures['field_texture'];
    if (field == null) return Vector4.zero();
    final probe = b.vec4('ConvolveInfo', 'probe', Vector4.zero());
    final tiles = b.vec4('ConvolveInfo', 'tiles', Vector4.zero());
    final atlas = b.vec4('ConvolveInfo', 'atlas', Vector4.zero());
    final px = (v[0] * atlas.x).floorToDouble();
    final py = (v[1] * atlas.y).floorToDouble();
    final old = field.sample((px + 0.5) / atlas.x, (py + 0.5) / atlas.y);

    if (probe.y > 0.5) {
      final seed = b.textures['seed_texture'];
      return seed?.sample((px + 0.5) / atlas.x, (py + 0.5) / atlas.y) ?? old;
    }

    final columns = probe.w;
    final moments = py >= tiles.z;
    final interior = moments ? tiles.y : tiles.x;
    final stride = interior + 2.0;
    final lx = px;
    final ly = moments ? py - tiles.z : py;
    final tileX = (lx / stride).floorToDouble();
    final tileY = (ly / stride).floorToDouble();
    if (tileY * columns + tileX != probe.x || tileX >= columns) return old;

    final (ix, iy) = _interiorOf(
      lx - tileX * stride,
      ly - tileY * stride,
      interior,
    );
    final normal = _decode((ix + 0.5) / interior, (iy + 0.5) / interior);

    final radiance = b.textures['radiance_texture'];
    final surface = b.textures['surface_texture'];
    final light = Vector3.zero();
    var mean = 0.0;
    var square = 0.0;
    var weight = 0.0;
    for (final (d, solidAngle) in _cubeTexels(
      math.max((atlas.z + 0.5).floor(), 1),
    )) {
      final cosine = normal.dot(d);
      if (cosine <= 0.0) continue;
      if (moments) {
        final c2 = cosine * cosine;
        final w = c2 * c2 * c2 * solidAngle;
        final depth = surface?.sampleCube(d.x, d.y, d.z).w ?? 0.0;
        final axis = math.max(d.x.abs(), math.max(d.y.abs(), d.z.abs()));
        final distance = depth <= 0.0 ? tiles.w : depth / math.max(axis, 1e-4);
        mean += distance * w;
        square += distance * distance * w;
        weight += w;
      } else {
        final w = cosine * solidAngle;
        final l = radiance?.sampleCube(d.x, d.y, d.z) ?? Vector4.zero();
        light.add(Vector3(l.x, l.y, l.z) * w);
        weight += w;
      }
    }
    final keep = probe.z;
    if (moments) {
      final freshMean = weight > 0.0 ? mean / weight : old.x;
      final freshSquare = weight > 0.0 ? square / weight : old.y;
      return Vector4(
        freshMean + (old.x - freshMean) * keep,
        freshSquare + (old.y - freshSquare) * keep,
        0.0,
        1.0,
      );
    }
    final fresh = weight > 0.0 ? light / weight : Vector3(old.x, old.y, old.z);
    return Vector4(
      fresh.x + (old.x - fresh.x) * keep,
      fresh.y + (old.y - fresh.y) * keep,
      fresh.z + (old.z - fresh.z) * keep,
      old.w,
    );
  }
}

/// Chebyshev's bound, cubed, on a point [distance] from a probe whose
/// moments that way are [mean] and [meanSquare]; one nearer than the mean.
double _chebyshevCubed(double mean, double meanSquare, double distance) {
  if (distance <= mean) return 1.0;
  final variance = math.max(meanSquare - mean * mean, 1e-6);
  final difference = distance - mean;
  final bound = variance / (variance + difference * difference);
  return bound * bound * bound;
}

/// Whether the field is read this draw.
bool irradianceEnabled(ShaderBindings b) =>
    b.vec4(_block, 'origin', Vector4.zero()).w > 0.5 &&
    b.textures['irradiance_texture'] != null;

/// `SampleIrradiance(world, normal, view)`.
Vector3 sampleIrradiance(
  ShaderBindings b,
  Vector3 world,
  Vector3 normal,
  Vector3 view,
) {
  final atlas = b.textures['irradiance_texture']!;
  final origin4 = b.vec4(_block, 'origin', Vector4.zero());
  final spacing4 = b.vec4(_block, 'spacing', Vector4.zero());
  final counts4 = b.vec4(_block, 'counts', Vector4.zero());
  final tiles = b.vec4(_block, 'tiles', Vector4.zero());
  final size = b.vec4(_block, 'atlas', Vector4.zero());
  final origin = Vector3(origin4.x, origin4.y, origin4.z);
  final spacing = Vector3(spacing4.x, spacing4.y, spacing4.z);
  final irradianceTile = tiles.x;
  final depthTile = tiles.y;
  final columns = tiles.z;
  final momentsTop = tiles.w;

  Vector4 texel(double x, double y) =>
      atlas.sample((x + 0.5) * size.x, (y + 0.5) * size.y);

  Vector4 bilinear(
    double cornerX,
    double cornerY,
    double interior,
    Vector2 uv,
  ) {
    final ax = 1.0 + uv.x * interior - 0.5;
    final ay = 1.0 + uv.y * interior - 0.5;
    final lx = ax.floorToDouble();
    final ly = ay.floorToDouble();
    final fx = ax - lx;
    final fy = ay - ly;
    final a = texel(cornerX + lx, cornerY + ly);
    final bb = texel(cornerX + lx + 1.0, cornerY + ly);
    final c = texel(cornerX + lx, cornerY + ly + 1.0);
    final d = texel(cornerX + lx + 1.0, cornerY + ly + 1.0);
    final top = a + (bb - a) * fx;
    final bottom = c + (d - c) * fx;
    return top + (bottom - top) * fy;
  }

  final unit = normal.normalized();
  final biased = world + unit * spacing4.w + view * counts4.w;
  final grid = Vector3(
    (biased.x - origin.x) / spacing.x,
    (biased.y - origin.y) / spacing.y,
    (biased.z - origin.z) / spacing.z,
  );
  final base = Vector3(
    grid.x.floorToDouble().clamp(0.0, counts4.x - 2.0),
    grid.y.floorToDouble().clamp(0.0, counts4.y - 2.0),
    grid.z.floorToDouble().clamp(0.0, counts4.z - 2.0),
  );
  final f = Vector3(
    (grid.x - base.x).clamp(0.0, 1.0),
    (grid.y - base.y).clamp(0.0, 1.0),
    (grid.z - base.z).clamp(0.0, 1.0),
  );

  final total = Vector3.zero();
  var weights = 0.0;
  for (var corner = 0; corner < 8; corner++) {
    final ox = (corner & 1).toDouble();
    final oy = ((corner >> 1) & 1).toDouble();
    final oz = ((corner >> 2) & 1).toDouble();
    final cx = base.x + ox;
    final cy = base.y + oy;
    final cz = base.z + oz;
    final probe = (cz * counts4.y + cy) * counts4.x + cx;
    final tileX = probe % columns;
    final tileY = (probe / columns).floorToDouble();

    final irradianceX = tileX * (irradianceTile + 2.0);
    final irradianceY = tileY * (irradianceTile + 2.0);
    final momentX = tileX * (depthTile + 2.0);
    final momentY = momentsTop + tileY * (depthTile + 2.0);

    if (texel(irradianceX + 1.0, irradianceY + 1.0).w < 0.5) continue;

    final wx = ox == 1.0 ? f.x : 1.0 - f.x;
    final wy = oy == 1.0 ? f.y : 1.0 - f.y;
    final wz = oz == 1.0 ? f.z : 1.0 - f.z;
    var weight = math.max(wx * wy * wz, 0.001);

    final probePosition = Vector3(
      origin.x + spacing.x * cx,
      origin.y + spacing.y * cy,
      origin.z + spacing.z * cz,
    );
    final toProbe = probePosition - biased;
    final distance = toProbe.length;
    if (distance > 1e-6) {
      final direction = toProbe / distance;
      final facing = unit.dot((probePosition - world).normalized()) * 0.5 + 0.5;

      final moments = bilinear(
        momentX,
        momentY,
        depthTile,
        _octahedral(-direction),
      );
      final chebyshev = _chebyshevCubed(moments.x, moments.y, distance);
      final floored = math.max(
        (facing * facing + 0.2) * math.max(chebyshev, 0.05),
        1e-6,
      );
      weight *= floored < 0.2 ? floored * floored * floored * 25.0 : floored;
    }

    final light = bilinear(
      irradianceX,
      irradianceY,
      irradianceTile,
      _octahedral(unit),
    );
    total.add(Vector3(light.x, light.y, light.z) * weight);
    weights += weight;
  }
  return weights > 0.0 ? total / weights : Vector3.zero();
}
