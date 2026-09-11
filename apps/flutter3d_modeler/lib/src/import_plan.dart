/// What an import screen needs to decide before and after a file decodes —
/// `ui-16`'s own pure-Dart half, `import_plan_test` without Flutter. The
/// screen itself, its warnings list and its bounds preview are a widget's
/// job; deciding how many warnings there are, whether a project's own
/// profile can hold what came in, and what a model's own bounds read as
/// once its unit is known needs none of that.
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

/// The unit a model's own file measures in, and the multiplier that reads
/// it as this project's own metres — every other placement in the project
/// is already in them, and a `.stl` file in particular carries no unit at
/// all, conventionally millimetres.
enum ImportUnit {
  millimetres(0.001),
  centimetres(0.01),
  metres(1.0);

  const ImportUnit(this.scale);

  /// [ImportOptions.scale]'s own value for a file authored in this unit.
  final double scale;
}

/// Whether a candidate file can even be opened, decided from its own byte
/// length alone — the one limit that needs no document, because the file
/// has not been decoded yet.
///
/// `ui-16`'s own "файл сверх лимита на вебе — отказ до декодирования": a
/// browser tab has no swap and a model too large to decode there is worth
/// refusing before spending the time finding that out. Null on any other
/// platform — [onWeb] is the only case this limit exists for.
String? refuseBeforeDecoding({
  required int fileSizeBytes,
  required bool onWeb,
  int webFileSizeLimitBytes = 30 * 1024 * 1024,
}) {
  if (!onWeb || fileSizeBytes <= webFileSizeLimitBytes) return null;
  final mb = fileSizeBytes / (1024 * 1024);
  final limitMb = webFileSizeLimitBytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)} MB is over the '
      '${limitMb.toStringAsFixed(0)} MB a browser tab can decode safely.';
}

/// [document]'s own triangle count, added across every surface it carries.
int triangleCountOf(ModelDocument document) {
  var total = 0;
  for (final surface in document.surfaces) {
    total += surface.mesh.triangleCount;
  }
  return total;
}

/// What an import screen shows once [document] has decoded: how many
/// warnings it carries, whether [profile] can hold it, and its own bounds
/// read in [unit].
final class ImportPlan {
  ImportPlan({
    required this.document,
    required this.profile,
    this.unit = ImportUnit.metres,
  }) : triangleCount = triangleCountOf(document);

  final ModelDocument document;
  final ProjectProfile profile;
  final ImportUnit unit;

  /// The number of triangles [document] carries, computed once at
  /// construction rather than on every read — the same reason
  /// [ModelAsset.triangleCount] the engine already has exists at all.
  final int triangleCount;

  List<String> get warnings => document.warnings;

  int get warningCount => warnings.length;

  /// Whether [profile]'s own triangle budget can hold [document] as
  /// decoded — before [unit] scales anything, since a unit changes size,
  /// not triangle count.
  bool get exceedsTriangleBudget => triangleCount > profile.maxTriangles;

  /// [document]'s own bounds, in [unit] read as this project's metres —
  /// `ui-16`'s own worked example: an `.stl` in millimetres, opened with
  /// "mm" chosen, reads its bounds back in metres.
  Aabb3 get scaledBounds {
    final raw = document.computeBounds();
    final scale = unit.scale;
    return Aabb3.minMax(raw.min * scale, raw.max * scale);
  }

  /// [ImportOptions] this plan's own [unit] and [upAxis] choice resolve
  /// to — what `fromModelDocument` actually reads.
  ImportOptions optionsWith({UpAxis upAxis = UpAxis.y}) =>
      ImportOptions(scale: unit.scale, upAxis: upAxis);
}
