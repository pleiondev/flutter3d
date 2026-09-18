/// Filling an irradiance field from the scene it stands in — `gfx-81n`.
///
/// **Rays rather than a rendered cube, and the reason is what is available.**
/// The published way to fill a probe is to trace the scene from it; the way
/// without ray-tracing hardware is to render a small cube map per probe and
/// convolve it. This engine has neither a tracing API nor a spare six render
/// passes per probe per frame — but it does have a raycaster over the same
/// scene, built for picking and already accurate enough to hit a posed
/// character. So a probe is filled by casting a few hundred rays from it,
/// evaluating the direct light where each one lands, and writing what came
/// back into the probe's own tile.
///
/// **One bounce, and it says so.** What a ray finds is a surface lit by the
/// scene's lamps — not a surface lit by other surfaces. Two bounces would be
/// this run over the field's own previous contents, which is how the published
/// schemes do it and is a loop this does not yet run. The visible consequence
/// is that a room lit only by light that has already bounced twice stays dark.
///
/// **This is a bake, run when asked, not per frame.** A probe is a few hundred
/// raycasts; a field of a few hundred probes is a few hundred thousand, which
/// is seconds rather than milliseconds. The published schemes update a slice of
/// the field per frame and let it converge; [gatherProbe] takes one probe so
/// that a caller can do the same, and [gather] does the whole field for a
/// caller that would rather wait once.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'irradiance_field.dart';
import 'light_node.dart';
import 'raycaster.dart';
import 'scene.dart';

/// How far a probe looks before deciding it is seeing the sky.
const double kIrradianceReach = 60.0;

/// Fills every probe of [field] from [scene].
///
/// [rays] is per probe. The directions are a golden-angle spiral rather than a
/// random set, for the reason `EnvironmentMap.prefilter` gives for its own:
/// two independently written backends have to agree exactly, and nothing with
/// a random number in it does.
void gather(
  IrradianceField field,
  Scene scene, {
  int rays = 128,
  Vector3? sky,
}) {
  final caster = Raycaster()..maxDistance = kIrradianceReach;
  for (var z = 0; z < field.countZ; z++) {
    for (var y = 0; y < field.countY; y++) {
      for (var x = 0; x < field.countX; x++) {
        gatherProbe(
          field,
          scene,
          x,
          y,
          z,
          rays: rays,
          sky: sky,
          caster: caster,
        );
      }
    }
  }
  field.fillGutters();
}

/// Fills one probe. See [gather]; the field's gutters are *not* refilled here,
/// because a caller updating a slice per frame should do that once at the end.
void gatherProbe(
  IrradianceField field,
  Scene scene,
  int x,
  int y,
  int z, {
  int rays = 128,
  Vector3? sky,
  Raycaster? caster,
}) {
  final probe = field.probeIndex(x, y, z);
  final at = field.probePosition(x, y, z);
  final ray = caster ?? (Raycaster()..maxDistance = kIrradianceReach);
  final skyColour = sky ?? Vector3.zero();

  // **The rays first, then the convolution.** What a tile holds is irradiance
  // — what a surface facing a direction receives — and that is the incoming
  // light integrated against a cosine over the whole hemisphere, not the light
  // that happened to arrive along that one direction. So the rays are gathered
  // once and every texel is built from all of them.
  var inside = 0;
  final directions = List<Vector3>.generate(rays, (_) => Vector3.zero());
  final radiances = List<Vector3>.generate(rays, (_) => Vector3.zero());
  final distances = Float64List(rays);

  for (var i = 0; i < rays; i++) {
    _spiralDirection(i, rays, directions[i]);
    ray.ray.origin.setFrom(at);
    ray.ray.direction.setFrom(directions[i]);

    final hit = ray.intersectScene(scene);
    if (hit == null) {
      // Nothing out there: the probe sees the sky, at whatever the caller says
      // the sky is worth. Zero by default rather than a guess — an engine that
      // invented a sky colour here would light an interior through its walls.
      radiances[i].setFrom(skyColour);
      distances[i] = kIrradianceReach;
      continue;
    }
    _directLight(scene, hit, radiances[i]);
    distances[i] = hit.distance;
    // A ray that leaves a probe and lands on the *inside* of a surface means
    // the probe is inside that surface. One such ray is a thin wall or a
    // double-sided leaf; most of them is a probe in the furniture.
    if (hit.normal.dot(directions[i]) > 0.0) inside++;
  }

  // **Half is the line, and it is a judgement rather than a measurement.** A
  // probe wedged against a wall sees its inside through a few rays and is still
  // worth reading; one buried in a crate sees nothing else. Below the line the
  // probe stays active and its own black readings are simply what it saw.
  field.active[probe] = inside * 2 > rays ? 0 : 1;

  final normal = Vector3.zero();
  final sum = Vector3.zero();

  for (var ty = 0; ty < field.tile; ty++) {
    for (var tx = 0; tx < field.tile; tx++) {
      field.texelDirection(tx, ty, field.tile, normal);
      sum.setZero();
      var weight = 0.0;
      for (var i = 0; i < rays; i++) {
        final cosine = normal.dot(directions[i]);
        if (cosine <= 0.0) continue;
        sum.addScaled(radiances[i], cosine);
        weight += cosine;
      }
      if (weight > 0.0) sum.scale(1.0 / weight);
      field.writeIrradianceTexel(probe, tx, ty, sum);
    }
  }

  for (var ty = 0; ty < field.depthTile; ty++) {
    for (var tx = 0; tx < field.depthTile; tx++) {
      field.texelDirection(tx, ty, field.depthTile, normal);
      var mean = 0.0;
      var square = 0.0;
      var weight = 0.0;
      for (var i = 0; i < rays; i++) {
        final cosine = normal.dot(directions[i]);
        if (cosine <= 0.0) continue;
        // **Sharpened, unlike the irradiance above.** A cosine lobe is right
        // for light, which arrives from everywhere; it is wrong for distance,
        // where what matters is what lies almost exactly along the direction
        // asked about. A broad lobe averages the near wall with the far one and
        // the visibility test then lets light through both.
        final w = cosine * cosine * cosine * cosine * cosine * cosine;
        mean += distances[i] * w;
        square += distances[i] * distances[i] * w;
        weight += w;
      }
      if (weight > 0.0) {
        mean /= weight;
        square /= weight;
      }
      field.writeDepthTexel(probe, tx, ty, mean, square);
    }
  }
}

/// The light the scene's lamps deliver to [hit], times what the surface
/// reflects.
///
/// Lambert only, and deliberately: what a probe stores is the *diffuse*
/// irradiance arriving at it, so a specular highlight on the surface the ray
/// found is not light heading towards the probe in particular.
void _directLight(Scene scene, HitResult hit, Vector3 out) {
  out.setZero();
  final toLight = Vector3.zero();
  for (final light in scene.lights) {
    if (!light.visibleInHierarchy) continue;

    final double attenuation;
    if (light.type == LightType.directional) {
      light.readDirectionToLight(toLight);
      attenuation = 1.0;
    } else {
      light.readWorldPosition(toLight);
      toLight.sub(hit.point);
      final distance = toLight.length;
      if (distance < 1e-6) continue;
      toLight.scale(1.0 / distance);
      attenuation = 1.0 / math.max(distance * distance, 1e-4);
    }

    final facing = hit.normal.dot(toLight);
    if (facing <= 0.0) continue;

    final scale = light.intensity * attenuation * facing;
    out
      ..x += light.color.x * scale
      ..y += light.color.y * scale
      ..z += light.color.z * scale;
  }

  // **Times the surface's own colour, which is where the bounce gets its
  // tint.** A ray that lands on a red wall under a white lamp brings back red;
  // dropping this multiply is the version of this file that compiles, runs, and
  // makes every room's indirect light the colour of its lamps.
  final albedo = hit.node?.material.baseColor;
  if (albedo != null) {
    out
      ..x *= albedo.x
      ..y *= albedo.y
      ..z *= albedo.z;
  }
}

/// The [i]th of [count] directions spread over the sphere.
///
/// The golden-angle spiral: `z` marches evenly from one pole to the other while
/// the azimuth turns by the golden angle, which lands points about as evenly as
/// anything without an optimisation step and is completely determined by `i`.
void _spiralDirection(int i, int count, Vector3 out) {
  final z = 1.0 - 2.0 * (i + 0.5) / count;
  final radius = math.sqrt(math.max(1.0 - z * z, 0.0));
  final theta = i * 2.399963229728653;
  out.setValues(radius * math.cos(theta), radius * math.sin(theta), z);
}
