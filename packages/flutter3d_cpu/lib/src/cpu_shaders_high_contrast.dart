/// The high-contrast look, on the software rasteriser — `N9`.
///
/// `post/outline_mask.frag` and `post/high_contrast.frag` line for line: the
/// marked nodes' colours written where the scene shows them, and the frame
/// flattened within each surface, pushed apart in tone, outlined where the
/// geometry steps or turns and ringed in each mark's colour. The GLSL carries
/// the argument for every choice; what is here is the arithmetic, kept in the
/// same order so a difference between the sets points at one line.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart' show decodeOctahedral;

/// `post/outline_mask.frag`: a marked node, drawn through the velocity vertex
/// stages — `v_depth` is varying eight — in its outline colour, and nothing
/// behind what the opaque scene drew there.
final class OutlineMaskShader implements CpuFragmentShader {
  const OutlineMaskShader();

  static const String _block = 'OutlineMaskInfo';

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final surface = b.textures['surface_texture'];
    if (surface != null) {
      final target = b.vec4(_block, 'target', Vector4.zero());
      // `FragCoordFromTop`.
      final y = target.z > 0.0 ? target.z - c.coord.y : c.coord.y;
      final stored = surface.sample(c.coord.x * target.x, y * target.y).w;
      if (stored > 0.0 && v[8] > stored * (1.0 + target.w) + 1e-3) return null;
    }
    final colour = b.vec4(_block, 'color', Vector4.zero());
    return Vector4(colour.x, colour.y, colour.z, 1.0);
  }
}

/// `post/high_contrast.frag`: flatten, tone, outline, roles.
final class HighContrastShader implements CpuFragmentShader {
  const HighContrastShader();

  static const String _block = 'HighContrastInfo';

  /// `DepthBend`: how far [centre] bends off the line through its two
  /// neighbours, as a share of itself; a silhouette when either is empty.
  static double _bend(double a, double centre, double b) =>
      a <= 0.0 || b <= 0.0 ? 1e6 : (a + b - 2.0 * centre).abs() / centre;

  /// The eight directions the ring looks in, cardinal first, as the GLSL
  /// lists them.
  static const List<(double, double)> _directions = <(double, double)>[
    (1.0, 0.0),
    (-1.0, 0.0),
    (0.0, 1.0),
    (0.0, -1.0),
    (1.0, 1.0),
    (-1.0, 1.0),
    (1.0, -1.0),
    (-1.0, -1.0),
  ];

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneTexture = b.textures['scene_texture'];
    if (sceneTexture == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final u = v[0];
    final w = v[1];
    final scene = sceneTexture.sample(u, w);

    final look = b.vec4(_block, 'look', Vector4.zero());
    final edges = b.vec4(_block, 'edges', Vector4.zero());
    final line = b.vec4(_block, 'line', Vector4.zero());
    final screen = b.vec4(_block, 'screen', Vector4.zero());
    final surfaceTexture = screen.z > 0.5
        ? b.textures['surface_texture']
        : null;
    final maskTexture = screen.w > 0.5 ? b.textures['mask_texture'] : null;

    final surface = surfaceTexture?.sample(u, w) ?? Vector4.zero();
    final depth = surface.w;
    final normal = depth > 0.0
        ? decodeOctahedral(surface.x, surface.y)
        : Vector3(0.0, 0.0, 1.0);
    final bend = math.max(edges.x, 1e-4);
    final turn = math.max(edges.y, 1e-4);
    var colour = Vector3(scene.x, scene.y, scene.z);

    // Flatten: the mean of the taps on this pixel's surface.
    final flatten = look.x.clamp(0.0, 1.0);
    if (surfaceTexture != null && depth > 0.0 && flatten > 0.0) {
      final spacing = math.max(edges.w, 1.0);
      final sum = Vector3.zero();
      var count = 0;
      for (var y = -2; y <= 2; y++) {
        for (var x = -2; x <= 2; x++) {
          final tu = u + x * screen.x * spacing;
          final tv = w + y * screen.y * spacing;
          final tap = surfaceTexture.sample(tu, tv);
          final ring = math.max(math.max(x.abs(), y.abs()), 1);
          final same =
              tap.w > 0.0 &&
              (tap.w - depth).abs() <= bend * depth * ring &&
              1.0 - decodeOctahedral(tap.x, tap.y).dot(normal) < turn;
          if (same) {
            final texel = sceneTexture.sample(tu, tv);
            sum.add(Vector3(texel.x, texel.y, texel.z));
            count++;
          }
        }
      }
      if (count > 0) {
        final mean = sum / count.toDouble();
        colour = colour + (mean - colour) * flatten;
      }
    }

    // Tone: toward the luma, then apart about mid grey.
    final luma = colour.x * 0.2126 + colour.y * 0.7152 + colour.z * 0.0722;
    final keep = look.z.clamp(0.0, 1.0);
    final gain = math.max(look.y, 0.0);
    double toned(double channel) =>
        ((luma + (channel - luma) * keep - 0.5) * gain + 0.5).clamp(0.0, 1.0);
    colour = Vector3(toned(colour.x), toned(colour.y), toned(colour.z));

    // Outline, wherever the geometry steps or turns.
    final reach = edges.z;
    if (surfaceTexture != null && depth > 0.0 && reach > 0.0) {
      final dx = screen.x * reach;
      final dy = screen.y * reach;
      final left = surfaceTexture.sample(u - dx, w);
      final right = surfaceTexture.sample(u + dx, w);
      final up = surfaceTexture.sample(u, w - dy);
      final down = surfaceTexture.sample(u, w + dy);
      // An axis whose tap falls off the frame is left out: clamped, it is
      // this pixel again, and the bend becomes the step.
      final across = u - dx >= 0.0 && u + dx <= 1.0;
      final along = w - dy >= 0.0 && w + dy <= 1.0;
      final bent = math.max(
        across ? _bend(left.w, depth, right.w) : 0.0,
        along ? _bend(up.w, depth, down.w) : 0.0,
      );
      final turned = <Vector4>[left, right, up, down]
          .where((tap) => tap.w > 0.0)
          .map((tap) => 1.0 - decodeOctahedral(tap.x, tap.y).dot(normal))
          .fold(0.0, math.max);
      if (bent >= bend || turned >= turn) {
        colour = Vector3(line.x, line.y, line.z);
      }
    }

    // Roles: a share of the mark's colour inside, a ring of it outside.
    final ringWidth = line.w;
    if (maskTexture != null) {
      final own = maskTexture.sample(u, w);
      if (own.w > 0.5) {
        final fill = look.w.clamp(0.0, 1.0);
        colour = colour + (Vector3(own.x, own.y, own.z) - colour) * fill;
      } else if (ringWidth > 0.0) {
        Vector4? found;
        for (var i = 1; i <= 4 && found == null; i++) {
          if (i > ringWidth) break;
          for (final (ox, oy) in _directions) {
            final tap = maskTexture.sample(
              u + ox * screen.x * i,
              w + oy * screen.y * i,
            );
            if (found == null && tap.w > 0.5) found = tap;
          }
        }
        if (found != null) colour = Vector3(found.x, found.y, found.z);
      }
    }

    return Vector4(colour.x, colour.y, colour.z, scene.w);
  }
}
