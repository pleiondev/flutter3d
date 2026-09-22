/// Draco's prediction schemes — `gfx-82n`.
///
/// **An attribute is stored as how wrong a guess was.** The decoder makes the
/// same guess the encoder made, from values it has already decoded, and adds
/// the stored *correction*. The better the guess the smaller the corrections,
/// and small numbers are what the entropy coder in `draco_buffer.dart` is good
/// at. Everything here is a way of guessing:
///
/// * **difference** — the previous value. Needs nothing but the stream.
/// * **parallelogram** — across an edge from a finished triangle, the fourth
///   corner of the parallelogram: `next + previous − opposite`. What a
///   position or a generic attribute gets at the encoder's default speed.
/// * **constrained multi-parallelogram** — up to four of those, from every
///   finished face round the vertex, averaged, with a stored bit per
///   parallelogram saying "not this one, it lies across a crease".
/// * **texture coordinates, portable** — the triangle's shape in space is
///   known from the positions, so its shape in UV space is known up to a
///   mirror; one stored bit picks the side.
/// * **geometric normal** — the area-weighted face normals round the vertex,
///   computed from the positions; one stored bit says whether it came out
///   backwards.
///
/// Those are the five a bitstream 2.2 encoder can write. The two retired
/// schemes (`MULTI_PARALLELOGRAM` and `TEX_COORDS_DEPRECATED`) are refused by
/// name in `draco_decoder.dart` rather than here.
///
/// **Integer arithmetic, and the rounding is the format.** Every guess is
/// computed in the quantised integers, never in floats, because encoder and
/// decoder must agree to the last bit: a guess that differs by one turns a
/// correction of zero into a value that is off by one, and the next guess is
/// built on that. Truncating division, wrap-around addition and the integer
/// square root below are each what the reference does at that line.
///
/// Follows the files under `compression/attributes/prediction_schemes/`.
library;

import 'dart:typed_data';

import 'draco_buffer.dart';
import 'draco_corner_table.dart';
import 'draco_octahedron.dart';
import 'draco_traversal.dart';

Never _fail(String message) => throw DracoException(message);

/// Whether `int` is a JavaScript number here. Compiled to JavaScript, `0` and
/// `0.0` are one value; on the VM they are not.
const bool _intsAreDoubles = identical(0, 0.0);

/// What turns a guess and a correction into a value.
abstract interface class PredictionTransform {
  /// Writes `original` for the [components] corrections at [at] in [data],
  /// in place, given the guess at [predictedAt] in [predicted].
  void computeOriginal(
    Int32List predicted,
    int predictedAt,
    Int32List data,
    int at,
  );
}

/// `PredictionSchemeWrapDecodingTransform`.
///
/// The guess is clamped into the range the encoder measured, the correction is
/// added, and the sum is wrapped back into that range — which is what lets a
/// correction that would overshoot be written as a small number going the
/// other way round.
final class WrapTransform implements PredictionTransform {
  WrapTransform(DracoBuffer buffer, this.components)
    : minValue = buffer.readInt32(),
      maxValue = buffer.readInt32() {
    if (minValue > maxValue) _fail('wrap transform range is inverted');
    if (maxValue - minValue >= 0x7FFFFFFF) {
      _fail('wrap transform range does not fit in 32 bits');
    }
  }

  final int components;
  final int minValue;
  final int maxValue;
  late final int _span = maxValue - minValue + 1;

  @override
  void computeOriginal(
    Int32List predicted,
    int predictedAt,
    Int32List data,
    int at,
  ) {
    for (var c = 0; c < components; c++) {
      final guess = predicted[predictedAt + c].clamp(minValue, maxValue);
      // Added as unsigned 32-bit and read back signed: the reference relies on
      // that wrap, and an out-of-range correction lands differently without it.
      final sum = (guess + data[at + c]).toSigned(32);
      data[at + c] = sum > maxValue
          ? sum - _span
          : sum < minValue
          ? sum + _span
          : sum;
    }
  }
}

/// `PredictionSchemeNormalOctahedronCanonicalizedDecodingTransform`: the sum
/// happens in a frame the guess itself picks — see `draco_octahedron.dart`.
final class OctahedronTransform implements PredictionTransform {
  OctahedronTransform(DracoBuffer buffer) : box = _boxFrom(buffer.readInt32()) {
    // The centre, read and discarded exactly as the reference does: it is
    // derived from the maximum, and the stored copy is not consulted.
    buffer.readInt32();
  }

  static OctahedronToolBox _boxFrom(int maxQuantized) {
    if (maxQuantized.isEven || maxQuantized < 3 || maxQuantized > 0x3FFFFFFF) {
      _fail(
        'octahedral maximum $maxQuantized is not two-to-the-something minus '
        'one, for something between 2 and 30',
      );
    }
    return OctahedronToolBox.fromMaxQuantized(maxQuantized);
  }

  final OctahedronToolBox box;

  @override
  void computeOriginal(
    Int32List predicted,
    int predictedAt,
    Int32List data,
    int at,
  ) {
    final correctionS = data[at];
    final correctionT = data[at + 1];
    data[at] = predicted[predictedAt];
    data[at + 1] = predicted[predictedAt + 1];
    octahedronComputeOriginal(box, data, at, correctionS, correctionT);
  }
}

/// What the position-driven predictors read positions through.
///
/// **Three hops, and each is a different numbering.** A stored value of *this*
/// attribute belongs to a point; the point has a stored value of the
/// *position* attribute, which was sequenced by its own walk; and that value is
/// three quantised integers. `GetPositionForEntryId` in the reference.
final class ParentPositions {
  const ParentPositions({
    required this.portable,
    required this.pointToValue,
    required this.entryToPoint,
  });

  /// The position attribute's integers, before dequantisation.
  final Int32List portable;

  /// The position attribute's value for a point, or null where point and
  /// value are the same number (sequential connectivity).
  final Int32List? pointToValue;

  /// The point each stored value of the predicted attribute belongs to.
  final Int32List entryToPoint;

  int offsetOf(int entry) {
    final point = entryToPoint[entry];
    return (pointToValue?[point] ?? point) * 3;
  }
}

/// `PredictionSchemeDeltaDecoder`: each value from the one before, the first
/// from zeros.
///
/// **Element zero is not exempt.** The reference predicts it from a vector of
/// zeros and runs the transform over that, so a wrap can fire there too — the
/// bug `monster_sequential.drc` found while the sequential half was written.
void predictDifference(
  PredictionTransform transform,
  Int32List data,
  int components,
  int entries,
) {
  if (entries == 0) return;
  transform.computeOriginal(Int32List(components), 0, data, 0);
  for (var at = components; at < entries * components; at += components) {
    transform.computeOriginal(data, at - components, data, at);
  }
}

/// `ComputeParallelogramPrediction`: true, with the guess in [out] at [outAt],
/// when the face across [corner]'s edge is already fully decoded.
bool _parallelogram(
  AttributeSequence sequence,
  Int32List data,
  int components,
  int entry,
  int corner,
  Int32List out,
  int outAt,
) {
  final table = sequence.table;
  final across = table.opposite(corner);
  if (across == dracoInvalid) return false;

  final map = sequence.vertexToValue;
  final opposite = map[table.vertex(across)];
  final next = map[table.vertex(table.next(across))];
  final previous = map[table.vertex(table.previous(across))];
  if (opposite >= entry || next >= entry || previous >= entry) return false;

  for (var c = 0; c < components; c++) {
    out[outAt + c] =
        (data[next * components + c] +
                data[previous * components + c] -
                data[opposite * components + c])
            .toSigned(32);
  }
  return true;
}

/// `MeshPredictionSchemeParallelogramDecoder`.
void predictParallelogram(
  WrapTransform transform,
  AttributeSequence sequence,
  Int32List data,
  int components,
) {
  final entries = sequence.valueCount;
  if (entries == 0) return;
  final guess = Int32List(components);
  transform.computeOriginal(guess, 0, data, 0);

  for (var entry = 1; entry < entries; entry++) {
    final at = entry * components;
    final corner = sequence.cornerOf(entry);
    // No finished face across the edge — a boundary, a seam, or simply not
    // decoded yet — falls back to the previous value.
    if (_parallelogram(sequence, data, components, entry, corner, guess, 0)) {
      transform.computeOriginal(guess, 0, data, at);
    } else {
      transform.computeOriginal(data, at - components, data, at);
    }
  }
}

/// `MeshPredictionSchemeConstrainedMultiParallelogramDecoder`.
final class ConstrainedMultiParallelogram {
  /// Reads the crease flags: four runs, the *n*-th for vertices that had *n*
  /// parallelograms available, since how reliable one guess is depends on how
  /// many others it is being averaged with.
  ConstrainedMultiParallelogram(DracoBuffer buffer, int cornerCount)
    : _isCrease = <List<bool>>[
        for (var i = 0; i < _maxParallelograms; i++)
          _readFlags(buffer, cornerCount),
      ];

  static const int _maxParallelograms = 4;

  static List<bool> _readFlags(DracoBuffer buffer, int cornerCount) {
    final count = buffer.readVarUint();
    if (count > cornerCount) _fail('more crease flags than corners');
    if (count == 0) return const <bool>[];
    final bits = RAnsBitDecoder(buffer);
    return <bool>[for (var i = 0; i < count; i++) bits.readBit()];
  }

  final List<List<bool>> _isCrease;

  void predict(
    WrapTransform transform,
    AttributeSequence sequence,
    Int32List data,
    int components,
  ) {
    final entries = sequence.valueCount;
    if (entries == 0) return;
    final table = sequence.table;
    final guesses = Int32List(_maxParallelograms * components);
    final average = Int32List(components);
    final flagCursor = Int32List(_maxParallelograms);
    transform.computeOriginal(average, 0, data, 0);

    for (var entry = 1; entry < entries; entry++) {
      final at = entry * components;
      final start = sequence.cornerOf(entry);

      // Every face round the vertex: left until the fan ends or closes, then
      // right from the start for the other half of an open fan.
      var found = 0;
      var corner = start;
      var firstPass = true;
      while (corner != dracoInvalid) {
        if (_parallelogram(
          sequence,
          data,
          components,
          entry,
          corner,
          guesses,
          found * components,
        )) {
          if (++found == _maxParallelograms) break;
        }
        corner = firstPass ? table.swingLeft(corner) : table.swingRight(corner);
        if (corner == start) break;
        if (corner == dracoInvalid && firstPass) {
          firstPass = false;
          corner = table.swingRight(start);
        }
      }

      var used = 0;
      average.fillRange(0, components, 0);
      for (var i = 0; i < found; i++) {
        final context = found - 1;
        final flag = flagCursor[context]++;
        if (flag >= _isCrease[context].length) {
          _fail('the crease flags ran out before the vertices did');
        }
        if (_isCrease[context][flag]) continue;
        used++;
        for (var c = 0; c < components; c++) {
          average[c] = (average[c] + guesses[i * components + c]).toSigned(32);
        }
      }

      if (used == 0) {
        transform.computeOriginal(data, at - components, data, at);
      } else {
        for (var c = 0; c < components; c++) {
          // Truncating, like the C++ it has to agree with.
          average[c] = average[c] ~/ used;
        }
        transform.computeOriginal(average, 0, data, at);
      }
    }
  }
}

/// `MeshPredictionSchemeTexCoordsPortableDecoder`.
///
/// **The triangle's shape is already known, so its UVs nearly are.** With the
/// two other corners' UVs and all three positions decoded, the tip's UV is
/// fixed up to which side of the opposite edge it lies on: project the tip
/// onto the edge in space, carry the foot of that projection into UV space by
/// the same ratio, and step off the edge perpendicular to it by the height the
/// triangle has in space. One stored bit picks the side.
///
/// **On 64-bit integers, which is a constraint on where this runs.** The
/// products below reach 2^60 at the quantisation `gltf-transform` defaults to.
/// The VM's `int` is the `int64_t` the reference computes in, wrap-around
/// included. Compiled to JavaScript an `int` is a double and exact only to
/// 2^53, so there the square-root step goes through `BigInt`, and quantisation
/// wide enough to push the *other* products past 2^53 is refused by name
/// rather than decoded approximately.
final class TexCoordsPortable {
  TexCoordsPortable(DracoBuffer buffer) : _orientations = _read(buffer);

  /// Run-length of a sort: each stored bit says "same as the last one", which
  /// is nearly always true across a UV island.
  static List<bool> _read(DracoBuffer buffer) {
    final count = buffer.readInt32();
    if (count < 0) _fail('negative orientation count');
    if (count > buffer.remaining * 4096) {
      _fail('more orientations than the stream could hold');
    }
    final bits = RAnsBitDecoder(buffer);
    var last = true;
    return <bool>[
      for (var i = 0; i < count; i++) last = bits.readBit() ? last : !last,
    ];
  }

  /// Consumed from the back — the encoder pushed them in its order and the
  /// reference pops.
  final List<bool> _orientations;

  void predict(
    WrapTransform transform,
    AttributeSequence sequence,
    ParentPositions positions,
    Int32List data,
  ) {
    final table = sequence.table;
    final map = sequence.vertexToValue;
    final guess = Int32List(2);

    for (var entry = 0; entry < sequence.valueCount; entry++) {
      final corner = sequence.cornerOf(entry);
      final next = map[table.vertex(table.next(corner))];
      final previous = map[table.vertex(table.previous(corner))];
      _guess(positions, data, entry, next, previous, guess);
      transform.computeOriginal(guess, 0, data, entry * 2);
    }
  }

  void _guess(
    ParentPositions positions,
    Int32List data,
    int entry,
    int next,
    int previous,
    Int32List guess,
  ) {
    if (previous < entry && next < entry) {
      final nU = data[next * 2], nV = data[next * 2 + 1];
      final pU = data[previous * 2], pV = data[previous * 2 + 1];
      if (pU == nU && pV == nV) {
        guess[0] = pU;
        guess[1] = pV;
        return;
      }

      final pos = positions.portable;
      final tip = positions.offsetOf(entry);
      final n = positions.offsetOf(next);
      final p = positions.offsetOf(previous);
      final pnX = pos[p] - pos[n];
      final pnY = pos[p + 1] - pos[n + 1];
      final pnZ = pos[p + 2] - pos[n + 2];
      final pnNorm2 = pnX * pnX + pnY * pnY + pnZ * pnZ;
      if (pnNorm2 != 0) {
        final cnX = pos[tip] - pos[n];
        final cnY = pos[tip + 1] - pos[n + 1];
        final cnZ = pos[tip + 2] - pos[n + 2];
        final cnDotPn = pnX * cnX + pnY * cnY + pnZ * cnZ;
        final pnU = pU - nU, pnV = pV - nV;

        final uvMax = _max(nU.abs(), nV.abs());
        final pnUvMax = _max(pnU.abs(), pnV.abs());
        final pnMax = _max(_max(pnX.abs(), pnY.abs()), pnZ.abs());
        if (_intsAreDoubles && (pnMax >= 1 << 17 || uvMax >= 1 << 17)) {
          _fail(
            'texture-coordinate prediction at this quantisation needs 64-bit '
            'integers, which JavaScript does not have',
          );
        }
        // The reference's own overflow guards, kept: a stream that trips them
        // is one its decoder refuses too.
        if (uvMax > _int64Max ~/ pnNorm2 ||
            cnDotPn.abs() > _int64Max ~/ pnUvMax ||
            cnDotPn.abs() > _int64Max ~/ pnMax) {
          _fail('texture-coordinate prediction overflows 64 bits');
        }

        // The foot of the tip's perpendicular, in UV space, times |pn|².
        final xU = nU * pnNorm2 + cnDotPn * pnU;
        final xV = nV * pnNorm2 + cnDotPn * pnV;
        // The same foot in space, and how far the tip stands off it.
        final cxX = pos[tip] - (pos[n] + (cnDotPn * pnX) ~/ pnNorm2);
        final cxY = pos[tip + 1] - (pos[n + 1] + (cnDotPn * pnY) ~/ pnNorm2);
        final cxZ = pos[tip + 2] - (pos[n + 2] + (cnDotPn * pnZ) ~/ pnNorm2);
        final cxNorm2 = cxX * cxX + cxY * cxY + cxZ * cxZ;
        final scale = _intSqrtOfProduct(cxNorm2, pnNorm2);
        // pn in UV space turned a quarter, scaled to the tip's height.
        final cxU = pnV * scale;
        final cxV = -pnU * scale;

        if (_orientations.isEmpty) {
          _fail('the orientation flags ran out before the vertices did');
        }
        final (sumU, sumV) = _orientations.removeLast()
            ? (xU + cxU, xV + cxV)
            : (xU - cxU, xV - cxV);
        guess[0] = (sumU ~/ pnNorm2).toSigned(32);
        guess[1] = (sumV ~/ pnNorm2).toSigned(32);
        return;
      }
    }

    // Not enough decoded round this corner to build a triangle from. The
    // cascade is the reference's, including that a usable `previous` is
    // overridden whenever `next` is not usable too.
    final int from;
    if (next < entry) {
      from = next;
    } else if (entry > 0) {
      from = entry - 1;
    } else {
      guess[0] = 0;
      guess[1] = 0;
      return;
    }
    guess[0] = data[from * 2];
    guess[1] = data[from * 2 + 1];
  }
}

/// The largest `int64` a double holds exactly, 1024 short of the real maximum.
/// The literal has to compile to JavaScript too, where the real one does not,
/// and an overflow guard loses nothing by being that much more careful.
const int _int64Max = 0x7FFFFFFFFFFFFC00;

int _max(int a, int b) => a > b ? a : b;

/// `IntSqrt(a * b)` with the product taken as the reference takes it: in
/// unsigned 64 bits, wrapping.
///
/// The fast path is whenever the product provably fits the platform's exact
/// integers — 2^53 compiled to JavaScript, 2^63 on the VM. Past that it is
/// `BigInt`, masked to 64 bits so that a wrap the reference would make is made
/// here too.
int _intSqrtOfProduct(int a, int b) {
  final bits = a.bitLength + b.bitLength;
  if (bits <= (_intsAreDoubles ? 53 : 63)) return _intSqrt(a * b);
  final product = (BigInt.from(a) * BigInt.from(b)).toUnsigned(64);
  return _bigSqrt(product).toInt();
}

/// Floor of the square root, exactly — Newton's iteration from above, on
/// integers, which is also what the reference's `IntSqrt` converges to. A
/// double's `sqrt` would not do: it is good to 53 bits and the product may
/// have 63.
int _intSqrt(int n) {
  if (n < 2) return n < 0 ? 0 : n;
  var x = 1 << ((n.bitLength + 1) >> 1);
  while (true) {
    final y = (x + n ~/ x) >> 1;
    if (y >= x) return x;
    x = y;
  }
}

BigInt _bigSqrt(BigInt n) {
  if (n < BigInt.two) return n;
  var x = BigInt.one << ((n.bitLength + 1) >> 1);
  while (true) {
    final y = (x + n ~/ x) >> 1;
    if (y >= x) return x;
    x = y;
  }
}

/// `MeshPredictionSchemeGeometricNormalDecoder`.
///
/// The guess is the sum of the cross products of every face round the vertex —
/// the area-weighted normal — from the decoded positions, brought onto the
/// octahedron and stored there. A stored bit flips it, for the vertex whose
/// authored normal points the other way from its geometry.
final class GeometricNormal {
  /// The flip bits come *after* the transform's own data in the stream, which
  /// is the reverse of every other scheme here.
  GeometricNormal(DracoBuffer buffer)
    : transform = OctahedronTransform(buffer),
      _flips = RAnsBitDecoder(buffer);

  final OctahedronTransform transform;
  final RAnsBitDecoder _flips;

  void predict(
    AttributeSequence sequence,
    ParentPositions positions,
    Int32List data,
  ) {
    final table = sequence.table;
    final map = sequence.vertexToValue;
    final pos = positions.portable;
    final box = transform.box;
    final normal = Int32List(3);
    final guess = Int32List(2);

    int positionAt(int corner) => positions.offsetOf(map[table.vertex(corner)]);

    for (var entry = 0; entry < sequence.valueCount; entry++) {
      final start = sequence.cornerOf(entry);
      final centre = positionAt(start);

      // Every corner round the vertex, left then right.
      var nx = 0, ny = 0, nz = 0;
      var corner = start;
      var goingLeft = true;
      while (corner != dracoInvalid) {
        final a = positionAt(table.next(corner));
        final b = positionAt(table.previous(corner));
        final ax = pos[a] - pos[centre];
        final ay = pos[a + 1] - pos[centre + 1];
        final az = pos[a + 2] - pos[centre + 2];
        final bx = pos[b] - pos[centre];
        final by = pos[b + 1] - pos[centre + 1];
        final bz = pos[b + 2] - pos[centre + 2];
        nx += ay * bz - az * by;
        ny += az * bx - ax * bz;
        nz += ax * by - ay * bx;

        if (goingLeft) {
          corner = table.swingLeft(corner);
          if (corner == dracoInvalid) {
            corner = table.swingRight(start);
            goingLeft = false;
          } else if (corner == start) {
            corner = dracoInvalid;
          }
        } else {
          corner = table.swingRight(corner);
        }
      }

      // Brought under 2^29 so the canonicalisation below stays in 32 bits.
      const upperBound = 1 << 29;
      final absSum = nx.abs() + ny.abs() + nz.abs();
      if (absSum > upperBound) {
        final quotient = absSum ~/ upperBound;
        nx = nx ~/ quotient;
        ny = ny ~/ quotient;
        nz = nz ~/ quotient;
      }
      normal[0] = nx.toSigned(32);
      normal[1] = ny.toSigned(32);
      normal[2] = nz.toSigned(32);

      box.canonicalizeIntegerVector(normal);
      if (_flips.readBit()) {
        normal[0] = -normal[0];
        normal[1] = -normal[1];
        normal[2] = -normal[2];
      }
      box.integerVectorToOctahedralCoords(normal, guess);
      transform.computeOriginal(guess, 0, data, entry * 2);
    }
  }
}
