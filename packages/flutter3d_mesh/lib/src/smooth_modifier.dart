part of 'modifier.dart';

/// A thin [Modifier] wrapper storing [smoothVertices]'s own parameters, the
/// same split [ArrayModifier] and [MirrorModifier] both make between "the
/// geometry" and "the stack step".
///
/// **Runs over every vertex of the base, on a copy.** Unlike `smoothVertices`
/// itself, which takes a [Selection] and moves the mesh it is handed in
/// place, a modifier has no selection to read and must never mutate [apply]'s
/// own `base` — the same rule every modifier here keeps, and for the same
/// reason: a stack evaluated twice from the same base must never find its own
/// first evaluation already sitting there.
final class SmoothModifier extends Modifier {
  const SmoothModifier({
    required this.iterations,
    this.lambda = 0.5,
    this.preserveVolume = false,
  });

  final int iterations;
  final double lambda;
  final bool preserveVolume;

  @override
  EditMesh apply(EditMesh base, ModifierContext context) {
    final copy = EditMesh.fromBytes(base.toBytes());
    final all = Selection.of(ElementLevel.vertex, <int>[
      for (var v = 0; v < copy.vertexSlotCount; v++)
        if (copy.isVertexAlive(v)) v,
    ]);
    copy.beginStep();
    smoothVertices(
      copy,
      all,
      iterations: iterations,
      lambda: lambda,
      preserveVolume: preserveVolume,
    );
    copy.endStep();
    return copy;
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'smooth',
    'iterations': iterations,
    'lambda': lambda,
    'preserveVolume': preserveVolume,
  };

  /// [SmoothModifier] from its own [toJson], or null when [iterations] is
  /// missing or of the wrong type. [lambda] and [preserveVolume] default the
  /// same way the constructor does when absent, matching how this class's
  /// own [toJson] always writes every field but a hand-built call — an MCP
  /// tool call, say — need not.
  static SmoothModifier? fromJson(Map<String, Object?> json) => switch (json) {
    {'iterations': final int iterations} => SmoothModifier(
      iterations: iterations,
      lambda: switch (json['lambda']) {
        final num lambda => lambda.toDouble(),
        _ => 0.5,
      },
      preserveVolume: switch (json['preserveVolume']) {
        final bool preserveVolume => preserveVolume,
        _ => false,
      },
    ),
    _ => null,
  };
}
