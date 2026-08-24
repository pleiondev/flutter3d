// ignore_for_file: avoid_print — this is a command-line benchmark whose whole
// output is stdout; a logging framework would be the wrong tool.
//
// Measures the CPU work that FFI would be a candidate to replace.
//
// Standalone Dart on purpose: compiled with `dart compile exe` it runs through
// the same AOT pipeline a release build uses, so the numbers reflect what ships
// rather than JIT warm-up. That matters because "Dart is slow, move it to C" is
// an assumption worth testing before paying for a native build.
//
// Only the layers that are free of flutter_gpu can be measured this way, which is
// most of the interesting ones: geometry generation, glTF and OBJ decoding, and
// the per-frame maths that culling and sorting are built from.
//
// Split into one file per suite — bench_assets.dart, bench_geometry.dart and
// bench_frame_math.dart — because each measures an unrelated layer and shares
// nothing but the `bench()` helper in bench_util.dart.

import 'bench_assets.dart';
import 'bench_frame_math.dart';
import 'bench_geometry.dart';

void main() async {
  await benchAssetDecoding();
  await benchGeometryGeneration();
  await benchFrameMath();

  print('');
  print('Frame budget at 60 Hz is 16.6 ms; at 120 Hz, 8.3 ms.');
}
