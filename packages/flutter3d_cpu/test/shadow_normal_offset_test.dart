/// The sun's normal offset lifts a point just clear of its own plane, and no
/// further.
///
///     dart test test/shadow_normal_offset_test.dart
///
/// A double-sided caster writes its lit faces into the map, so a lit point
/// compares against the plane it lies on. The offset along the normal has to
/// clear that plane for every tap of the 3×3 kernel, which reaches a texel
/// and a half across: 1.5·texel·sinθ, taken along each axis of the map. It
/// used to be a whole texel plus 1/cos² of the slope on top, several texels
/// at a glancing sun, and a thin caster close above a floor left no shadow
/// on it. Both sides are pinned here against a map drawn by hand, through an
/// identity projection: world x and y across the tile, world z as the depth,
/// the light looking down +z.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _tile = 64;

/// One texel of the tile in metres: the identity maps two metres across it.
const double _texel = 2.0 / _tile;

/// A one-cascade map whose texel centres hold [depth] of the world x and y
/// they stand over.
BoundTexture _map(double Function(double x, double y) depth) {
  final texture = CpuTexture(_tile, _tile, TextureFormat.r32g32b32a32Float);
  for (var j = 0; j < _tile; j++) {
    for (var i = 0; i < _tile; i++) {
      final x = (i + 0.5) / _tile * 2.0 - 1.0;
      final y = 1.0 - (j + 0.5) / _tile * 2.0;
      texture.pixels[(j * _tile + i) * 4] = depth(x, y);
    }
  }
  return BoundTexture(texture, SamplerOptions.nearestClamp);
}

/// The light that survives at [world] with [normal], against [map].
double _shadowAt(BoundTexture map, Vector3 world, Vector3 normal) {
  final surface = Surface(
    Vector3.all(1.0),
    1.0,
    normal,
    world,
    Vector3.zero(),
    0.0,
    1.0,
    Vector3(0.0, 0.0, -1.0),
    1.0,
    Vector4.zero(),
  );
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'FragInfo': <String, Float32List>{
        // One texel across, a small bias, no flat offset, full strength.
        'shadow_params': Float32List.fromList(<double>[
          1.0 / _tile,
          1e-4,
          0.0,
          1.0,
        ]),
        'frame_params': Float32List(4),
        'shadow_cascades': Float32List.fromList(<double>[
          100.0,
          200.0,
          1.0,
          1.0 / _tile,
        ]),
        'shadow_bias': Float32List.fromList(<double>[1e-4, 1e-4, 1e-4, 0]),
        'shadow_matrix': Float32List.fromList(Matrix4.identity().storage),
        'camera_position': Float32List(4),
        'ambient_ground': Float32List(4),
      },
    },
    <String, BoundTexture>{'shadow_texture': map},
  );
  return shadowFactor(surface, bindings, 0, -normal.z);
}

/// The plane through depth 0.5 at the centre whose normal leans [angle]
/// radians from the light, in the direction [heading] across the map.
({BoundTexture map, Vector3 normal, double Function(double, double) depth})
_plane(double angle, double heading, {double lift = 0.0}) {
  final slope = math.tan(angle);
  final a = slope * math.cos(heading);
  final b = slope * math.sin(heading);
  double depth(double x, double y) => 0.5 + a * x + b * y;
  return (
    map: _map((x, y) => depth(x, y) - lift),
    normal: Vector3(a, b, -1.0)..normalize(),
    depth: depth,
  );
}

void main() {
  test('a plane the map recorded does not shadow itself at any slope', () {
    var points = 0;
    for (final degrees in const <double>[0, 15, 30, 45, 60, 70]) {
      // Along an axis of the map and across its diagonal, where a texel
      // reaches furthest.
      for (final heading in const <double>[0.0, math.pi / 4, 2.0]) {
        final plane = _plane(degrees * math.pi / 180.0, heading);
        for (var k = 0; k < 40; k++) {
          // Fractions of a texel all over, so every place a point can sit
          // within its texel is tried.
          final x = -0.1 + k * 0.137 * _texel;
          final y = 0.05 - k * 0.291 * _texel;
          final world = Vector3(x, y, plane.depth(x, y));
          // Mutation: a texel times sinθ rather than a texel and a half, or
          // the x axis alone, and points near a texel's edge see their own
          // plane one tap over.
          expect(
            _shadowAt(plane.map, world, plane.normal),
            1.0,
            reason: '$degrees° heading $heading at ($x, $y)',
          );
          points++;
        }
      }
    }
    expect(points, 720);
  });

  test('a caster just above a floor lit head on still shadows it', () {
    // Half a texel of air between them. With the light straight down there
    // is no slope to clear and no offset beyond the flat one: the old texel
    // of it lifted the floor over the caster and lit it.
    final floor = _plane(0.0, 0.0, lift: 0.5 * _texel);
    for (var k = 0; k < 10; k++) {
      final x = k * 0.173 * _texel;
      final world = Vector3(x, 0.0, floor.depth(x, 0.0));
      expect(_shadowAt(floor.map, world, floor.normal), 0.0);
    }
  });

  test('a caster close above a slope under a low sun still shadows it', () {
    // Sixty degrees off, six texels of depth between them along the light.
    // The offset clears the slope by 1.5·sin60°/cos60° ≈ 2.6 texels, and
    // the kernel's taps downhill come to 2.6 more: every one under the
    // caster. The old offset, 4.5 texels along the normal, cleared it by
    // nine and looked out over the caster's edge.
    final slope = _plane(60.0 * math.pi / 180.0, 0.0, lift: 6.0 * _texel);
    for (var k = 0; k < 10; k++) {
      final x = k * 0.173 * _texel;
      final world = Vector3(x, 0.0, slope.depth(x, 0.0));
      expect(_shadowAt(slope.map, world, slope.normal), 0.0);
    }
  });
}
