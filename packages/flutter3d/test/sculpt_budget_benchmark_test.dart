// ignore_for_file: avoid_print — a command-line-shaped benchmark whose whole
// output is stdout; a logging framework would be the wrong tool.

/// `pro-sc-01`'s own row: whether a sculpting brush stroke on a 1.2-million
/// triangle mesh fits its budget on macOS — upload the mesh, edit 20 000
/// vertices, recompute their normals, overwrite the changed region of the GPU
/// buffer, build a BVH over the mesh and raycast it once, and say what garbage
/// one such stroke produces. Thresholds from the plan row: 8/16 ms and 3 s.
///
///     flutter test test/sculpt_budget_benchmark_test.dart
///
/// **Which threshold gates which number, since the plan's own row does not
/// say.** Read against `p0-02` (this repository's precedent: 8.33 ms is a
/// 120 Hz frame, 16.6 ms a 60 Hz one) and against the plan's own row order —
/// "upload … кадр, правка … overwrite, BVH build/raycast" — the two one-time
/// costs of getting a model open and sculptable (uploading it once, building
/// a BVH over it once) are what "3 s" budgets, the same way p0-02 gave
/// loading its own, separate allowance from the frame budget. What repeats on
/// every brush movement — editing the touched vertices, recomputing their
/// normals, overwriting the buffer, and one raycast to find where the brush
/// is — is what "8/16 ms" gates, because that is the part that has to happen
/// inside a frame for a stroke to track the pointer.
///
/// **What this actually measured, on this machine** (`sysctl
/// machdep.cpu.brand_string` says "Apple M3 Pro", the same machine
/// `doc/model-editor.md` §6 was measured on) **through this test runner's own
/// JIT, on 2026-09-13:**
///
/// Setup, once (the row's own "3 s" budget):
///
/// | Step | Time |
/// |---|---|
/// | `EditMesh.fromFaces` (775×775 grid, 1 201 250 triangles) | see printed run |
/// | `MeshLayoutPlan.build` (merge corners, cut faces, normals) | see printed run |
/// | `fillVertices` (all rows) | see printed run |
/// | `withGeneratedTangents` | see printed run |
/// | `DeviceMesh.upload` (CPU backend) | see printed run |
/// | `TriangleBvh.fromMesh` | see printed run |
///
/// Per stroke, repeated (the row's own "8/16 ms" budget):
///
/// | Step | Time |
/// |---|---|
/// | select ~20k vertices in a random circle | see printed run |
/// | `moveVertex` × touched, journalled | see printed run |
/// | `MeshNormals.build` (whole mesh — no partial path exists yet) | see printed run |
/// | `fillVerticesOf` (touched rows only) | see printed run |
/// | `DeviceMesh.overwriteVertices` (CPU backend) | see printed run |
/// | one `TriangleBvh.raycast` | see printed run |
///
/// The actual numbers are in the run's own stdout, not frozen into this
/// comment, because a comment is not where a dated, honest number belongs —
/// `doc/model-editor.md` §6 is, and that is where this run's numbers were
/// copied after being read off a real execution rather than guessed.
///
/// **What this does *not* cover, and why.**
///
/// - **Chrome and a Galaxy A55 are not measured here.** This sandbox has
///   macOS only; the plan row asks for all three. `p0-02`/`p0-03` already
///   drew this same line for the viewport spike, for the same reason —
///   Chrome needs a foregrounded tab and a browser driver
///   (`packages/flutter3d_webgl/tool/profile_web.py`), A55 needs the device
///   in hand — and neither exists in this run.
/// - **"Frame" is not re-rendered here.** `p0-02` already measured a real
///   Metal/Impeller frame with a one-million-triangle mesh in one draw call
///   on this same machine (8.33 ms mean, 0 frames over 16.6 ms out of 587) —
///   1.2 million changes that number by nothing p0-02's own draw-call
///   conclusion did not already cover, since triangle count was shown there
///   not to be what a frame pays for. Rendering this benchmark's own mesh
///   through the CPU software rasterizer instead would answer a different
///   question — software raster throughput, not GPU frame cost — and answer
///   it slowly enough (a software triangle rasterizer over 1.2 million
///   triangles) to make this test not worth waiting for, so it is not done.
/// - **Upload and overwrite go through `CpuDevice`, not through Impeller.**
///   `CpuDevice.uploadGeometry`/`overwriteGeometry` do exactly what a real
///   backend's byte-shuffling half does — `Uint8List.fromList` and
///   `Uint8List.setAll` — but nothing past that: no driver call, no command
///   buffer, no GPU. That makes the two numbers here a proxy for the
///   memory-copy cost any backend pays, not a repeat of `p0-06`'s real
///   Impeller measurement (1.24 ms/200k triangles, 5.39 ms/1M) — which
///   already exists and is the number to trust for the GPU side.
/// - **Garbage per stroke is a code-review answer, not a sampled one.** Dart
///   gives no portable allocation counter outside `--observe` plus DevTools,
///   which this sandbox cannot drive interactively. What is here instead: an
///   accounting of what the hot path allocates, read from the source of
///   `MeshNormals`, `MeshLayoutPlan` and `DeviceMesh`, backed by one thing
///   this test *can* check without a profiler — that repeating the stroke a
///   second and third time costs the same as the first, which a scheme that
///   allocated for every touched vertex or for the mesh's whole normal
///   buffer, every stroke, would not do.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A grid of quads `n` by `n` — the point and face layout of `tool/bench.dart`
/// (`p0-04`, `mesh-31`), copied rather than imported because that file is a
/// `dart compile exe` script, not a library this test can reach.
///
/// **Every face marked smooth, which `tool/bench.dart`'s own `grid` does not
/// do.** `EditMesh` defaults every face to *not* smooth (`edit_mesh.dart`'s
/// own `faceHas` reads a null layer as false), so a mesh built the way
/// `bench.dart` builds one has every corner in its own normal group — one GPU
/// vertex per corner, four per quad, with nothing shared. That is a faceted
/// cube's shading and the wrong shape for what this benchmark asks: a
/// smooth, editable surface where merging is what buys the plan's own "38
/// МБ" for 602 176 vertices rather than four times that for 2 402 500
/// unmerged corners — the first number this benchmark printed here, before
/// this fix, before it was corrected. `SphereShape` and every other
/// parametric generator in `flutter3d_geometry`/`parametric.dart` mark every
/// face smooth for the same reason; this grid now matches that convention
/// rather than `bench.dart`'s.
EditMesh grid(int n) {
  final points = <Vector3>[
    for (var y = 0; y <= n; y++)
      for (var x = 0; x <= n; x++)
        Vector3(x.toDouble() / n - 0.5, 0, y.toDouble() / n - 0.5),
  ];
  final faces = <List<int>>[
    for (var y = 0; y < n; y++)
      for (var x = 0; x < n; x++)
        <int>[
          y * (n + 1) + x,
          y * (n + 1) + x + 1,
          (y + 1) * (n + 1) + x + 1,
          (y + 1) * (n + 1) + x,
        ],
  ];
  final mesh = EditMesh.fromFaces(points, faces);
  mesh.beginStep();
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    mesh.setFaceFlag(face, FaceFlags.smooth, on: true);
  }
  mesh.endStep();
  return mesh;
}

double _ms(Stopwatch sw) => sw.elapsedMicroseconds / 1000.0;

String _fmt(double milliseconds) => milliseconds >= 1
    ? '${milliseconds.toStringAsFixed(2)} ms'
    : '${(milliseconds * 1000).toStringAsFixed(1)} us';

void main() {
  test("pro-sc-01's own acceptance: a brush stroke on 1.2M triangles", () {
    // 775 x 775 quads is 1 201 250 triangles and 602 176 vertices — near
    // enough the plan's "1,2 млн" to be the same mesh, and at
    // `VertexLayout.standard` (64 bytes/vertex) that is 38 539 264 bytes of
    // vertex data: within 1% of the plan's own "38 МБ".
    const n = 775;
    print('--- setup: opening a 1.2M-triangle mesh (the row\'s "3 s") ---');

    final swBuild = Stopwatch()..start();
    final mesh = grid(n);
    swBuild.stop();
    final triangleCount = mesh.faceCount * 2; // quads, each cut in two
    print(
      'EditMesh.fromFaces ($n x $n grid, $triangleCount triangles, '
      '${mesh.vertexCount} vertices): ${_fmt(_ms(swBuild))}',
    );

    final plan = MeshLayoutPlan();
    final swPlan = Stopwatch()..start();
    plan.build(mesh);
    swPlan.stop();
    print('MeshLayoutPlan.build (merge + cut + normals): ${_fmt(_ms(swPlan))}');

    final buffer = plan.rows();
    final swFill = Stopwatch()..start();
    plan.fillVertices(mesh, buffer);
    swFill.stop();
    print('fillVertices (all rows): ${_fmt(_ms(swFill))}');

    final undressed = MeshData(
      layout: plan.layout,
      vertices: buffer,
      indices: Uint32List.sublistView(plan.indices, 0, plan.triangleCount * 3),
    );
    final vertexBytes = undressed.vertexBytes.lengthInBytes;
    print(
      'vertex buffer: $vertexBytes bytes '
      '(${(vertexBytes / 1e6).toStringAsFixed(2)} MB decimal, '
      '${(vertexBytes / (1 << 20)).toStringAsFixed(2)} MiB) '
      '— plan\'s own row says "38 МБ"',
    );

    final swTangent = Stopwatch()..start();
    // A copy, by `withGeneratedTangents`' own contract — later per-stroke
    // writes go into *this* array, not into `buffer`, which is why `buffer`
    // is not read again below.
    final drawn = undressed.withGeneratedTangents();
    swTangent.stop();
    print(
      'withGeneratedTangents (one-time, not part of a stroke): '
      '${_fmt(_ms(swTangent))}',
    );

    final it = cpuTestDevice();
    final swUpload = Stopwatch()..start();
    final deviceMesh = DeviceMesh.upload(it.device, drawn);
    swUpload.stop();
    print(
      'DeviceMesh.upload, CPU backend proxy for the byte copy '
      '(real Impeller number: p0-06, 5.39 ms/1M tri): ${_fmt(_ms(swUpload))}',
    );

    final swBvh = Stopwatch()..start();
    final bvh = TriangleBvh.fromMesh(drawn);
    swBvh.stop();
    print('TriangleBvh.fromMesh: ${_fmt(_ms(swBvh))}');

    final setupTotal =
        _ms(swBuild) +
        _ms(swPlan) +
        _ms(swFill) +
        _ms(swTangent) +
        _ms(swUpload) +
        _ms(swBvh);
    print(
      'setup total: ${_fmt(setupTotal)} '
      '(threshold 3000 ms: ${setupTotal < 3000 ? "PASSES" : "MISSES"})',
    );

    // A reverse map from mesh vertex to the GPU row it landed in. Built
    // once here, not per stroke: the plan's own doc comment is explicit
    // that a drag changes none of the merge/cut decisions, so this map is
    // as stable as the plan itself for as long as nobody edits topology.
    final vertexOfRow = plan.gpuVertexToVertex;
    final rowOfVertex = Int32List(mesh.vertexSlotCount);
    for (var row = 0; row < plan.vertexCount; row++) {
      rowOfVertex[vertexOfRow[row]] = row;
    }

    print('');
    print('--- per stroke, repeated (the row\'s own "8/16 ms") ---');

    // Radius chosen so a circular brush over this grid's own point density
    // touches about 20 000 vertices — the plan's own number.
    const targetTouched = 20000;
    final radius = math.sqrt(
      targetTouched / (math.pi * mesh.vertexCount.toDouble()),
    );
    final random = math.Random(20260913);

    // Preallocated once and reused every stroke: an `Int32List` sized for
    // more than any one stroke should touch, sliced with a view rather than
    // reallocated. This is the same "buffers kept, not remade" pattern
    // `MeshNormals` and `MeshLayoutPlan` already use, applied to the one
    // array in this benchmark's own hot path that they do not own.
    final touchedStore = Int32List(80000);
    final ray = Ray(Vector3.zero(), Vector3(0, -1, 0));

    const strokeIterations = 3; // plus one untimed warmup, below
    final strokeTotals = <double>[];
    final selectMs = <double>[], editMs = <double>[], normalsMs = <double>[];
    final fillMs = <double>[], overwriteMs = <double>[], raycastMs = <double>[];
    final touchedCounts = <int>[], overwrittenRows = <int>[];

    for (var iteration = -1; iteration < strokeIterations; iteration++) {
      final cx = (random.nextDouble() * 2 - 1) * (0.5 - radius);
      final cz = (random.nextDouble() * 2 - 1) * (0.5 - radius);

      final swSelect = Stopwatch()..start();
      var touched = 0;
      final r2 = radius * radius;
      final positions = mesh.positions;
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        final dx = positions[v * 3] - cx;
        final dz = positions[v * 3 + 2] - cz;
        final d2 = dx * dx + dz * dz;
        if (d2 <= r2 && touched < touchedStore.length) {
          touchedStore[touched++] = v;
        }
      }
      swSelect.stop();
      final touchedView = Int32List.sublistView(touchedStore, 0, touched);

      final swEdit = Stopwatch()..start();
      mesh.beginStep();
      for (final v in touchedView) {
        final dx = positions[v * 3] - cx;
        final dz = positions[v * 3 + 2] - cz;
        final d = math.sqrt(dx * dx + dz * dz);
        final bump = 0.03 * (1 - (d / radius)).clamp(0.0, 1.0);
        mesh.moveVertex(
          v,
          Vector3(positions[v * 3], bump, positions[v * 3 + 2]),
        );
      }
      mesh.endStep();
      swEdit.stop();

      final swNormals = Stopwatch()..start();
      plan.normals.build(mesh);
      swNormals.stop();

      final swFillStroke = Stopwatch()..start();
      plan.fillVerticesOf(mesh, drawn.vertices, touchedView);
      swFillStroke.stop();

      var minRow = 1 << 30, maxRow = -1;
      for (final v in touchedView) {
        final row = rowOfVertex[v];
        if (row < minRow) minRow = row;
        if (row > maxRow) maxRow = row;
      }
      final stride = plan.floatsPerVertex;
      final swOverwrite = Stopwatch()..start();
      final rowSpan = maxRow - minRow + 1;
      // `ByteData.sublistView`'s `start`/`end` are element indices into the
      // source typed list — float32 elements here, not bytes — so this is
      // `minRow * stride`, not `minRow * stride * 4`.
      final region = ByteData.sublistView(
        drawn.vertices,
        minRow * stride,
        (maxRow + 1) * stride,
      );
      deviceMesh.overwriteVertices(it.device, minRow, region);
      swOverwrite.stop();

      final swRaycast = Stopwatch()..start();
      ray.origin.setValues(cx, 1.0, cz);
      bvh.raycast(ray);
      swRaycast.stop();

      if (iteration >= 0) {
        strokeTotals.add(
          _ms(swSelect) +
              _ms(swEdit) +
              _ms(swNormals) +
              _ms(swFillStroke) +
              _ms(swOverwrite) +
              _ms(swRaycast),
        );
        selectMs.add(_ms(swSelect));
        editMs.add(_ms(swEdit));
        normalsMs.add(_ms(swNormals));
        fillMs.add(_ms(swFillStroke));
        overwriteMs.add(_ms(swOverwrite));
        raycastMs.add(_ms(swRaycast));
        touchedCounts.add(touched);
        overwrittenRows.add(rowSpan);
      }
    }

    double avg(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    final avgTouched =
        touchedCounts.reduce((a, b) => a + b) / touchedCounts.length;
    final avgRows =
        overwrittenRows.reduce((a, b) => a + b) / overwrittenRows.length;

    print(
      'touched vertices: avg ${avgTouched.round()} '
      '(target $targetTouched, radius ${radius.toStringAsFixed(4)})',
    );
    print('select ~20k in a circle: ${_fmt(avg(selectMs))}');
    print('moveVertex x touched, journalled: ${_fmt(avg(editMs))}');
    print(
      'MeshNormals.build (whole mesh, $triangleCount triangles): '
      '${_fmt(avg(normalsMs))}',
    );
    print('fillVerticesOf (touched rows only): ${_fmt(avg(fillMs))}');
    print(
      'overwrite region: avg ${avgRows.round()} rows '
      '(${(avgRows * plan.floatsPerVertex * 4 / 1e6).toStringAsFixed(2)} MB) '
      'for avg ${avgTouched.round()} touched vertices — the gap is every '
      'untouched vertex sharing a scanline with a touched one, because '
      'nothing chunks this mesh spatially yet',
    );
    print(
      'DeviceMesh.overwriteVertices, CPU backend proxy: '
      '${_fmt(avg(overwriteMs))}',
    );
    print('one TriangleBvh.raycast: ${_fmt(avg(raycastMs))}');
    final strokeAvg = avg(strokeTotals);
    print(
      'stroke total (select+edit+normals+fill+overwrite+raycast): '
      '${_fmt(strokeAvg)} '
      '(8 ms: ${strokeAvg < 8 ? "PASSES" : "MISSES"}; '
      '16 ms: ${strokeAvg < 16 ? "PASSES" : "MISSES"})',
    );
    print(
      'repeat cost, stroke 1 vs stroke $strokeIterations: '
      '${_fmt(strokeTotals.first)} vs ${_fmt(strokeTotals.last)} — steady '
      'rather than growing is the check this test can run in place of a '
      'real allocation profiler (see the doc comment above)',
    );

    // Soft, structural checks — not the performance thresholds, which this
    // test reports rather than gates (see the doc comment above for why).
    expect(
      mesh.vertexCount,
      closeTo(602176, 10),
      reason:
          'the grid size this benchmark asks for should be the mesh it '
          'gets',
    );
    expect(
      vertexBytes,
      closeTo(38 * 1000 * 1000, 2 * 1000 * 1000),
      reason: "matches the plan row's own \"38 МБ\" within 5%",
    );
    expect(
      avg(raycastMs),
      lessThan(1.0),
      reason:
          'p0-10 already established picking is not the bottleneck; '
          'this is the one per-stroke number expected to clear 8/16 ms '
          'with room to spare',
    );
    // No `expect` on `setupTotal` or `strokeAvg` against the row's own
    // 3 s/8/16 ms budgets: this run measured 3.35 s and ~306 ms respectively
    // (see the printed PASSES/MISSES lines above and `doc/model-editor.md`
    // §6 for the dated numbers) — real misses on the current, unchunked
    // `EditMesh` + whole-mesh `MeshNormals` path, not a bug in this test. A
    // `flutter test` that asserted a budget this codebase is not expected
    // to clear yet (that is `pro-sc-02`'s job) would just be a permanently
    // red test; this one reports the numbers instead of gating on them,
    // the same way `tool/bench.dart`'s own script prints rather than
    // asserts.
  }, timeout: const Timeout(Duration(minutes: 5)));
}
