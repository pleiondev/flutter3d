/// `anim-18`'s own row: a second document, read for [retargetClip] alone —
/// screen 14's "import a source clip", which is deliberately **not** the
/// same door `fromModelDocument`'s own importer opens onto the live
/// project.
///
/// **Why a source stays its own [ModelProject].** [retargetClip] already
/// takes `sourceProject`/`sourceSkeleton` apart from `targetProject`/
/// `targetSkeleton` — two whole documents, not one project holding both
/// rigs — because a mocap file and the character being animated share
/// nothing: not a skeleton, not an object table, usually not even a scale.
/// Merging the source into the target the way `importInto` merges a prop
/// would give the target's own `nextId` a hundred new joints it never asked
/// for and that nothing but this one retarget ever reads again. A
/// [RetargetSource] is read once, retargeted from, and thrown away.
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'project_animation.dart';
import 'project_document.dart';

/// A file opened for retargeting alone — [project] and [skeleton] are read
/// by [retargetClip], never merged into the document being edited.
final class RetargetSource {
  const RetargetSource({
    required this.name,
    required this.project,
    required this.skeletonIndex,
    this.warning,
  });

  /// The file's own name, for the clip library's own card and the status
  /// line — not [ModelDocument]'s own concern, since a decoded document
  /// carries no file name at all.
  final String name;

  /// Read through [fromModelDocument], the same importer the live document
  /// uses — but never folded into it. See the library doc comment.
  final ModelProject project;

  /// Which of [project]'s own skeletons [retargetClip] reads as
  /// `sourceSkeleton` — always `0` today, since a source file names at most
  /// one rig worth retargeting from.
  final int skeletonIndex;

  /// Set when [project] carried no skin at all and [skeleton] had to be
  /// synthesised from its animated nodes — screen 14's own warning card:
  /// "imported without a skin — mapped by node names only". Null for a file
  /// that named a real skin, which is the ordinary case.
  final String? warning;

  ProjectSkeleton get skeleton => project.skeletons[skeletonIndex];

  /// Every clip [project] carries — the clip library's own card list.
  List<ProjectClip> get clips => project.clips;

  /// [document] read as a [RetargetSource] named [name].
  ///
  /// **The ordinary case:** [fromModelDocument] already builds
  /// [ModelProject.skeletons] from [ModelDocument.skins] — see that
  /// function's own doc comment — so a file exported with a real skin (an
  /// FBX or glTF mocap take bound to a rig) comes back with [warning] null
  /// and [skeletonIndex] naming that skin directly.
  ///
  /// **The no-skin case, screen 14's own warning.** A raw motion-capture
  /// hierarchy — a BVH, or an FBX exported as bones with no bound mesh —
  /// carries animated nodes and no [ModelDocument.skins] entry at all:
  /// [fromModelDocument] then hands back a project with an empty
  /// [ModelProject.skeletons], nothing [retargetClip] can read a
  /// `sourceSkeleton` off. This synthesises one instead: every object that
  /// at least one clip actually animates, in the project's own object
  /// order, becomes a joint of a fresh [ProjectSkeleton] — mapped onto the
  /// target afterwards by name alone, exactly as honest as that sounds,
  /// which is why [warning] is set to say so rather than silently pretend
  /// this is a real skin.
  factory RetargetSource.fromDocument(String name, ModelDocument document) {
    final ModelProject imported = fromModelDocument(document);
    if (imported.skeletons.isNotEmpty) {
      return RetargetSource(name: name, project: imported, skeletonIndex: 0);
    }

    final Set<int> animated = <int>{
      for (final ProjectClip clip in imported.clips)
        for (final ProjectTrack track in clip.tracks) track.objectId,
    };
    final List<int> joints = <int>[
      for (final ModelObject object in imported.objects)
        if (animated.contains(object.id)) object.id,
    ];
    final ProjectSkeleton synthesized = ProjectSkeleton(
      joints: joints,
      inverseBindMatrices: List<Matrix4>.generate(
        joints.length,
        (_) => Matrix4.identity(),
      ),
    );
    return RetargetSource(
      name: name,
      project: imported.copyWith(skeletons: <ProjectSkeleton>[synthesized]),
      skeletonIndex: 0,
      warning: 'Imported without a skin — mapped by node names only.',
    );
  }
}
