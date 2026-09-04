// ignore_for_file: avoid_print — see bench.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/render/key_sort.dart';
import 'package:flutter3d/src/engine/scene/bvh.dart';
import 'package:vector_math/vector_math.dart';

import 'bench_util.dart';

/// Runs this suite on its own:
///
///     dart compile exe tool/bench/bench_frame_math.dart -o /tmp/bench_frame
///     /tmp/bench_frame
///
/// **Its own entry point so one suite can be re-run without the other two.**
/// It had a sharper reason once: `bench.dart` had stopped AOT-compiling, because
/// the geometry and asset suites reached `MeshGeometry` and through it the
/// hardware layer, and `GraphicsDevice` names a Flutter type — so the aggregate
/// binary died on `dart:ui is not available on this platform` and took these
/// numbers with it, while this suite, which reaches only `key_sort.dart` and
/// `bvh.dart`, still compiled. The geometry layer has since been split so that
/// the aggregate compiles again; what is left here is the convenience, which is
/// worth keeping on its own — these rows are the slowest of the three suites,
/// and re-measuring them should not cost a teapot parse.
///
/// The numbers matter more than the convenience does: `kRadixThreshold`,
/// `RenderList.bvhThreshold` and the decision that this engine ships no native
/// sorting code are all quoted from this suite, and a measurement nobody can
/// re-run is a measurement nobody can contradict.
void main() async {
  await benchFrameMath();
}

/// Culling, sorting and matrix maths at the scale a frame actually does them.
Future<void> benchFrameMath() async {
  print('');
  print('--- per-frame maths ----------------------------------------------');

  // The shapes culling and sorting actually work on, at a scale where a native
  // rewrite would even be considered.
  const objectCount = 50000;
  final centres = List<Vector3>.generate(
    objectCount,
    (i) => Vector3(
      (i % 100) - 50.0,
      ((i ~/ 100) % 100) - 50.0,
      ((i ~/ 10000) % 100) - 50.0,
    ),
  );
  final radii = List<double>.generate(objectCount, (i) => 0.5);

  final view = makeViewMatrix(
    Vector3(0.0, 0.0, 120.0),
    Vector3.zero(),
    Vector3(0.0, 1.0, 0.0),
  );
  final projection = makePerspectiveMatrix(math.pi / 4, 16 / 9, 0.1, 500.0);
  final frustum = Frustum.matrix(projection * view);
  final probe = Sphere.centerRadius(Vector3.zero(), 1.0);

  var visible = 0;
  await bench(
    'frustum cull, $objectCount bounding spheres',
    50,
    () async {
      visible = 0;
      for (var i = 0; i < objectCount; i++) {
        probe.center.setFrom(centres[i]);
        probe.radius = radii[i];
        if (frustum.intersectsWithSphere(probe)) visible++;
      }
    },
    items: objectCount,
    unit: 'object',
  );
  print('  (…of which $visible visible)');

  // The same question at the scale that motivates a tree, answered both ways.
  //
  // The linear pass grows with the object count however few are on screen. The
  // tree rejects whole subtrees, so its cost tracks what is visible rather than
  // what exists — a change in shape, not in constant factor, and that is what
  // makes 200 000 objects affordable.
  //
  // Two worlds, because the answer depends entirely on which one you are in.
  // A dense cluster that fits in the frustum gives the tree nothing to reject,
  // and it can only lose. A world larger than the view is where it earns its
  // keep — and that is the world 200 000 objects implies.
  const bigCount = 200000;

  Float32List worldOf(double spread) {
    final spheres = Float32List(bigCount * 4);
    for (var i = 0; i < bigCount; i++) {
      spheres[i * 4] = ((i % 100) - 50.0) * spread;
      spheres[i * 4 + 1] = (((i ~/ 100) % 100) - 50.0) * spread;
      spheres[i * 4 + 2] = (((i ~/ 10000) % 100) - 50.0) * spread;
      spheres[i * 4 + 3] = 0.5;
    }
    return spheres;
  }

  final bigSpheres = worldOf(1.0);

  var bigVisible = 0;
  await bench(
    'frustum cull, $bigCount spheres, linear',
    5,
    () async {
      bigVisible = 0;
      for (var i = 0; i < bigCount; i++) {
        probe.center.setValues(
          bigSpheres[i * 4],
          bigSpheres[i * 4 + 1],
          bigSpheres[i * 4 + 2],
        );
        probe.radius = bigSpheres[i * 4 + 3];
        if (frustum.intersectsWithSphere(probe)) bigVisible++;
      }
    },
    items: bigCount,
    unit: 'object',
  );

  var stampSeed = 1;
  final tree = SceneBvh()..refresh(bigSpheres, bigCount, 1);
  var treeCandidates = 0;
  await bench(
    'frustum cull, $bigCount spheres, BVH (tree already built)',
    5,
    () async {
      treeCandidates = 0;
      tree.queryFrustum(frustum, (_) => treeCandidates++);
    },
    items: bigCount,
    unit: 'object',
  );
  print(
    '  (…$treeCandidates candidates offered from ${tree.nodeCount} '
    'nodes; the linear pass tested all $bigCount and found $bigVisible)',
  );

  await bench(
    'BVH rebuild, $bigCount spheres',
    3,
    // A fresh stamp each time, or refresh would recognise the data and
    // skip the work being measured.
    () async => tree.refresh(bigSpheres, bigCount, ++stampSeed),
    items: bigCount,
    unit: 'object',
  );

  // The same count spread over a world twenty times wider, so the frustum holds
  // a small slice of it. This is the shape a real scene has.
  final wideSpheres = worldOf(20.0);
  var wideVisible = 0;
  await bench(
    'frustum cull, $bigCount spheres in a wide world, linear',
    5,
    () async {
      wideVisible = 0;
      for (var i = 0; i < bigCount; i++) {
        probe.center.setValues(
          wideSpheres[i * 4],
          wideSpheres[i * 4 + 1],
          wideSpheres[i * 4 + 2],
        );
        probe.radius = wideSpheres[i * 4 + 3];
        if (frustum.intersectsWithSphere(probe)) wideVisible++;
      }
    },
    items: bigCount,
    unit: 'object',
  );

  final wideTree = SceneBvh()..refresh(wideSpheres, bigCount, 1);
  var wideCandidates = 0;
  await bench(
    'frustum cull, $bigCount spheres in a wide world, BVH',
    5,
    () async {
      wideCandidates = 0;
      wideTree.queryFrustum(frustum, (_) => wideCandidates++);
    },
    items: bigCount,
    unit: 'object',
  );
  print(
    '  (…$wideCandidates candidates offered, $wideVisible actually '
    'visible of $bigCount)',
  );

  // Sorting a packed-key render list, the shape RenderList produces.
  final keys = Int64List(objectCount);
  final random = math.Random(7);
  for (var i = 0; i < objectCount; i++) {
    keys[i] = random.nextInt(1 << 32);
  }
  final order = List<int>.generate(objectCount, (i) => i);

  await bench(
    'sort $objectCount packed int keys',
    20,
    () async {
      for (var i = 0; i < objectCount; i++) {
        order[i] = i;
      }
      order.sort((a, b) => keys[a].compareTo(keys[b]));
    },
    items: objectCount,
    unit: 'item',
  );

  // Same ordering, but with the index packed into the key so one typed-list sort
  // replaces the closure-with-indirection above.
  final packed = Int64List(objectCount);
  await bench(
    'sort $objectCount keys packed with index',
    20,
    () async {
      for (var i = 0; i < objectCount; i++) {
        // 20 bits of index is enough for a million draws.
        packed[i] = (keys[i] << 20) | i;
      }
      packed.sort();
    },
    items: objectCount,
    unit: 'item',
  );

  // The implementation the render list actually ships, so the number in the
  // analysis describes shipped code rather than a prototype.
  final shipped = Int64List(objectCount);
  final shippedScratch = Int64List(objectCount);
  final histogram = Uint32List(256);

  await bench(
    'sortPackedKeys (shipped), $objectCount entries',
    20,
    () async {
      for (var i = 0; i < objectCount; i++) {
        shipped[i] = (keys[i] << kPayloadBits) | i;
      }
      sortPackedKeys(shipped, shippedScratch, objectCount, counts: histogram);
    },
    items: objectCount,
    unit: 'item',
  );

  // The size a plain scene actually reaches, where the comparison sort wins and
  // the threshold picks it.
  const smallCount = 40;
  final small = Int64List(smallCount);
  final smallScratch = Int64List(smallCount);
  await bench('sortPackedKeys (shipped), $smallCount entries', 2000, () async {
    for (var i = 0; i < smallCount; i++) {
      small[i] = (keys[i] << kPayloadBits) | i;
    }
    sortPackedKeys(small, smallScratch, smallCount, counts: histogram);
  });

  // World-transform propagation: the multiply every dirty node performs.
  final parent = Matrix4.rotationY(0.3)..translateByDouble(1.0, 2.0, 3.0, 1.0);
  final local = Matrix4.rotationX(0.2)..translateByDouble(0.5, 0.0, 0.0, 1.0);
  final out = Matrix4.identity();

  await bench(
    'compose $objectCount world matrices',
    50,
    () async {
      for (var i = 0; i < objectCount; i++) {
        out.setFrom(parent);
        out.multiply(local);
      }
    },
    items: objectCount,
    unit: 'node',
  );

  // Inverse-transpose, which the renderer does per draw for normals.
  await bench(
    'invert+transpose 50000 matrices',
    20,
    () async {
      for (var i = 0; i < objectCount; i++) {
        out.setFrom(parent);
        out.invert();
        out.transpose();
      }
    },
    items: objectCount,
    unit: 'matrix',
  );
}
