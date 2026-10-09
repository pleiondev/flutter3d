import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'editing.dart';
import 'gizmos.dart';

/// One row of an outliner: a thing in the level, and what to call it.
final class OutlineEntry {
  const OutlineEntry({
    required this.kind,
    required this.index,
    required this.label,
    required this.detail,
  });

  final Piece kind;

  /// Its place in the document's own list for [kind] — what selecting it
  /// hands [Editing.select].
  final int index;

  /// Its name when the document gave it one, otherwise what it is and its
  /// number.
  final String label;

  /// The second thing worth knowing: a brush's material, a light's type, an
  /// entity's type when it has a name of its own.
  final String detail;

  Picked get picked => (kind: kind, index: index);
}

/// A heading in an outliner and the rows under it.
final class OutlineGroup {
  const OutlineGroup({
    required this.title,
    required this.kind,
    required this.entries,
  });

  /// What the heading says: `Brushes`, `Lights`, or an entity type.
  final String title;
  final Piece kind;
  final List<OutlineEntry> entries;
}

/// The level as a tree: its brushes, its lights, and its entities by type.
///
/// **Entities by type, because that is how a level is read.** A crypt has one
/// spawn, six torches and a dozen monsters, and the question somebody brings
/// to the outliner is "where are the torches" rather than "what is entity
/// forty"; one heading per type answers it, in the order the types first
/// appear in the document, which is the order the generator and the author
/// put them down.
///
/// [filter] keeps the rows whose label or detail contains it, ignoring case,
/// and drops the headings left with nothing under them. Nothing in here needs
/// a window, so what the tree is is tested without one.
List<OutlineGroup> outlineOf(Level level, {String filter = ''}) {
  final wanted = filter.trim().toLowerCase();
  bool keeps(OutlineEntry it) =>
      wanted.isEmpty ||
      it.label.toLowerCase().contains(wanted) ||
      it.detail.toLowerCase().contains(wanted);

  final brushes = <OutlineEntry>[
    for (var i = 0; i < level.brushes.length; i++)
      OutlineEntry(
        kind: Piece.brush,
        index: i,
        label: 'brush $i',
        detail: level.brushes[i].material,
      ),
  ];
  final lights = <OutlineEntry>[
    for (var i = 0; i < level.lights.length; i++)
      OutlineEntry(
        kind: Piece.light,
        index: i,
        label: level.lights[i].name ?? 'light $i',
        detail: level.lights[i].type.name,
      ),
  ];
  final types = <String>{for (final e in level.entities) e.type};
  final entities = <String, List<OutlineEntry>>{
    for (final type in types)
      type: <OutlineEntry>[
        for (var i = 0; i < level.entities.length; i++)
          if (level.entities[i].type == type)
            OutlineEntry(
              kind: Piece.entity,
              index: i,
              label: level.entities[i].name ?? '$type $i',
              detail: level.entities[i].name == null ? '' : type,
            ),
      ],
  };

  return <OutlineGroup>[
    for (final (title, kind, entries) in <(String, Piece, List<OutlineEntry>)>[
      ('Brushes', Piece.brush, brushes),
      ('Lights', Piece.light, lights),
      for (final entry in entities.entries)
        (entry.key, Piece.entity, entry.value),
    ])
      if (entries.where(keeps).toList() case final kept when kept.isNotEmpty)
        OutlineGroup(title: title, kind: kind, entries: kept),
  ];
}
