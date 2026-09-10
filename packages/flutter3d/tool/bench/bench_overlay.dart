// ignore_for_file: avoid_print — see bench.dart.

/// What the modeller's overlay costs on the CPU at the size `view-01-bench`
/// asks about: two hundred thousand elements handed over in one frame.
///
///     flutter test tool/bench/bench_overlay.dart
///
/// **Two questions, and a threshold hanging off each.** (b) is what it costs to
/// turn two hundred thousand camera-facing quads into the bytes
/// `CommandEncoder.bindVertexData` is given — the vertex handles a person sees
/// when a whole mesh is in vertex mode. (c) is what the nudge towards the eye
/// costs on its own over two hundred thousand vertices, because that is the one
/// piece of the build a shader could take over. The plan says that above two
/// milliseconds `view-06-overlay-shader` stops being conditional and has to be
/// built: a `depth_bias` in `overlay.vert` across four backends, GLSL, a CPU
/// transcription and two tables, which is a fortnight nobody wants to spend on
/// a guess.
///
/// **The upload is missing from these numbers, and saying so is the point.**
/// `bindVertexData` needs a device, a pass and an encoder; there is none here,
/// so what is measured stops at the `ByteData` view the encoder would be
/// handed. The device half is `p0-06`'s question, measured on the `p0-01` stand
/// where a real frame is running. Reading these rows as the whole cost of a
/// frame would be reading them wrongly.
///
/// **Run through `flutter test` rather than `dart compile exe`, which is a
/// finding and not a convenience.** Every other benchmark in this repository is
/// compiled ahead of time, and `tool/structure.dart` holds `tool/bench/
/// bench.dart` to it by walking imports. This one cannot join them:
/// `MeshOverlay` names `ShaderHandle`, so it imports `flutter3d_hardware`,
/// whose `graphics_device.dart` returns a `Widget` from `present` and therefore
/// reaches `package:flutter/widgets.dart` and `dart:ui` four hops on. `dart
/// run` dies on the same import for the same reason. `flutter3d_cpu`'s
/// `tool/dump_fixture.dart` reached the same wall and answered it the same way.
/// The numbers below are therefore JIT numbers from the test VM, and the
/// obvious objection is that a release build would halve them and move a
/// threshold. It was checked before this file was believed: the arithmetic of
/// [MeshOverlay.edge] was replicated on its own, where nothing reaches
/// `dart:ui`, and built both ways. The pair is what the check was for, and the
/// pair came back 5.32 ms under the test VM against 5.68 ms compiled ahead of
/// time — the compiled build was no faster, because what the row is really
/// measuring is a `Vector3` allocated per vertex, and an allocation is an
/// allocation in either pipeline. Those two absolutes belong to that replica on
/// that machine and this file will not reproduce them; what carries over is
/// that the compiler is not hiding a factor of two.
///
/// **What an element is changes between the halves, so each row names its
/// own.** (b) counts quads and one quad is six vertices; (c) counts vertices.
/// The rows print `ns/quad` and `ns/vertex` for that reason, and (b) prints its
/// per-vertex figure as well, because that is the only one of its numbers a
/// reader can hold against the nudge.
///
/// The figures this prints belong in `doc/model-editor.md` with the machine and
/// the date beside them, for the reason `ARCHITECTURE.md` §14 gives about the
/// engine's: a measurement nobody can re-run is a measurement nobody can
/// contradict.
library;

import 'dart:math' as math;

import 'package:flutter3d/src/engine/render/mesh_overlay.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The size the plan named, and the size a modeller reaches by selecting
/// everything on a mesh somebody would actually sculpt.
const int kElements = 200000;

/// The plan's threshold, in microseconds: above two milliseconds of nudge
/// `view-06-overlay-shader` stops being conditional.
const double kThresholdUs = 2000;

/// What one row cost: the fastest of the repeats and the slowest, both in
/// microseconds for a single run of the body.
typedef Row = ({double best, double worst});

/// Runs [body] [iterations] times over, [repeats] times, prints the band the
/// runs landed in, and hands both ends back.
///
/// **It returns the measurement, which is why this is not
/// `bench_util.dart`'s.** The threshold that matters here is a difference
/// between two rows — the nudge is whatever building a nudged vertex costs over
/// building a plain one — and a helper that only prints leaves the subtraction
/// to whoever reads the terminal, which is where a decision about a fortnight
/// of shader work would quietly turn into arithmetic nobody checked.
///
/// **It reports a band rather than a number, because one run of this is not a
/// measurement.** A single timing is what the file printed first, and the
/// spread turned out to be worth more than the digits after the point: on one
/// machine over one afternoon (b) came back at 86.73 ms as a lone figure, then
/// at 28.55 ms best against 32.86 ms worst in five runs, then at 32.99 ms
/// against 42.17 ms in the next five. Quoting the fastest alone invites a
/// reader to trust two decimal places the next run contradicts. The rejected
/// alternative was a mean with a standard deviation, which reads as more
/// rigour than five runs support and which one stalled run drags about; the
/// fastest run is the one least contaminated by whatever else had the cores,
/// and the slowest is printed beside it so nobody has to take the fastest on
/// trust.
Row bench(
  String name,
  int iterations,
  void Function() body, {
  int? items,
  String unit = 'element',
  int repeats = 5,
}) {
  body(); // once untimed, so lazy paths and the first growth are not counted

  final runs = List<double>.generate(repeats, (_) => _time(iterations, body))
    ..sort();
  final row = (best: runs.first, worst: runs.last);
  print(
    '${name.padRight(46)} ${_ms(row.best)}${_per(row.best, items, unit)}'
    '${_spread(row, repeats)}',
  );
  return row;
}

/// Microseconds one run of [body] cost, averaged over [iterations] of them.
double _time(int iterations, void Function() body) {
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / iterations;
}

String _ms(double micros) => micros >= 1000
    ? '${(micros / 1000).toStringAsFixed(2)} ms'
    : '${micros.toStringAsFixed(1)} us';

/// The per-item cost, with [unit] naming what an item is.
///
/// **The unit is spelled out because the column used to lie by omission.** Both
/// halves of the table said `ns/element`, and an element was a quad in (b) and
/// a vertex in (c) — six to one — so a reader sizing `view-06` against the quad
/// path was comparing figures that share a name and nothing else.
String _per(double micros, int? items, String unit) =>
    items == null || items <= 0
    ? ''
    : '   (${(micros * 1000 / items).toStringAsFixed(1)} ns/$unit)';

/// How far the slowest run ran behind the fastest, as a percentage of the
/// fastest.
///
/// A band under half a microsecond wide is below what timing a loop this way
/// resolves, and the hand-over row is exactly that: a percentage on it read
/// `worst +902%` of a figure that rounds to nothing, which is a frightening
/// number describing no event. Such a row says nothing about spread, so it says
/// nothing.
String _spread(Row row, int repeats) {
  if (row.best <= 0 || row.worst - row.best < 0.5) return '';
  final over = (row.worst - row.best) / row.best * 100;
  return '   [best of $repeats, worst +${over.toStringAsFixed(0)}%]';
}

/// The per-item cost of a band, both ends against one unit name.
String _perBand(double low, double high, int items, String unit) =>
    '   (${(low * 1000 / items).toStringAsFixed(1)} to '
    '${(high * 1000 / items).toStringAsFixed(1)} ns/$unit)';

/// Points scattered through a cube in front of the camera rather than laid out
/// on a grid.
///
/// A grid would put every element at nearly the same distance from the eye, and
/// the nudge is a division by that distance — so a grid would measure one
/// branch of the perspective maths over and over and hide whatever the spread
/// of a real model costs.
List<Vector3> scatter(int count) {
  final random = math.Random(20260910);
  return List<Vector3>.generate(
    count,
    (_) => Vector3(
      random.nextDouble() * 4 - 2,
      random.nextDouble() * 4 - 2,
      random.nextDouble() * 4 - 2,
    ),
  );
}

/// An overlay aimed at the scatter from a metre or so back, told how big a
/// pixel is the way a perspective camera would tell it.
MeshOverlay aimed() {
  const fieldOfView =
      0.7; // radians, near enough the 40 degrees a viewport uses
  const viewportHeight = 1080.0;
  return MeshOverlay(
    vertexShader: const ShaderHandle(backend: 'bench', name: 'DebugLineVertex'),
    fragmentShader: const ShaderHandle(
      backend: 'bench',
      name: 'DebugLineFragment',
    ),
  )..lookFrom(
    eye: Vector3(0, 0, 6),
    right: Vector3(1, 0, 0),
    up: Vector3(0, 1, 0),
    pixel: 2 * math.tan(fieldOfView / 2) / viewportHeight,
  );
}

void main() {
  // A benchmark inside a test case only so that the runner exits zero and the
  // output is not filed under "no tests were found"; nothing here asserts.
  test(
    'overlay micro-benchmarks',
    benchOverlay,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // The one thing here that *is* asserted, because it is the one thing that
  // cannot be seen by reading the output: a wrong verdict is printed in the
  // same words as a right one. No timing goes into it, so it is as steady on a
  // loaded machine as on an idle one.
  test('a verdict is refused when the measurement contradicts itself', () {
    // The pathology, as two rows: one pairing has the row that does strictly
    // more work coming out faster, and the other pairing lands under the
    // threshold.
    final band = _nudgeBand(
      (best: 1000.0, worst: 2500.0),
      (best: 1000.0, worst: 1500.0),
    );

    // The printed band is floored, because a negative millisecond count is not
    // a measurement of anything. Mutation: hand `_verdict` the floored band
    // instead of the raw one — which is what the call site looks like if the
    // two are ever tidied into one pair of numbers — and this reads `clear,
    // view-06 stays conditional`: a fortnight of shader work called off on the
    // strength of a busy afternoon.
    expect(band.low, 0.0);
    expect(band.high, 1500.0);
    expect(band.verdict, startsWith('UNSETTLED'));
    expect(band.verdict, contains('busy'));

    // And the four real answers still come out.
    expect(_verdict(-500, -100), startsWith('NOT MEASURED'));
    expect(_verdict(2500, 4000), startsWith('CROSSED'));
    expect(_verdict(500, 1500), startsWith('clear'));
    expect(_verdict(1500, 2500), startsWith('UNSETTLED'));
  });
}

void benchOverlay() {
  print('');
  print('--- the modeller overlay, $kElements elements --------------------');

  final points = scatter(kElements);
  final colour = Vector4(1, 0.55, 0.1, 1);
  final overlay = aimed();

  // (b) The quads. `point` is the whole camera-facing path: a distance to the
  // eye, a pixel size at that distance, the nudge, four corners and six
  // vertices written into the batch. An element here is a quad, and a quad is
  // six vertices, which is why the column below says `ns/quad` and why the line
  // after it converts to the per-vertex figure that (c) can be held against.
  final build = bench(
    '(b) point() x$kElements quads',
    5,
    () {
      overlay.clear();
      for (var i = 0; i < points.length; i++) {
        overlay.point(points[i], colour);
      }
    },
    items: kElements,
    unit: 'quad',
  );

  final handed = overlay.handles;
  print(
    '    ${handed.vertexCount} vertices, '
    '${(handed.vertexBytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1)} '
    'MiB to hand over'
    '${_per(build.best, handed.vertexCount, 'vertex')} on the same run',
  );

  // The hand-over itself, which is all `bindVertexData` gets from this side. A
  // `ByteData` over the buffer the batch already owns, so the expectation is
  // that it costs nothing and the row exists to prove there is no hidden copy.
  //
  // The guard below is the only claim this file makes, and it is here because a
  // benchmark that measured an empty batch would print a fast row and a happy
  // conclusion. Mutation, re-run against this version of the file:
  // `overlay.handles` above changed to `overlay.lines`, which `point` never
  // fills — the rows above it printed `0 vertices, 0.0 MiB to hand over` and
  // then `0.0 us` for the hand-over of nothing, and the guard threw
  // `Bad state: the batch came back empty`. Without it that pair of rows is
  // what a reader would have taken away as (b) having been measured.
  var sink = handed.vertexBytes;
  bench('(b) handles.vertexBytes (the hand-over)', 10000, () {
    sink = handed.vertexBytes;
  });
  if (sink.lengthInBytes == 0) throw StateError('the batch came back empty');

  print('');

  // (c) The nudge, by difference. `edge` is two nudges and two vertex writes;
  // the batch on its own is two vertex writes. Both rows put the same number of
  // vertices into a batch that has already grown to hold them, with the same
  // colour and the same positions read out of the same list, which is what
  // makes the subtraction mean anything.
  //
  // What is *not* the same, and is worth naming rather than glossing: the
  // nudged row goes round its loop half as many times, reading two points and
  // calling once, where the plain row reads one and calls once. That is a
  // couple of hundred microseconds of loop overhead the plain row pays and the
  // nudged one does not, against a difference of thirteen to twenty-eight
  // milliseconds — so it leans the wrong way for the answer this row is used
  // for, understating the nudge rather than flattering it, and a threshold
  // crossed in spite of it is crossed.
  final nudged = bench(
    '(c) edge() x${kElements ~/ 2} (2 vertices each)',
    5,
    () {
      overlay.clear();
      for (var i = 0; i + 1 < points.length; i += 2) {
        overlay.edge(points[i], points[i + 1], colour);
      }
    },
    items: kElements,
    unit: 'vertex',
  );

  final plain = OverlayBatch(reserveVertices: kElements);
  final stored = bench(
    '(c) batch.vertex() x$kElements (no nudge)',
    5,
    () {
      plain.clear();
      for (var i = 0; i < points.length; i++) {
        plain.vertex(points[i], colour);
      }
    },
    items: kElements,
    unit: 'vertex',
  );

  // A difference between two measured rows carries both rows' uncertainty, so
  // it is a band and not a figure: the narrowest the nudge could be is the
  // fastest nudged run against the slowest plain one, and the widest is the
  // other pairing.
  //
  // Both ends are floored at zero because a negative millisecond count is not a
  // measurement of anything, and this subtraction is the one arithmetic path in
  // the file that can go negative — the two rows are timed separately, so a
  // stalled plain run is all it takes. Mutation: both subtractions reversed to
  // `stored - nudged`, which is the arithmetic a stalled plain run would hand
  // over, run twice. Floored, it printed a band of `0.0 us to 0.0 us` and
  // `NOT MEASURED: the difference sank into the noise`; with `math.max` taken
  // back off, the same reversal printed `-8872.2 us to -6860.6 us` and
  // `-44.4 to -34.3 ns/vertex`, which is the figure this floor exists to keep
  // out of `doc/model-editor.md`.
  final band = _nudgeBand(nudged, stored);
  print('');
  print(
    '(c) the nudge alone, $kElements vertices: ${_ms(band.low)} to '
    '${_ms(band.high)}'
    '${_perBand(band.low, band.high, kElements, 'vertex')}',
  );
  print('    threshold 2.00 ms: ${band.verdict}');
  print(
    '(b) the CPU half of a frame of quads: ${_ms(build.best)} to '
    '${_ms(build.worst)} — the upload is p0-06 on the p0-01 stand, never '
    'measured here',
  );
}

/// The nudge's cost: the band a person reads, and the verdict the plan reads.
///
/// **One function rather than three lines at the call site, because the two
/// answers are deliberately computed from different numbers and that is exactly
/// the kind of thing that gets tidied back into one.** The band is floored,
/// because a negative millisecond count is not a measurement of anything and
/// printing one would put it in front of somebody. The verdict is not floored,
/// because a floored band cannot tell a real answer from a busy machine: a low
/// end clamped up from a negative and a high end that happens to sit under the
/// threshold reads as `clear, view-06 stays conditional`, in the same words as
/// a real result, from a run in which the row doing strictly more work came out
/// faster.
({double low, double high, String verdict}) _nudgeBand(Row nudged, Row stored) {
  final low = nudged.best - stored.worst;
  final high = nudged.worst - stored.best;
  return (
    low: math.max(0.0, low),
    high: math.max(0.0, high),
    verdict: _verdict(low, high),
  );
}

/// What the nudge band says about the plan's threshold.
///
/// A band that straddles the threshold decides nothing, and saying so is the
/// point of measuring a band at all: the rejected alternative was to test the
/// best run against the threshold, which turns whichever way the machine was
/// leaning that afternoon into a fortnight of shader work or the absence of it.
/// [low] and [high] are the raw difference, before the floor the printed band
/// gets — see the call site.
String _verdict(double low, double high) {
  if (high <= 0) return 'NOT MEASURED: the difference sank into the noise';
  if (low < 0) {
    // The nudged row does everything the plain row does and a subtraction, a
    // length, a divide and a multiply-add on top, so it cannot really be
    // faster. One end of the band saying it was means the machine was busy
    // enough for the scheduler to be the thing being measured, and the only
    // honest verdict is that there is no verdict.
    return 'UNSETTLED: one pairing has the nudge running faster than no nudge '
        'at all, so the machine was busy — re-run on an idle one';
  }
  if (low > kThresholdUs) return 'CROSSED, view-06 is mandatory';
  if (high < kThresholdUs) return 'clear, view-06 stays conditional';
  return 'UNSETTLED: the band straddles it, re-run on an idle machine';
}
