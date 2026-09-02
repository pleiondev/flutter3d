/// Bakes the light a level's walls throw on each other.
///
/// ## Radiosity by gathering, not by form factors
///
/// The classical method builds a matrix of form factors between every pair
/// of patches and solves it; the crypt has tens of thousands of texels, and
/// the matrix is their square. This gathers instead: each bounce, every
/// texel sends a few dozen cosine-weighted rays into its hemisphere and
/// averages the light leaving whatever they hit, which is the Monte Carlo
/// estimate of the same integral — `E = π · mean(L)` with `L = albedo · E /
/// π` at the hit, so a bounce is `mean(albedo · E)` over the rays. Rays go
/// through the level's own collision world, the same boxes the player
/// walks into, so a wall that blocks a body blocks light.
///
/// ## Direct light stays dynamic
///
/// By default the map holds only the bounces. The direct light and its
/// shadows are the renderer's, every frame, so a torch can flicker and a
/// door can open; the map carries what does not move. [includeDirect] puts
/// the direct term in as well, which is how the unwrap and the storage are
/// checked before anybody trusts the bounces — a lit floor with a shadow
/// across it is a picture a person can judge.
///
/// ## Deterministic
///
/// Every ray's direction comes from a generator seeded by the texel's own
/// index, so the bake does not depend on the order texels are visited in
/// and two bakes of the same level are the same bytes. That is what lets
/// CI bake and compare rather than trust.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../save/game_random.dart';
import 'brush_geometry.dart';
import 'level.dart';
import 'level_collision.dart';
import 'lightmap.dart';
import 'lightmap_layout.dart';

final class LightmapBaker {
  const LightmapBaker({
    this.texelsPerMetre = 4.0,
    this.bounces = 2,
    this.samples = 64,
    this.seed = 1,
    this.includeDirect = false,
    this.texturedAlbedo = 0.5,
  }) : assert(bounces >= 0),
       assert(samples > 0);

  final double texelsPerMetre;

  /// How many times light is allowed to bounce. Nought bakes nothing but
  /// the direct term, which with [includeDirect] off is an empty map.
  final int bounces;

  /// Rays per texel per bounce.
  final int samples;

  final int seed;

  /// Whether the direct light and its shadows go into the map as well.
  final bool includeDirect;

  /// What a textured material reflects, since the bake does not read the
  /// texture: a mid grey, scaled by the material's colour.
  final double texturedAlbedo;

  /// How far off a face a texel's ray starts, so it does not hit its own
  /// box.
  static const double _lift = 0.02;

  /// Bakes [level]. [log] hears each stage as it completes; the caller keeps
  /// the clock, since this package reads none.
  Lightmap bake(
    Level level, {
    LightmapLayout? layout,
    void Function(String message)? log,
  }) {
    final plan =
        layout ?? LightmapLayout.plan(level, texelsPerMetre: texelsPerMetre);
    final world = CollisionWorld();
    level.addTo(world);
    world.update();

    final indexOf = <Brush, int>{
      for (var i = 0; i < level.brushes.length; i++) level.brushes[i]: i,
    };
    final albedos = <Vector3>[
      for (final brush in level.brushes) _albedoOf(level.materialFor(brush)),
    ];
    log?.call(
      'planned ${plan.faces.length} faces into ${plan.width}x${plan.height} '
      'at $texelsPerMetre texels a metre',
    );

    final direct = _direct(level, plan, world);
    log?.call('direct light done');

    final indirect = Float32List(plan.texelCount * 3);
    var previous = direct;
    for (var bounce = 1; bounce <= bounces; bounce++) {
      final current = _bounce(plan, world, indexOf, albedos, previous);
      for (var i = 0; i < indirect.length; i++) {
        indirect[i] += current[i];
      }
      previous = current;
      log?.call('bounce $bounce done');
    }

    final map = Lightmap(
      width: plan.width,
      height: plan.height,
      texelsPerMetre: plan.texelsPerMetre,
      levelHash: Lightmap.hashOf(level),
    );
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    var counted = 0;
    for (final face in plan.faces) {
      for (var j = 0; j < face.height; j++) {
        for (var i = 0; i < face.width; i++) {
          final at = ((face.y + j) * plan.width + face.x + i) * 3;
          final r = indirect[at] + (includeDirect ? direct[at] : 0.0);
          final g = indirect[at + 1] + (includeDirect ? direct[at + 1] : 0.0);
          final b = indirect[at + 2] + (includeDirect ? direct[at + 2] : 0.0);
          map.setIrradiance(face.x + i, face.y + j, r, g, b);
          sumR += indirect[at];
          sumG += indirect[at + 1];
          sumB += indirect[at + 2];
          counted++;
        }
      }
    }
    // The reserved texel: what a ramp, which owns no rectangle, is lit by —
    // the level's average bounce, which is nearer the truth than black.
    if (counted > 0) {
      map.setIrradiance(
        LightmapLayout.reservedX,
        LightmapLayout.reservedY,
        sumR / counted,
        sumG / counted,
        sumB / counted,
      );
    }
    return map;
  }

  /// The direct irradiance at every planned texel: each light's colour and
  /// intensity, attenuated as the shaders attenuate, times the cosine, when
  /// a ray to the light meets nothing.
  Float32List _direct(Level level, LightmapLayout plan, CollisionWorld world) {
    final out = Float32List(plan.texelCount * 3);
    final point = Vector3.zero();
    final origin = Vector3.zero();
    final toLight = Vector3.zero();
    final hit = RayHit();

    for (final face in plan.faces) {
      final n = face.normal;
      for (var j = 0; j < face.height; j++) {
        for (var i = 0; i < face.width; i++) {
          plan.texelCentre(face, i, j, point);
          origin
            ..setFrom(point)
            ..addScaled(n, _lift);
          final at = ((face.y + j) * plan.width + face.x + i) * 3;
          for (final light in level.lights) {
            final double reach;
            final double attenuation;
            switch (light.type) {
              case LevelLightType.directional:
                toLight
                  ..setFrom(light.direction)
                  ..negate()
                  ..normalize();
                reach = 1000.0;
                attenuation = 1.0;
              case LevelLightType.point:
              case LevelLightType.spot:
                // A spot is lit as a point: the level format carries no
                // cone for it, so the renderer's cone is its own default and
                // the bake has nothing to read.
                toLight
                  ..setFrom(light.position)
                  ..sub(origin);
                final distance = toLight.length;
                if (distance < 1e-4) continue;
                toLight.scale(1.0 / distance);
                reach = distance - _lift;
                attenuation = _punctualAttenuation(distance, light.range);
            }
            final cosine = n.dot(toLight);
            if (cosine <= 0.0 || attenuation <= 0.0) continue;
            if (world.raycast(origin, toLight, reach, hit)) continue;
            final scale = light.intensity * attenuation * cosine;
            out[at] += light.color.x * scale;
            out[at + 1] += light.color.y * scale;
            out[at + 2] += light.color.z * scale;
          }
        }
      }
    }
    return out;
  }

  /// One bounce: at every texel, the average over cosine-weighted rays of
  /// the light the hit texel reflects from [previous].
  Float32List _bounce(
    LightmapLayout plan,
    CollisionWorld world,
    Map<Brush, int> indexOf,
    List<Vector3> albedos,
    Float32List previous,
  ) {
    final out = Float32List(plan.texelCount * 3);
    final point = Vector3.zero();
    final origin = Vector3.zero();
    final direction = Vector3.zero();
    final hit = RayHit();

    for (final face in plan.faces) {
      final n = face.normal;
      final u = face.u;
      final v = face.v;
      for (var j = 0; j < face.height; j++) {
        for (var i = 0; i < face.width; i++) {
          plan.texelCentre(face, i, j, point);
          origin
            ..setFrom(point)
            ..addScaled(n, _lift);
          final texel = (face.y + j) * plan.width + face.x + i;
          final dice = GameRandom((seed ^ (texel * 0x9E3779B1)) & 0x7FFFFFFF);
          var r = 0.0;
          var g = 0.0;
          var b = 0.0;
          for (var s = 0; s < samples; s++) {
            // Cosine-weighted: the radius is the square root of one uniform
            // draw and the angle is the other, which lands more rays near
            // the normal in exactly the proportion the cosine weights them.
            final radius = math.sqrt(dice.nextDouble());
            final angle = 2.0 * math.pi * dice.nextDouble();
            final up = math.sqrt(math.max(0.0, 1.0 - radius * radius));
            direction
              ..setFrom(u)
              ..scale(radius * math.cos(angle))
              ..addScaled(v, radius * math.sin(angle))
              ..addScaled(n, up);
            if (!world.raycast(origin, direction, 200.0, hit)) continue;
            final brush = hit.collider?.userData;
            if (brush is! Brush) continue;
            final index = indexOf[brush];
            if (index == null) continue;
            final faceIndex = _faceFacing(hit.normal);
            if (faceIndex < 0) continue;
            final landed = plan.faceOf(index, faceIndex);
            if (landed == null) continue;
            final (ti, tj) = plan.texelOf(landed, hit.point);
            final from = ((landed.y + tj) * plan.width + landed.x + ti) * 3;
            final albedo = albedos[index];
            r += albedo.x * previous[from];
            g += albedo.y * previous[from + 1];
            b += albedo.z * previous[from + 2];
          }
          final at = texel * 3;
          out[at] = r / samples;
          out[at + 1] = g / samples;
          out[at + 2] = b / samples;
        }
      }
    }
    return out;
  }

  /// Which of the six block faces a hit normal belongs to, or −1 for a
  /// normal no block face has — a ramp's slope.
  static int _faceFacing(Vector3 normal) {
    final axes = BrushGeometry.faceAxes;
    for (var f = 0; f < axes.length; f++) {
      if (axes[f].$1.dot(normal) > 0.99) return f;
    }
    return -1;
  }

  /// The shaders' `PunctualAttenuation`, so a baked light falls off the way
  /// the drawn one does.
  static double _punctualAttenuation(double distance, double range) {
    final inverseSquare = 1.0 / math.max(distance * distance, 1e-4);
    if (range <= 0.0) return inverseSquare;
    final ratio = distance / range;
    final window = (1.0 - ratio * ratio * ratio * ratio).clamp(0.0, 1.0);
    return inverseSquare * window * window;
  }

  /// What a material reflects, linear: its colour, and a mid grey in place
  /// of a texture the bake does not read.
  Vector3 _albedoOf(LevelMaterial material) {
    final tint = material.baseColor;
    final textured = material.albedo != null ? texturedAlbedo : 1.0;
    return Vector3(
      _linear(tint.x) * textured,
      _linear(tint.y) * textured,
      _linear(tint.z) * textured,
    );
  }

  static double _linear(double srgb) => srgb <= 0.04045
      ? srgb / 12.92
      : math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
}
