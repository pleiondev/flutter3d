/// `SampleLight` and `AccumulateLights` from `surface.glsl`: turning a light
/// index into a contribution, and summing every light a fragment sees.
///
/// The seam between this file and `cpu_shaders_surface.dart` is the seam
/// `surface.glsl` itself draws: reading a surface answers "what is here",
/// this file answers "what lights it".
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';
import 'cpu_shaders_ltc.dart';
import 'cpu_shaders_shadow_directional.dart';
import 'cpu_shaders_shadow_point.dart';
import 'cpu_shaders_surface.dart';

/// `LightCount()`: the count lives in `frame_params.y`, not in a member of its
/// own. Reading a member that does not exist is silent, which is how the first
/// version of this file drew an unlit scene.
int lightCount(ShaderBindings bindings, Vector3 world) {
  final params = bindings.vec4('FragInfo', 'frame_params', Vector4.zero());
  final list = bindings.vec4('LightListInfo', 'list', Vector4.zero());
  // `L6`: the tail is the cell's, when the draw reads one.
  // A draw with no list texture has `list.y` at nought and no cell to read,
  // which keeps the ordinary draw at the one lookup it always made.
  final tail = list.y > 0.0 && clustered(bindings)
      ? clusterAt(bindings, world).count
      : list.x;
  return (params.y + 0.5).floor().clamp(0, kMaxLights) +
      (tail + 0.5).floor().clamp(0, kExtraLights);
}

/// `Clustered` — `L6`.
bool clustered(ShaderBindings bindings) =>
    bindings.vec4('LightListInfo', 'cluster_grid', Vector4.zero()).w > 0.5;

/// `FindCluster`: where the entries of [world]'s cell start, and how many.
({double offset, double count}) clusterAt(
  ShaderBindings bindings,
  Vector3 world,
) {
  final m = bindings.mat4('LightListInfo', 'cluster_view_projection');
  final grid = bindings.vec4('LightListInfo', 'cluster_grid', Vector4.zero());
  final depth = bindings.vec4('LightListInfo', 'cluster_depth', Vector4.zero());
  final clip = m.transformed(Vector4(world.x, world.y, world.z, 1.0));
  final w = math.max(clip.w, 1e-6);
  double cut(double at, double cells) =>
      math.min(math.max((at * cells).floorToDouble(), 0.0), cells - 1.0);
  final tx = cut(clip.x / w * 0.5 + 0.5, grid.x);
  final ty = cut(clip.y / w * 0.5 + 0.5, grid.y);
  final tz = clip.w <= depth.x
      ? 0.0
      : cut(math.log(clip.w / depth.x) * depth.y / grid.z, grid.z);
  final cell = (tx + ty * grid.x + tz * grid.x * grid.y).round();
  final header = lightListTexel(
    bindings,
    depth.z.round() + cell ~/ 4,
    cell % 4,
  );
  return (offset: header.x, count: header.y);
}

/// `ClusterRow`: the row entry [slot] of [world]'s cell names.
int clusterRow(ShaderBindings bindings, Vector3 world, int slot) {
  final depth = bindings.vec4('LightListInfo', 'cluster_depth', Vector4.zero());
  final entry = clusterAt(bindings, world).offset.round() + slot;
  final four = lightListTexel(
    bindings,
    depth.w.round() + entry ~/ 16,
    (entry % 16) ~/ 4,
  );
  return switch (entry % 4) {
    0 => four.x,
    1 => four.y,
    2 => four.z,
    _ => four.w,
  }.round();
}

/// `InSlots`: whether one of the draw's slots already holds row [row].
bool inSlots(ShaderBindings bindings, int row) {
  for (var i = 0; i < kMaxLights; i++) {
    if ((lightListLane(bindings, 'slot_rows', i) - row).abs() < 0.5) {
      return true;
    }
  }
  return false;
}

/// `kExtraLights` in `lib/surface.glsl` — `gfx-74n`.
const int kExtraLights = 24;

/// `LightListLane`: one lane of a six-vector table.
double lightListLane(ShaderBindings bindings, String member, int slot) {
  final four = bindings.vec4(
    'LightListInfo',
    member,
    Vector4.zero(),
    at: slot ~/ 4,
  );
  return switch (slot - (slot ~/ 4) * 4) {
    0 => four.x,
    1 => four.y,
    2 => four.z,
    _ => four.w,
  };
}

/// `LightListRow`: which row of the light texture slot [slot] of the tail
/// reads.
double lightListRow(ShaderBindings bindings, int slot) =>
    lightListLane(bindings, 'indices', slot);

/// `LightListScale`: how much of slot [slot] survives the edge fade.
double lightListScale(ShaderBindings bindings, int slot) =>
    lightListLane(bindings, 'scales', slot);

/// One texel of the light list, at row [row] and column [column].
///
/// **Nearest and unfiltered, by the sampler the renderer binds.** These are not
/// colours: a position halfway between two lights is not a light, so anything
/// that interpolated them would invent one. The GLSL samples at texel centres
/// for the same reason, and this indexes the row directly, which is that
/// arithmetic with the rounding taken out.
Vector4 lightListTexel(ShaderBindings bindings, int row, int column) {
  final texture = bindings.textures['light_list_texture'];
  if (texture == null) return Vector4.zero();
  final width = texture.texture.width;
  final height = texture.texture.height;
  if (row < 0 || row >= height || column < 0 || column >= width) {
    return Vector4.zero();
  }
  final at = (row * width + column) * 4;
  final pixels = texture.texture.pixels;
  return Vector4(pixels[at], pixels[at + 1], pixels[at + 2], pixels[at + 3]);
}

/// `PunctualAttenuation`: inverse square with glTF's range window.
double attenuation(double distance, double range) {
  var attenuation = 1.0 / math.max(distance * distance, 1e-4);
  if (range > 0.0) {
    final ratio = distance / range;
    final window = (1.0 - ratio * ratio * ratio * ratio).clamp(0.0, 1.0);
    attenuation *= window * window;
  }
  return attenuation;
}

/// What `SampleLight` produces.
typedef LightSample = ({
  Vector3 direction,
  Vector3 radiance,
  double nDotL,
  double nDotH,
  double vDotH,
  // `L7`: the GGX lobe integrated over a rectangle, its norm and Fresnel
  // term, when the model binds the LTC tables; null otherwise.
  Vector3? ltc,
});

/// `RectangleFormFactor` — `gfx-77n`.
///
/// Lambert's polygon form factor, exact rather than fitted: each edge's
/// subtended angle weighted by how much its plane leans into the normal, summed
/// and halved. See the GLSL of the same name for why no table is shipped, and
/// for why the sum is negated — the rectangle emits along
/// `cross(halfWidth, halfHeight)` and this winding is clockwise seen from
/// there.
double rectangleFormFactor(List<Vector3> corners, Vector3 n) {
  var total = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = corners[i].normalized();
    final b = corners[(i + 1) & 3].normalized();
    // Clamped before the `acos`: rounding can put a dot a hair past one, and
    // `acos` of that is a NaN that spreads to the whole pixel.
    final angle = math.acos(a.dot(b).clamp(-1.0, 1.0));
    final axis = a.cross(b);
    final len = axis.length;
    if (len > 1e-6) total += angle * (axis..scale(1.0 / len)).dot(n);
  }
  return math.max(-total * 0.5, 0.0);
}

/// `RectangleClosestPoint` — the representative point for the specular lobe.
Vector3 rectangleClosestPoint(
  Vector3 centre,
  Vector3 halfWidth,
  Vector3 halfHeight,
  Vector3 world,
  Vector3 mirror,
) {
  final n = halfWidth.cross(halfHeight);
  final nLen = n.length;
  if (nLen < 1e-12) return centre;
  n.scale(1.0 / nLen);

  final toPlane = centre - world;
  final denom = mirror.dot(n);
  final Vector3 onPlane;
  if (denom.abs() < 1e-5) {
    onPlane = toPlane - n * toPlane.dot(n);
  } else {
    final t = toPlane.dot(n) / denom;
    onPlane = t > 0.0 ? mirror * t : toPlane - n * toPlane.dot(n);
  }

  final offset = onPlane - toPlane;
  final wLen2 = math.max(halfWidth.dot(halfWidth), 1e-12);
  final hLen2 = math.max(halfHeight.dot(halfHeight), 1e-12);
  final u = (offset.dot(halfWidth) / wLen2).clamp(-1.0, 1.0);
  final v = (offset.dot(halfHeight) / hLen2).clamp(-1.0, 1.0);
  return centre + halfWidth * u + halfHeight * v;
}

/// `SampleLight`.
///
/// Returns null for a light that contributes nothing, which is the `n_dot_l <=
/// 0` early-out in `AccumulateLights`.
LightSample? sampleLight(ShaderBindings bindings, int index, Surface s) {
  // A light past the eighth comes from the frame's light list — `gfx-74n`. The
  // row holds the same four vectors the slot arrays do, in the same order, so
  // everything below this reads one shape.
  final fromList = index >= kMaxLights;
  final slot = index - kMaxLights;
  // `L6`: from the cell, when the draw reads one; a light the slots already
  // hold is skipped by its intensity.
  final fromCell = fromList && clustered(bindings);
  final row = !fromList
      ? -1
      : fromCell
      ? clusterRow(bindings, s.world, slot)
      : lightListRow(bindings, slot).round();

  final position = fromList
      ? lightListTexel(bindings, row, 0)
      : bindings.vec4('FragInfo', 'light_position', Vector4.zero(), at: index);
  final colour = fromList
      ? (lightListTexel(bindings, row, 1)
          // The intensity and not the colour, for `_pack`'s own reason: the
          // same multiply, and only one of them is a number nobody authored.
          ..w *= fromCell
              ? (inSlots(bindings, row) ? 0.0 : 1.0)
              : lightListScale(bindings, slot))
      : bindings.vec4('FragInfo', 'light_color', Vector4.zero(), at: index);
  final direction = fromList
      ? lightListTexel(bindings, row, 2)
      : bindings.vec4('FragInfo', 'light_direction', Vector4.zero(), at: index);

  Vector4 coneOf() => fromList
      ? lightListTexel(bindings, row, 3)
      : bindings.vec4('FragInfo', 'light_cone', Vector4.zero(), at: index);

  // **A rectangle leaves before the aim is normalised — `gfx-77n`.** For every
  // other kind `direction.xyz` points somewhere and its length means nothing;
  // for this one the length *is* half the panel's width, and normalising would
  // throw the size away. Transcribed from the branch of the same name in
  // `SampleLight`.
  if (position.w > 2.5) {
    final cone = coneOf();
    final halfWidth = Vector3(direction.x, direction.y, direction.z);
    final halfHeight = Vector3(cone.x, cone.y, cone.z);
    final toCentre = Vector3(position.x, position.y, position.z) - s.world;

    final corners = <Vector3>[
      toCentre - halfWidth - halfHeight,
      toCentre + halfWidth - halfHeight,
      toCentre + halfWidth + halfHeight,
      toCentre - halfWidth + halfHeight,
    ];
    final formFactor = rectangleFormFactor(corners, s.normal);
    if (formFactor <= 0.0) return null;

    final area = halfWidth.cross(halfHeight).length * 4.0;
    var radiance = area > 1e-9 ? 1.0 / area : 0.0;

    // The range window only: a panel twice as far away subtends a quarter of
    // the sky, so the inverse square is already inside the form factor.
    if (direction.w > 0.0) {
      final ratio = toCentre.length / direction.w;
      final window = (1.0 - ratio * ratio * ratio * ratio).clamp(0.0, 1.0);
      radiance *= window * window;
    }

    final mirror = s.normal * (2.0 * s.normal.dot(s.view)) - s.view;
    final representative = rectangleClosestPoint(
      Vector3(position.x, position.y, position.z),
      halfWidth,
      halfHeight,
      s.world,
      mirror,
    );
    final toPoint = representative - s.world;
    final pointDistance = toPoint.length;
    final l = pointDistance > 1e-6
        ? (toPoint..scale(1.0 / pointDistance))
        : s.normal.clone();

    final h = (l + s.view)..normalize();
    return (
      direction: l,
      radiance: Vector3(colour.x, colour.y, colour.z) * (colour.w * radiance),
      nDotL: formFactor,
      nDotH: math.max(s.normal.dot(h), 0.0),
      vDotH: math.max(s.view.dot(h), 0.0),
      ltc: switch (bindings.textures['ltc_texture']) {
        final table? => ltcRectangle(
          table,
          s.normal,
          s.view,
          s.roughness,
          corners,
        ),
        null => null,
      },
    );
  }

  final aim = Vector3(direction.x, direction.y, direction.z);
  final aimLength = aim.length;
  if (aimLength > 1e-6) aim.scale(1.0 / aimLength);

  Vector3 toLight;
  var lightAttenuation = 1.0;
  if (position.w < 0.5) {
    // Directional: the direction to the light is the reverse of the one it
    // points.
    toLight = -aim;
  } else {
    toLight = Vector3(position.x, position.y, position.z) - s.world;
    final distance = toLight.length;
    if (distance < 1e-6) return null;
    toLight.scale(1.0 / distance);
    lightAttenuation = attenuation(distance, direction.w);
  }

  // The spot cone: a smooth ramp between the two cosines, transcribed from
  // `SampleLight` in surface.glsl. The Dart side guarantees the denominator is
  // non-zero.
  //
  // Three lines above this there used to be a comment saying spot cones were
  // not transcribed, left behind when they were. This file's header promises
  // that where it departs from the GLSL it says so, which is only worth
  // anything if a departure it names is one it has.
  if (position.w > 1.5) {
    final cone = fromList
        ? lightListTexel(bindings, row, 3)
        : bindings.vec4('FragInfo', 'light_cone', Vector4.zero(), at: index);
    final cosAngle = aim.dot(-toLight);
    lightAttenuation *= ((cosAngle - cone.y) / (cone.x - cone.y)).clamp(
      0.0,
      1.0,
    );
  }

  final half = (toLight + s.view)..normalize();
  final nDotL = math.max(s.normal.dot(toLight), 0.0);
  if (nDotL <= 0.0) return null;
  return (
    direction: toLight,
    radiance:
        Vector3(colour.x, colour.y, colour.z) * (colour.w * lightAttenuation),
    nDotL: nDotL,
    nDotH: math.max(s.normal.dot(half), 0.0),
    vDotH: math.max(s.view.dot(half), 0.0),
    ltc: null,
  );
}

/// `AccumulateLights`, with the model's own response passed in.
///
/// The GLSL achieves this with two function prototypes each shader defines;
/// here it is a callback, which is the same shape and one fewer file.
Vector3 accumulateLights(
  Surface s,
  ShaderBindings b,
  FragmentContext c, {
  required Vector3 Function(Surface s, LightSample light) shade,
  required bool shadowed,
}) {
  var total = Vector3.zero();
  final count = lightCount(b, s.world);
  for (var i = 0; i < count; i++) {
    final light = sampleLight(b, i, s);
    if (light == null) continue;
    // `LightHasShadow` — `gfx-74n`. Only the first eight carry one: the atlas
    // has six rows and the slot table eight entries, so a light from the list
    // has no row to read and asking would index past the table.
    var visibility = 1.0;
    if (i < kMaxLights) {
      visibility = shadowed ? shadowFactor(s, b, i, light.nDotL) : 1.0;
      visibility *= pointShadowFactor(b, s.world, s.normal, i, c);
    }
    if (visibility <= 0.0) continue;
    final response = shade(s, light);
    total += Vector3(
      response.x * light.radiance.x,
      response.y * light.radiance.y,
      response.z * light.radiance.z,
    )..scale(light.nDotL * visibility);
  }
  return total;
}
