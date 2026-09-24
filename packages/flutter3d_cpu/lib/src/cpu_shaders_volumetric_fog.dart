/// `volumetric_fog.frag` and `volumetric_fog_upsample.frag`: the air marched
/// at half resolution and laid over the scene by depth — `S4`.
///
/// Mirrors the GLSL operation for operation, the contract every shader in
/// this package keeps.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_lighting.dart';
import 'cpu_shaders_reflections.dart';

const String _block = 'VolumeFogInfo';

/// `kFogCellLights`: the most lights one step reads from its cell.
const int _kFogCellLights = 16;

/// `HenyeyGreenstein` from the shader.
double _henyeyGreenstein(double cosine, double g) {
  final g2 = g * g;
  final denominator = math.max(1.0 + g2 - 2.0 * g * cosine, 1e-4);
  return (1.0 - g2) / (12.566371 * denominator * math.sqrt(denominator));
}

/// `volumetric_fog.frag`: in-scatter in rgb, transmittance in alpha.
final class VolumetricFogShader implements CpuFragmentShader {
  const VolumetricFogShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final forward = b.vec4(_block, 'forward', Vector4.zero());
    final steps = (forward.w + 0.5).floor();

    final inverse = b.mat4(_block, 'inverse_view_projection');
    final ndcX = v[0] * 2.0 - 1.0;
    final ndcY = 1.0 - v[1] * 2.0;
    final nearH = inverse.transformed(Vector4(ndcX, ndcY, 0.0, 1.0));
    final farH = inverse.transformed(Vector4(ndcX, ndcY, 1.0, 1.0));
    final origin = Vector3(nearH.x, nearH.y, nearH.z)..scale(1.0 / nearH.w);
    final farPoint = Vector3(farH.x, farH.y, farH.z)..scale(1.0 / farH.w);
    final along = (farPoint - origin)..normalize();

    final camera = b.vec4(_block, 'camera', Vector4.zero());
    final surfaceDepth = b.textures['surface_texture']?.sample(v[0], v[1]).w;
    final cosine = math.max(
      along.dot(Vector3(forward.x, forward.y, forward.z)),
      1e-4,
    );
    final depth = surfaceDepth ?? 0.0;
    final toSurface = depth > 0.0 ? depth / cosine : 1e9;
    final distance = math.min(camera.w, toSurface);
    if (steps < 1 || distance <= 0.0) return Vector4(0.0, 0.0, 0.0, 1.0);

    final stride = distance / steps;
    final offset = pixelNoise(b, c.coord.x, c.coord.y) * stride;

    final medium = b.vec4(_block, 'medium', Vector4.zero());
    double density(double y) {
      final exponent = (-medium.y * (y - medium.z)).clamp(-30.0, 30.0);
      return math.max(medium.x, 0.0) * math.exp(exponent);
    }

    final cascades = b.vec4(_block, 'cascades', Vector4.zero());
    final bias = b.vec4(_block, 'bias', Vector4.zero());
    final shadow = b.textures['shadow_texture'];
    final matrices = <Matrix4>[
      b.mat4(_block, 'shadow_matrix'),
      b.mat4(_block, 'shadow_matrix_far'),
      b.mat4(_block, 'shadow_matrix_farthest'),
    ];
    final cascadeCount = (cascades.z + 0.5).floor();

    // `LitAt`, as `light_shafts.frag` has it.
    double litAt(Vector3 world, double viewDistance) {
      var cascade = 0;
      if (cascadeCount > 1 && viewDistance > cascades.x) cascade = 1;
      if (cascadeCount > 2 && viewDistance > cascades.y) cascade = 2;
      for (var attempt = 0; attempt < 3; attempt++) {
        final which = cascade + attempt;
        if (which >= cascadeCount || shadow == null) break;
        final lightSpace = matrices[which].transformed(
          Vector4(world.x, world.y, world.z, 1.0),
        );
        if (lightSpace.w <= 0.0) continue;
        final candidate = Vector3(lightSpace.x, lightSpace.y, lightSpace.z)
          ..scale(1.0 / lightSpace.w);
        final tileX = candidate.x * 0.5 + 0.5;
        final tileY = 0.5 - candidate.y * 0.5;
        if (tileX < 0.0 || tileX > 1.0 || tileY < 0.0 || tileY > 1.0) continue;
        if (candidate.z > 1.0) {
          if (which < cascadeCount - 1) continue;
          candidate.z = 1.0;
        }
        final stored = shadow.sample((tileX + which) / cascadeCount, tileY).x;
        return candidate.z - bias[which] > stored ? 0.0 : 1.0;
      }
      return 1.0;
    }

    final sun = b.vec4(_block, 'sun', Vector4.zero());
    final g = sun.w;
    final sunPhase = _henyeyGreenstein(
      along.dot(Vector3(sun.x, sun.y, sun.z)),
      g,
    );
    final sunRadiance = b.vec4(_block, 'sun_radiance', Vector4.zero());
    final ambient = b.vec4(_block, 'ambient', Vector4.zero());
    final albedo = b.vec4(_block, 'albedo', Vector4.zero());
    final clustered = albedo.w > 0.5;
    final eye = Vector3(camera.x, camera.y, camera.z);

    var transmittance = 1.0;
    final inscatter = Vector3.zero();
    for (var i = 0; i < steps && i < 64; i++) {
      final at = origin + along * (offset + i * stride);
      final stepTransmittance = math.exp(-density(at.y) * stride);
      final sunShare = sunPhase * litAt(at, (at - eye).length);
      final light = Vector3(
        sunRadiance.x * sunShare + ambient.x * 0.07957747,
        sunRadiance.y * sunShare + ambient.y * 0.07957747,
        sunRadiance.z * sunShare + ambient.z * 0.07957747,
      );
      if (clustered) {
        final cell = _clusterLight(b, at, along, g);
        light
          ..x += albedo.x * cell.x
          ..y += albedo.y * cell.y
          ..z += albedo.z * cell.z;
      }
      inscatter.addScaled(light, transmittance * (1.0 - stepTransmittance));
      transmittance *= stepTransmittance;
    }
    return Vector4(inscatter.x, inscatter.y, inscatter.z, transmittance);
  }
}

/// One texel of the light list, as `ListTexel` reads it: [texel] across and
/// [row] down, at the centre, through the scales the block carries.
Vector4 _listTexel(ShaderBindings b, double texel, double row) {
  final list = b.vec4(_block, 'list', Vector4.zero());
  final texture = b.textures['light_list_texture'];
  if (texture == null) return Vector4.zero();
  return texture.sample((texel + 0.5) * list.x, (row + 0.5) * list.y);
}

/// `ClusterLight`: what the lights of [world]'s cell send along [along].
Vector3 _clusterLight(
  ShaderBindings b,
  Vector3 world,
  Vector3 along,
  double g,
) {
  final m = b.mat4(_block, 'cluster_view_projection');
  final grid = b.vec4(_block, 'cluster_grid', Vector4.zero());
  final depth = b.vec4(_block, 'cluster_depth', Vector4.zero());
  final clip = m.transformed(Vector4(world.x, world.y, world.z, 1.0));
  final w = math.max(clip.w, 1e-6);
  double cut(double at, double cells) =>
      math.min(math.max(at.floorToDouble(), 0.0), cells - 1.0);
  final tx = cut((clip.x / w * 0.5 + 0.5) * grid.x, grid.x);
  final ty = cut((clip.y / w * 0.5 + 0.5) * grid.y, grid.y);
  final tz = clip.w <= depth.x
      ? 0.0
      : cut(math.log(clip.w / depth.x) * depth.y, grid.z);
  final cell = tx + ty * grid.x + tz * grid.x * grid.y;
  final headerRow = (cell / 4.0).floorToDouble();
  final header = _listTexel(b, cell - headerRow * 4.0, depth.z + headerRow);
  final count = (header.y + 0.5).floor();

  final total = Vector3.zero();
  for (var i = 0; i < _kFogCellLights && i < count; i++) {
    final entry = header.x + i;
    final entryRow = (entry / 16.0).floorToDouble();
    final within = entry - entryRow * 16.0;
    final texel = (within / 4.0).floorToDouble();
    final four = _listTexel(b, texel, depth.w + entryRow);
    final lane = within - texel * 4.0;
    final row = lane < 0.5
        ? four.x
        : lane < 1.5
        ? four.y
        : lane < 2.5
        ? four.z
        : four.w;

    final position = _listTexel(b, 0.0, row);
    final colour = _listTexel(b, 1.0, row);
    final direction = _listTexel(b, 2.0, row);
    final cone = _listTexel(b, 3.0, row);
    final type = position.w;
    final toLight = Vector3(position.x, position.y, position.z) - world;
    final lightDistance = toLight.length;
    if (!(type > 0.5 && type < 2.5 && lightDistance > 1e-4)) continue;
    final l = toLight / lightDistance;

    var falloff = attenuation(lightDistance, direction.w);
    if (type > 1.5) {
      final aim = Vector3(direction.x, direction.y, direction.z)..normalize();
      final cosAngle = aim.dot(-l);
      falloff *= ((cosAngle - cone.y) / (cone.x - cone.y)).clamp(0.0, 1.0);
    }
    total.addScaled(
      Vector3(colour.x, colour.y, colour.z),
      colour.w * falloff * _henyeyGreenstein(along.dot(l), g),
    );
  }
  return total;
}

/// `volumetric_fog_upsample.frag`: the four nearest fog texels, weighed by
/// their bilinear share and by how near their depth is to the pixel's.
final class VolumetricFogUpsampleShader implements CpuFragmentShader {
  const VolumetricFogUpsampleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneTexture = b.textures['scene_texture'];
    if (sceneTexture == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final scene = sceneTexture.sample(v[0], v[1]);
    final fogTexture = b.textures['fog_texture'];
    final surface = b.textures['surface_texture'];
    if (fogTexture == null || surface == null) return scene;

    final info = b.vec4('FogUpsampleInfo', 'size', Vector4.zero());
    final sizeX = info.x;
    final sizeY = info.y;
    double depthAt(double u, double w) {
      final depth = surface.sample(u, w).w;
      return depth > 0.0 ? depth : 1e6;
    }

    final atX = v[0] * math.max(sizeX, 1.0) - 0.5;
    final atY = v[1] * math.max(sizeY, 1.0) - 0.5;
    final baseX = atX.floorToDouble();
    final baseY = atY.floorToDouble();
    final fx = atX - baseX;
    final fy = atY - baseY;
    final here = depthAt(v[0], v[1]);

    final sum = Vector4.zero();
    var weight = 0.0;
    void tap(double cellX, double cellY, double share) {
      final u = (cellX.clamp(0.0, sizeX - 1.0) + 0.5) / sizeX;
      final w = (cellY.clamp(0.0, sizeY - 1.0) + 0.5) / sizeY;
      final difference = (depthAt(u, w) - here).abs() / math.max(here, 1e-3);
      final tapWeight = share / (0.01 + difference);
      sum.addScaled(fogTexture.sample(u, w), tapWeight);
      weight += tapWeight;
    }

    tap(baseX, baseY, (1.0 - fx) * (1.0 - fy));
    tap(baseX + 1.0, baseY, fx * (1.0 - fy));
    tap(baseX, baseY + 1.0, (1.0 - fx) * fy);
    tap(baseX + 1.0, baseY + 1.0, fx * fy);
    final fog = weight > 1e-6
        ? (sum..scale(1.0 / weight))
        : Vector4(0.0, 0.0, 0.0, 1.0);

    return Vector4(
      scene.x * fog.w + fog.x,
      scene.y * fog.w + fog.y,
      scene.z * fog.w + fog.z,
      scene.w,
    );
  }
}
