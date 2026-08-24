// ignore_for_file: avoid_print — this is a command-line benchmark whose whole
// output is stdout; a logging framework would be the wrong tool.

/// Runs [body] enough times to be measurable and reports per-iteration cost.
Future<void> bench(
  String name,
  int iterations,
  Future<void> Function() body, {
  String? unit,
  int? items,
}) async {
  // One untimed run so lazy initialization and first-call paths are not counted.
  await body();

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await body();
  }
  stopwatch.stop();

  final perIteration = stopwatch.elapsedMicroseconds / iterations;
  final label = perIteration >= 1000
      ? '${(perIteration / 1000).toStringAsFixed(2)} ms'
      : '${perIteration.toStringAsFixed(1)} us';

  var line = '${name.padRight(46)} $label';
  if (items != null && items > 0) {
    final ns = perIteration * 1000 / items;
    line += '   (${ns.toStringAsFixed(1)} ns per ${unit ?? 'item'})';
  }
  print(line);
}
