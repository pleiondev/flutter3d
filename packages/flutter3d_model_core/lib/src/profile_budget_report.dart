/// `anim-24`'s own row: "Screen 19: profile budgets (triangles, bones,
/// textures, influences), `wireframeDeclined` reported honestly."
///
/// **What this is not.** `Screen 19` itself — the timeline, the transport
/// bar, the budget bars — is `ui-28`'s own Flutter shell, not built here.
/// [ProfileBudgetReport] is the number a bar would read, the same way
/// `view-17`'s own engine half closed by proving `FrameResult.triangles`
/// without building the viewport that would paint it: prove the measurement,
/// name the screen as separate, undone work.
///
/// **Nothing here reimplements a check.** The triangle budget is
/// [ExportReadiness]'s own `_budget`, read back rather than re-derived; the
/// texture budget is `mat-28`'s [measure]; the joint and influence counts
/// walk the same [ProjectSkeleton]/[weightsOf] data `rigIssues` already
/// walks, because a bar and an export warning asking "how many joints does
/// this rig have" deserve the same answer.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'project.dart';
import 'texture_budget.dart';

/// One bar's own number: how much of a profile's limit is spent, in the
/// unit the limit is named in — triangles, joints, influences, bytes.
final class BudgetUsage {
  const BudgetUsage({required this.used, required this.limit});

  final int used;
  final int limit;

  /// `used / limit` — the number a bar's width or colour reads, never
  /// dividing by zero: a limit of 0 reads as spent (`1.0`) the moment
  /// anything at all is used, and unspent (`0.0`) otherwise. A limit of 0
  /// with nothing used is not a project over its own budget.
  double get fraction => limit <= 0 ? (used > 0 ? 1.0 : 0.0) : used / limit;

  /// Whether this bar alone paints orange — `anim-24`'s own acceptance:
  /// `maxJoints=16` on 19 joints.
  bool get over => used > limit;

  @override
  String toString() => 'BudgetUsage($used/$limit)';
}

/// Every "Screen 19" bar's own number, measured once against [project]'s
/// own [ProjectProfile].
final class ProfileBudgetReport {
  const ProfileBudgetReport({
    required this.triangles,
    required this.joints,
    required this.influences,
    required this.textureBytes,
    required this.wireframeDeclined,
  });

  /// Measures [project] against its own [ModelProject.profile].
  factory ProfileBudgetReport.of(ModelProject project) {
    final profile = project.profile;

    var maxJointsUsed = 0;
    for (final skeleton in project.skeletons) {
      if (skeleton.jointCount > maxJointsUsed) {
        maxJointsUsed = skeleton.jointCount;
      }
    }

    var maxInfluencesUsed = 0;
    for (final object in project.objects) {
      if (object.skeletonIndex == null) continue;
      if (object.geometry case EditedGeometry(:final EditMesh mesh)) {
        for (var v = 0; v < mesh.vertexSlotCount; v++) {
          if (!mesh.isVertexAlive(v)) continue;
          final count = weightsOf(mesh, v).length;
          if (count > maxInfluencesUsed) maxInfluencesUsed = count;
        }
      }
    }

    final textureUsage = measure(project, profile.textures);

    return ProfileBudgetReport(
      triangles: BudgetUsage(
        used: project.triangleCount,
        limit: profile.maxTriangles,
      ),
      joints: BudgetUsage(used: maxJointsUsed, limit: profile.maxJoints),
      influences: BudgetUsage(
        used: maxInfluencesUsed,
        limit: profile.maxInfluences,
      ),
      textureBytes: BudgetUsage(
        used: textureUsage.totalBytes,
        limit: profile.textures.maxBytesOnDevice,
      ),
      wireframeDeclined: true,
    );
  }

  final BudgetUsage triangles;
  final BudgetUsage joints;
  final BudgetUsage influences;
  final BudgetUsage textureBytes;

  /// `Screen 19` names a wireframe toggle among its budget bars; nothing
  /// draws one — [RenderShading] (`mcp-01n`'s own `render_project.dart`)
  /// offers `material`/`normals` only, for the same reason. Always `true`
  /// today: a field rather than a bare doc comment, so a caller can show
  /// the same honest "not built" state without reading this file's history.
  final bool wireframeDeclined;

  /// Whether any bar here is over its own limit.
  bool get anyOver =>
      triangles.over || joints.over || influences.over || textureBytes.over;

  @override
  String toString() =>
      'ProfileBudgetReport(triangles: $triangles, joints: $joints, '
      'influences: $influences, textureBytes: $textureBytes)';
}
