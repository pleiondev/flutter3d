part of 'modifier.dart';

/// A thin [Modifier] wrapper over [catmullClark], the same split
/// [ArrayModifier], [MirrorModifier] and [SmoothModifier] all make between
/// "the geometry" and "the stack step".
///
/// **[viewLevels] names a viewport concept this modifier does not have.**
/// The plan's own row asks for it alongside [levels] — a lower subdivision
/// count for interactive display, baked up to the real [levels] only for
/// export or a final render — but `apply` is the one place this modifier
/// does anything, and it is asked for *the* result, not a preview of one:
/// there is no second, cheaper code path here to hand a viewport instead.
/// [viewLevels] is carried through [toJson]/[fromJson] so a project that
/// sets it keeps the number, and is left for whichever viewport layer
/// chooses to read it and subdivide its own copy to fewer levels — nothing
/// this package does.
final class SubdivisionModifier extends Modifier {
  const SubdivisionModifier({required this.levels, int? viewLevels})
    : viewLevels = viewLevels ?? levels;

  /// How many Catmull-Clark passes [apply] actually folds into the result.
  final int levels;

  /// How many passes a viewport should show while editing — see the class
  /// doc comment for why nothing here reads this itself. Defaults to
  /// [levels] when not given, so a caller that never heard of the split
  /// gets one number that means the same thing everywhere.
  final int viewLevels;

  @override
  EditMesh apply(EditMesh base, ModifierContext context) =>
      catmullClark(base, levels: levels);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'subdivision',
    'levels': levels,
    'viewLevels': viewLevels,
  };

  /// [SubdivisionModifier] from its own [toJson], or null when [levels] is
  /// missing or of the wrong type. [viewLevels] defaults to [levels] the
  /// same way the constructor does when absent.
  static SubdivisionModifier? fromJson(Map<String, Object?> json) =>
      switch (json) {
        {'levels': final int levels} => SubdivisionModifier(
          levels: levels,
          viewLevels: switch (json['viewLevels']) {
            final int viewLevels => viewLevels,
            _ => null,
          },
        ),
        _ => null,
      };
}
