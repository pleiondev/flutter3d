/// Putting a gallery item into the open document — `gal-03`.
///
/// **One step, beside what is already there.** A gallery insert is not an
/// open: the scene somebody is building stays, and the thing they picked
/// arrives next to it. That is `importInto`'s own job for a dropped file,
/// and this is the same call with the model coming from a catalogue rather
/// than a picker — so a lamp from the gallery and a lamp from disk land the
/// same way, undo the same way, and export the same way.
///
/// **Pure: a project in, a project out.** Nothing here touches a cubit, a
/// context or a history, which is what lets the rule be tested without a
/// window — and what makes the one command the caller runs obvious rather
/// than buried in a screen.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' hide ImportReport;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'gallery_item.dart';

/// What an insert did: the project afterwards, and the ids it made.
typedef GalleryInsert = ({ModelProject project, List<int> ids});

/// [model] added to [project], named after [item].
///
/// **A built model goes in as editable geometry, not as a decoded file.**
/// `gal-02`'s recipes produce an `EditMesh`; writing it to glTF and reading
/// it back would lose the topology that makes it worth having and cost a
/// round trip to do it.
GalleryInsert insertIntoProject(
  ModelProject project,
  GalleryItem item,
  GalleryModel model, {
  ModelDocument Function(FetchedModel)? decode,
}) {
  switch (model) {
    case BuiltModel(:final EditMesh mesh):
      final ModelProject after = project.added(
        (int id) => ModelObject(
          id: id,
          name: item.name,
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
          credit: creditFor(item),
        ),
      );
      return (project: after, ids: <int>[after.objects.last.id]);
    case FetchedModel():
      final ModelDocument? document = decode?.call(model);
      if (document == null) {
        // Nothing to add rather than a half-import: a caller with no
        // decoder is a caller that asked for a file it cannot read, and
        // saying so is the screen's job.
        return (project: project, ids: const <int>[]);
      }
      final ImportReport report = importInto(project, document);
      // `importInto` appends, so everything past the old length is what
      // this insert brought in — the same reasoning the file import
      // already uses to find its own new ids.
      final List<int> ids = <int>[
        for (final ModelObject object in report.project.objects.skip(
          project.objects.length,
        ))
          object.id,
      ];
      // `gal-05`: every object the item brought in carries the credit, not
      // just the first — an export reads the objects that are in it, and a
      // file whose only credited object was deleted would owe nothing when
      // its siblings are still there.
      final ModelCredit? credit = creditFor(item);
      var after = report.project;
      if (credit != null) {
        for (final int id in ids) {
          final ModelObject? object = after[id];
          if (object == null) continue;
          after = after.withObject(object.copyWith(credit: credit));
        }
      }
      return (project: after, ids: ids);
  }
}

/// The credit [item] owes, or null where its licence asks for nothing.
///
/// **Recorded at the insert, not worked out at the export.** A catalogue
/// can change under a document — a source goes away, an item is relicensed
/// — and the obligation belongs to the moment somebody took the model, not
/// to whatever the internet says the day they export.
ModelCredit? creditFor(GalleryItem item) {
  if (!item.licence.requiresAttribution) return null;
  final String? author = item.author;
  // `gal-01` refuses an item that asks for a credit and names nobody, so
  // this cannot happen through the screen; it is here because a caller
  // that builds an item by hand can.
  if (author == null || author.trim().isEmpty) return null;
  return (
    title: item.name,
    author: author,
    licence: item.licence.name,
    url: item.licence.url,
  );
}

/// What the console says after an insert.
///
/// Names the item and, where the licence asks for one, the person to
/// credit — so the obligation is visible at the moment it is taken on
/// rather than at export time.
String insertSaid(GalleryItem item, int objects) {
  final String what = objects == 1 ? 'object' : 'objects';
  if (item.licence.requiresAttribution && item.author != null) {
    return 'inserted ${item.name} ($objects $what) — '
        '${item.licence.name}, by ${item.author}';
  }
  return 'inserted ${item.name} ($objects $what)';
}
