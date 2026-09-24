/// A grid of irradiance probes — `gfx-81n`.
///
/// **What this is for.** The engine's indirect diffuse light came from two
/// places, and neither of them is in the room: an environment map's roughest
/// level, which is the sky seen from one point, and a baked lightmap, which is
/// a texture somebody generated beforehand. Neither answers "what colour is the
/// light arriving at this spot, from this direction, right now" — so a red wall
/// lit by a white lamp does not tint the white wall facing it, and moving the
/// lamp changes nothing but the direct term.
///
/// A field of probes answers it. Space is divided into a grid, each cell corner
/// holds a probe, and a probe holds the light arriving at it from every
/// direction. A surface reads the eight probes around it and weighs them.
///
/// **Octahedral tiles, with a gutter.** A probe's sphere of directions is
/// stored as a square: the octahedral mapping folds a sphere onto one, and
/// unlike a cube map it needs no face selection and no seams inside the square.
/// The gutter is the one detail that is not obvious and is not optional — a
/// bilinear read near the edge of a tile reaches a texel *outside* it, and
/// without a border carrying the wrapped-around value that texel belongs to
/// the next probe. The symptom is a grid of bright dots, one per probe, which
/// reads as a lighting artefact rather than as an addressing bug.
///
/// **Two moments of depth, not one.** Alongside the irradiance each probe keeps
/// the mean distance to what it can see in each direction and the mean *square*
/// of that distance. The pair gives Chebyshev's inequality, which answers "how
/// likely is it that this point is visible from this probe" with a number
/// rather than a yes — and that is what stops light leaking through a wall,
/// which is the failure every probe scheme has and the one that makes a dark
/// room glow along its edges.
///
/// Nothing here gathers light; see `irradiance_gather.dart`. Nothing here
/// draws.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// A direction as a point in the unit square, and back.
///
/// The octahedral mapping: fold the sphere onto an octahedron, unfold that onto
/// a square. Continuous everywhere inside the square, which is what lets a
/// bilinear read between two directions mean anything.
Vector2 encodeOctahedral(Vector3 direction, [Vector2? out]) {
  // **A zero vector is not a direction, and it arrives.** A point that lands
  // exactly on a probe has no direction to it — which is not a contrived case:
  // a field laid out over a room puts probes on round numbers, and an object
  // centred on one is the ordinary way to place it. Dividing by the zero sum
  // below gives a NaN, and `floor` on a NaN throws from inside the encode with
  // nothing in the message about where it came from.
  if (direction.length2 <= 0.0) {
    return (out ?? Vector2.zero())..setValues(0.5, 0.5);
  }
  final n = direction.normalized();
  final sum = n.x.abs() + n.y.abs() + n.z.abs();
  var x = n.x / sum;
  var y = n.y / sum;
  if (n.z < 0.0) {
    final ax = x;
    final ay = y;
    x = (1.0 - ay.abs()) * (ax >= 0.0 ? 1.0 : -1.0);
    y = (1.0 - ax.abs()) * (ay >= 0.0 ? 1.0 : -1.0);
  }
  return (out ?? Vector2.zero())..setValues(x * 0.5 + 0.5, y * 0.5 + 0.5);
}

/// The inverse of [encodeOctahedral].
Vector3 decodeOctahedral(double u, double v, [Vector3? out]) {
  final x = u * 2.0 - 1.0;
  final y = v * 2.0 - 1.0;
  final z = 1.0 - x.abs() - y.abs();
  final t = math.max(-z, 0.0);
  final result = (out ?? Vector3.zero())
    ..setValues(x + (x >= 0.0 ? -t : t), y + (y >= 0.0 ? -t : t), z);
  if (result.length2 > 0.0) result.normalize();
  return result;
}

/// A grid of probes over a box.
final class IrradianceField {
  IrradianceField({
    required this.origin,
    required this.spacing,
    required this.countX,
    required this.countY,
    required this.countZ,
    this.tile = 8,
    this.depthTile = 16,
  }) : assert(countX > 1 && countY > 1 && countZ > 1, 'a field needs a cell'),
       assert(tile > 1 && depthTile > 1, 'a tile needs an interior') {
    final probes = countX * countY * countZ;
    irradiance = Float32List(probes * _stride(tile) * _stride(tile) * 3);
    depth = Float32List(probes * _stride(depthTile) * _stride(depthTile) * 2);
    active = Uint8List(probes)..fillRange(0, probes, 1);
  }

  /// Where probe (0, 0, 0) stands.
  final Vector3 origin;

  /// How far apart neighbouring probes are, per axis.
  final Vector3 spacing;

  final int countX;
  final int countY;
  final int countZ;

  /// The interior of one probe's octahedral tile, in texels a side. The stored
  /// tile is two wider, which is the gutter.
  final int tile;

  /// The same for the depth moments, larger because the visibility test is what
  /// decides whether light crosses a wall and a coarse one crosses it.
  final int depthTile;

  /// `rgb` per texel, per probe.
  late final Float32List irradiance;

  /// Mean distance and mean square distance per texel, per probe.
  late final Float32List depth;

  /// How many probes the renderer updates a frame on the GPU — `L4`. Nought,
  /// the default, leaves the field exactly what was baked; above it, the
  /// renderer draws that many probes' views each frame, round robin, and
  /// folds them into the atlas the lit stages read. Needs a device with cube
  /// textures and a second colour attachment; elsewhere the bake stands.
  int gpuUpdates = 0;

  /// How much of a probe's old value survives each GPU update, nought to
  /// one — `L4`. Higher is steadier and slower to follow a changed room.
  double hysteresis = 0.9;

  /// Whether each probe stands somewhere worth reading.
  ///
  /// **A probe inside a wall is the other way a field goes wrong**, and it is
  /// not rare: a grid laid over a room puts probes wherever the arithmetic says,
  /// including inside the furniture. Such a probe sees the inside of what it is
  /// in — black, and at no distance — so a surface near it reads black no matter
  /// what is actually lighting the room. Marking it and skipping it is what
  /// `gatherProbe` does; the alternative the published schemes use is to move
  /// the probe, which needs a search this does not have.
  late final Uint8List active;

  int get probeCount => countX * countY * countZ;

  static int _stride(int interior) => interior + 2;

  /// Bumped whenever the field's contents change — `L3`: by every write here
  /// and by [fillGutters], which is how a bake finishes. The renderer uploads
  /// the atlas again when this moved and not otherwise. Anything that writes
  /// [irradiance], [depth] or [active] directly calls [markChanged].
  int get version => _version;
  int _version = 0;

  /// Says the contents changed, for a writer that went past the methods here.
  void markChanged() => _version++;

  /// The field as one float texture — `L3`.
  ///
  /// Every probe's irradiance tile (gutter included) in a grid of [columns]
  /// tiles across, rgb with the probe's [active] flag in alpha; below them,
  /// starting at row [momentsTop], every probe's depth tile in the same grid,
  /// mean and mean square in red and green. Row-major from the top, four
  /// floats a texel. `lib/irradiance.glsl` reads it.
  ({int width, int height, int columns, int momentsTop, Float32List texels})
  toAtlas() {
    final probes = probeCount;
    final columns = math.sqrt(probes).ceil();
    final rows = (probes + columns - 1) ~/ columns;
    final irradianceStride = _stride(tile);
    final depthStride = _stride(depthTile);
    final width =
        columns *
        (irradianceStride > depthStride ? irradianceStride : depthStride);
    final momentsTop = rows * irradianceStride;
    final height = momentsTop + rows * depthStride;
    final texels = Float32List(width * height * 4);

    for (var probe = 0; probe < probes; probe++) {
      final column = probe % columns;
      final row = probe ~/ columns;
      final flag = active[probe].toDouble();
      for (var y = 0; y < irradianceStride; y++) {
        for (var x = 0; x < irradianceStride; x++) {
          final from =
              ((probe * irradianceStride + y) * irradianceStride + x) * 3;
          final to =
              ((row * irradianceStride + y) * width +
                  column * irradianceStride +
                  x) *
              4;
          texels[to] = irradiance[from];
          texels[to + 1] = irradiance[from + 1];
          texels[to + 2] = irradiance[from + 2];
          texels[to + 3] = flag;
        }
      }
      for (var y = 0; y < depthStride; y++) {
        for (var x = 0; x < depthStride; x++) {
          final from = ((probe * depthStride + y) * depthStride + x) * 2;
          final to =
              ((momentsTop + row * depthStride + y) * width +
                  column * depthStride +
                  x) *
              4;
          texels[to] = depth[from];
          texels[to + 1] = depth[from + 1];
          texels[to + 3] = 1.0;
        }
      }
    }
    return (
      width: width,
      height: height,
      columns: columns,
      momentsTop: momentsTop,
      texels: texels,
    );
  }

  /// The index of the probe at grid position [x], [y], [z].
  int probeIndex(int x, int y, int z) => (z * countY + y) * countX + x;

  /// Where that probe stands in the world.
  Vector3 probePosition(int x, int y, int z, [Vector3? out]) =>
      (out ?? Vector3.zero())..setValues(
        origin.x + spacing.x * x,
        origin.y + spacing.y * y,
        origin.z + spacing.z * z,
      );

  /// Writes [colour] as the irradiance probe [probe] receives from [direction].
  void writeIrradiance(int probe, Vector3 direction, Vector3 colour) {
    _version++;
    final uv = encodeOctahedral(direction);
    final at = _texelOf(probe, uv, tile, 3);
    irradiance[at] = colour.x;
    irradiance[at + 1] = colour.y;
    irradiance[at + 2] = colour.z;
  }

  /// Writes the two moments probe [probe] sees along [direction].
  void writeDepth(int probe, Vector3 direction, double distance) {
    _version++;
    final uv = encodeOctahedral(direction);
    final at = _texelOf(probe, uv, depthTile, 2);
    depth[at] = distance;
    depth[at + 1] = distance * distance;
  }

  /// The direction texel ([tx], [ty]) of a tile [interior] wide stands for.
  Vector3 texelDirection(int tx, int ty, int interior, [Vector3? out]) =>
      decodeOctahedral((tx + 0.5) / interior, (ty + 0.5) / interior, out);

  /// Writes one texel of the irradiance tile directly.
  ///
  /// **What a tile holds is irradiance, not radiance**, and the difference is
  /// the whole reason this exists beside [writeIrradiance]. A texel is not
  /// "what arrived from this direction"; it is "what a surface facing this
  /// direction receives", which is the incoming light convolved with a cosine
  /// over the whole hemisphere. A field filled the other way lights a
  /// floor-facing surface from the ceiling and from nothing else, and a wall to
  /// one side tints nothing at all — which is exactly the effect the row exists
  /// to produce.
  void writeIrradianceTexel(int probe, int tx, int ty, Vector3 colour) {
    _version++;
    final stride = _stride(tile);
    final at = ((probe * stride + ty + 1) * stride + tx + 1) * 3;
    irradiance[at] = colour.x;
    irradiance[at + 1] = colour.y;
    irradiance[at + 2] = colour.z;
  }

  /// Writes one texel of the depth tile directly. See [writeIrradianceTexel].
  void writeDepthTexel(int probe, int tx, int ty, double mean, double square) {
    _version++;
    final stride = _stride(depthTile);
    final at = ((probe * stride + ty + 1) * stride + tx + 1) * 2;
    depth[at] = mean;
    depth[at + 1] = square;
  }

  int _texelOf(int probe, Vector2 uv, int interior, int channels) {
    final stride = _stride(interior);
    // The interior starts one texel in, which is what the gutter is.
    final x = (uv.x * interior).floor().clamp(0, interior - 1) + 1;
    final y = (uv.y * interior).floor().clamp(0, interior - 1) + 1;
    return ((probe * stride + y) * stride + x) * channels;
  }

  /// Fills every tile's border from the interior it wraps around to.
  ///
  /// **Called once after a probe is written, and the field is wrong without
  /// it.** A bilinear read near a tile's edge reaches outside the interior; the
  /// octahedral mapping says which interior texel that outside one is the same
  /// direction as, and copying it there is what makes the read continuous. Skip
  /// this and every probe shows as a bright dot.
  void fillGutters() {
    _version++;
    _fillGutter(irradiance, tile, 3);
    _fillGutter(depth, depthTile, 2);
  }

  void _fillGutter(Float32List data, int interior, int channels) {
    final stride = _stride(interior);
    int index(int probe, int x, int y) =>
        ((probe * stride + y) * stride + x) * channels;

    for (var probe = 0; probe < probeCount; probe++) {
      // The octahedral square wraps by reflecting through the opposite edge,
      // reversed — the two halves of the unfolded octahedron meet there.
      for (var i = 0; i < interior; i++) {
        final mirror = interior - 1 - i;
        // Top and bottom rows.
        _copy(
          data,
          index(probe, 1 + mirror, 1),
          index(probe, 1 + i, 0),
          channels,
        );
        _copy(
          data,
          index(probe, 1 + mirror, interior),
          index(probe, 1 + i, interior + 1),
          channels,
        );
        // Left and right columns.
        _copy(
          data,
          index(probe, 1, 1 + mirror),
          index(probe, 0, 1 + i),
          channels,
        );
        _copy(
          data,
          index(probe, interior, 1 + mirror),
          index(probe, interior + 1, 1 + i),
          channels,
        );
      }
      // The four corners take the diagonally opposite interior texel.
      _copy(
        data,
        index(probe, interior, interior),
        index(probe, 0, 0),
        channels,
      );
      _copy(
        data,
        index(probe, 1, interior),
        index(probe, interior + 1, 0),
        channels,
      );
      _copy(
        data,
        index(probe, interior, 1),
        index(probe, 0, interior + 1),
        channels,
      );
      _copy(
        data,
        index(probe, 1, 1),
        index(probe, interior + 1, interior + 1),
        channels,
      );
    }
  }

  static void _copy(Float32List data, int from, int to, int channels) {
    for (var c = 0; c < channels; c++) {
      data[to + c] = data[from + c];
    }
  }

  /// The irradiance stored for [direction] at probe [probe].
  Vector3 readIrradiance(int probe, Vector3 direction, [Vector3? out]) {
    final uv = encodeOctahedral(direction);
    final at = _texelOf(probe, uv, tile, 3);
    return (out ?? Vector3.zero())
      ..setValues(irradiance[at], irradiance[at + 1], irradiance[at + 2]);
  }

  /// The two moments stored for [direction] at probe [probe].
  ({double mean, double meanSquare}) readDepth(int probe, Vector3 direction) {
    final uv = encodeOctahedral(direction);
    final at = _texelOf(probe, uv, depthTile, 2);
    return (mean: depth[at], meanSquare: depth[at + 1]);
  }

  /// How much of probe [probe] a point [distance] away along [direction] can
  /// see, by Chebyshev's inequality.
  ///
  /// **One over two, rather than in or out.** A binary visibility test makes a
  /// hard edge exactly where the probes happen to sit; the inequality gives the
  /// *probability* that a sample at this distance is in front of what the probe
  /// can see, which fades. Nearer than the mean is fully visible; past it, the
  /// variance decides how quickly the weight falls off — a probe looking at a
  /// flat wall has almost none and cuts sharply, one looking into a corner has
  /// a lot and stays soft.
  double visibility(int probe, Vector3 direction, double distance) {
    final moments = readDepth(probe, direction);
    if (distance <= moments.mean) return 1.0;
    final variance = math.max(
      moments.meanSquare - moments.mean * moments.mean,
      1e-6,
    );
    final difference = distance - moments.mean;
    final chebyshev = variance / (variance + difference * difference);
    // Cubed, which is the standard sharpening: the raw inequality is a loose
    // bound and leaves a haze where a wall should be opaque.
    return math.max(chebyshev * chebyshev * chebyshev, 0.0);
  }

  /// The irradiance arriving at [position] on a surface facing [normal].
  ///
  /// The eight probes around it, weighted three ways: trilinearly by where the
  /// point sits in its cell, by how much each probe is on the side the surface
  /// faces, and by whether the probe can see the point at all.
  Vector3 sample(Vector3 position, Vector3 normal, [Vector3? out]) {
    final result = (out ?? Vector3.zero())..setZero();

    final gx = (position.x - origin.x) / spacing.x;
    final gy = (position.y - origin.y) / spacing.y;
    final gz = (position.z - origin.z) / spacing.z;

    final baseX = gx.floor().clamp(0, countX - 2);
    final baseY = gy.floor().clamp(0, countY - 2);
    final baseZ = gz.floor().clamp(0, countZ - 2);
    final fx = (gx - baseX).clamp(0.0, 1.0);
    final fy = (gy - baseY).clamp(0.0, 1.0);
    final fz = (gz - baseZ).clamp(0.0, 1.0);

    final unit = normal.normalized();
    final toProbe = Vector3.zero();
    final at = Vector3.zero();
    final colour = Vector3.zero();
    var total = 0.0;

    for (var corner = 0; corner < 8; corner++) {
      final ox = corner & 1;
      final oy = (corner >> 1) & 1;
      final oz = (corner >> 2) & 1;
      final probe = probeIndex(baseX + ox, baseY + oy, baseZ + oz);
      if (active[probe] == 0) continue;
      probePosition(baseX + ox, baseY + oy, baseZ + oz, at);

      // **Floored rather than taken as it comes.** On a lattice point the
      // trilinear weights collapse onto one probe and every other corner gets
      // nothing — so a point standing exactly on a probe that turned out to be
      // inside a wall reads black, with seven live probes around it saying
      // otherwise. That is not a corner case: a field laid over a room puts
      // probes on round numbers and objects get placed on them. The floor is
      // small enough to be invisible where the interpolation is doing its job.
      var weight = math.max(
        (ox == 1 ? fx : 1.0 - fx) *
            (oy == 1 ? fy : 1.0 - fy) *
            (oz == 1 ? fz : 1.0 - fz),
        0.001,
      );

      toProbe
        ..setFrom(at)
        ..sub(position);
      final distance = toProbe.length;
      if (distance <= 1e-6) {
        // Standing on the probe. There is no direction to it and no wall
        // between them, so it contributes its trilinear weight and nothing
        // else modifies it — asking the visibility test about a direction that
        // does not exist is the version of this that throws.
        readIrradiance(probe, unit, colour);
        result.addScaled(colour, weight);
        total += weight;
        continue;
      }
      toProbe.scale(1.0 / distance);

      // **Smoothed rather than clamped at zero.** A probe exactly edge-on
      // contributes nothing under `max(dot, 0)`, and the discontinuity shows as
      // a seam running along every surface that happens to lie in a probe
      // plane. Half the cosine plus a half, squared, falls to zero smoothly.
      final facing = unit.dot(toProbe) * 0.5 + 0.5;
      weight *= facing * facing;
      if (weight <= 0.0) continue;

      weight *= visibility(probe, -toProbe, distance);
      if (weight <= 0.0) continue;

      readIrradiance(probe, unit, colour);
      result.addScaled(colour, weight);
      total += weight;
    }

    // Normalised by what actually contributed, so a point where most probes are
    // occluded reads as the colour of the ones that can see it rather than as
    // that colour divided by eight.
    if (total > 1e-6) result.scale(1.0 / total);
    return result;
  }
}
