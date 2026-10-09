import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'gizmos.dart';

/// One thing in a level document, named the way a selection names it.
///
/// **The counterpart of [Handle], for a caller with no pixels.** `handlesOf`
/// answers "what is under this point on the screen", which is the only question
/// a mouse can ask; a program driving the same document from a socket or a
/// command line cannot point at anything, and until this existed it had no way
/// to find out what was in the level it was editing. It could move the third
/// brush and could not learn that there was a third brush.
///
/// A [kind] and an [index] rather than the object, for exactly the reason
/// `Editing.selected` is an index: those two are what `Editing.select` takes,
/// so a row read here can be selected without translating anything. And they are
/// the reason a listing has to be asked for again after a delete — the document
/// keeps three plain lists, so removing entity 2 makes entity 3 into entity 2,
/// and an index remembered across that change points at the wrong thing rather
/// than at nothing.
final class ListedPiece {
  const ListedPiece({
    required this.kind,
    required this.index,
    required this.what,
    required this.at,
    this.size,
    this.name,
    this.id,
  });

  /// The row's id, which `Editing.selectId` takes and which does not move
  /// when a row before it is deleted. Null only for a listing made by hand.
  final String? id;

  /// Which of the document's three lists this is in.
  final Piece kind;

  /// Which one in that list, which is what [Editing.select] takes.
  final int index;

  /// A brush's material, a light's type, an entity's type — the word that says
  /// what this row *is*, in the level's own vocabulary rather than in one this
  /// package invented.
  final String what;

  final Vector3 at;

  /// A brush's size, or an entity's when the document gave it one.
  ///
  /// Null for a light and for the entities that are a coordinate and a word:
  /// writing "0.5 × 0.5 × 0.5" for a monster would be reporting `gizmoSize`,
  /// which is a mark an editor draws rather than anything the document says.
  final Vector3? size;

  /// What the document calls this one, when it says — the name a door is opened
  /// by and a lift is called by.
  final String? name;

  /// One line, for a caller whose reply is text.
  ///
  /// The same shape as [Editing.says], deliberately: an agent that reads a
  /// listing and then reads back what it selected should be reading one
  /// vocabulary rather than two spellings of it.
  String get says => <String>[
    '${kind.name} $index',
    what,
    if (name != null) '"$name"',
    'at ${_place(at)}',
    if (size != null)
      '${_round(size!.x)}×${_round(size!.y)}×${_round(size!.z)}',
  ].join(' · ');

  /// The same row for a caller whose reply is JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'index': index,
    if (id != null) 'id': id,
    'what': what,
    'at': <double>[at.x, at.y, at.z],
    if (size != null) 'size': <double>[size!.x, size!.y, size!.z],
    if (name != null) 'name': name,
  };

  static String _place(Vector3 it) =>
      '${_round(it.x)}, ${_round(it.y)}, ${_round(it.z)}';

  /// A number as a person writes it: the grid is quarters, so `0.25` survives
  /// while `4.00` reads as `4`.
  ///
  /// **The third copy of three lines, and it is copied on purpose.**
  /// `editor_command.dart` has the same rounding as a private static, and
  /// opening it would publish a formatting helper from a package whose surface
  /// is meant to be a document and the things you can do to one. A shared
  /// spelling of "4" is not worth a public member somebody has to keep.
  static String _round(double it) {
    // A zero a sign has crept onto prints as "-0", which is a number nobody
    // writes and which turns up the moment a vector is negated.
    if (it == 0.0) return '0';
    final text = it.toStringAsFixed(2);
    final trimmed = text.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

/// Everything [level] holds, flat, in the order the document writes its lists.
///
/// **Flat because a selection is flat.** The document is three lists and
/// `Editing` selects into one of them by kind and index; a listing shaped as
/// three sections would be a second arrangement of the same facts, and the
/// caller would have to flatten it again before it could select anything.
///
/// Brushes, then lights, then entities — the order `handlesOf` walks them in
/// and the order they are written in the file, so the same document always
/// produces the same listing and a diff of two listings is a diff of two
/// documents.
List<ListedPiece> piecesOf(Level level) => <ListedPiece>[
  for (var i = 0; i < level.brushes.length; i++)
    ListedPiece(
      kind: Piece.brush,
      index: i,
      id: level.brushes[i].id,
      what: level.brushes[i].material,
      at: level.brushes[i].center,
      size: level.brushes[i].size,
    ),
  for (var i = 0; i < level.lights.length; i++)
    ListedPiece(
      kind: Piece.light,
      index: i,
      id: level.lights[i].id,
      what: level.lights[i].type.wireName,
      at: level.lights[i].position,
      name: level.lights[i].name,
    ),
  for (var i = 0; i < level.entities.length; i++)
    ListedPiece(
      kind: Piece.entity,
      index: i,
      id: level.entities[i].id,
      // An instance says which prefab, since `prefab` alone would read the
      // same for every one of them.
      what: switch (level.entities[i]) {
        final EntityDef e when e.type == EntityTypes.prefab =>
          'prefab ${e.properties['prefab']}',
        final EntityDef e => e.type,
      },
      at: level.entities[i].position,
      size: level.entities[i].vector('size'),
      name: level.entities[i].name,
    ),
];

/// The level's prefabs, one block each: the id, then one line per entity of
/// its template with the path an override addresses it by — what an agent
/// needs before it can write `setOverride` or `setPrefabField`.
///
/// A nested instance's line names its prefab, and its own entities follow
/// under the joined path, so every path an override can take is printed.
String prefabListing(Level level) {
  if (level.prefabs.isEmpty) return 'the level has no prefabs';
  final lines = <String>[];
  void walk(String id, String prefix, List<String> stack) {
    final prefab = level.prefabs[id];
    if (prefab == null) {
      lines.add('  $prefix… prefab "$id" is missing');
      return;
    }
    if (stack.contains(id)) {
      lines.add('  $prefix… prefab "$id" contains itself');
      return;
    }
    for (final entity in prefab.entities) {
      final path = '$prefix${prefabSegment(entity)}';
      final at = entity.position;
      final nested = entity.type == EntityTypes.prefab
          ? entity.properties['prefab']
          : null;
      lines.add(
        '  $path${entity.name == null ? '' : ' "${entity.name}"'} · '
        '${nested == null ? entity.type : 'prefab $nested'} at '
        '${at.x}, ${at.y}, ${at.z}',
      );
      if (nested is String) walk(nested, '$path/', <String>[...stack, id]);
    }
  }

  for (final id in level.prefabs.keys) {
    final placed = level.entities
        .where(
          (EntityDef e) =>
              e.type == EntityTypes.prefab && e.properties['prefab'] == id,
        )
        .length;
    lines.add('prefab $id · $placed placed');
    walk(id, '', const <String>[]);
  }
  return lines.join('\n');
}
