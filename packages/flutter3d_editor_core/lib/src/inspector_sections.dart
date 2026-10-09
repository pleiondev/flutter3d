/// Which heading of an inspector each field of the selected thing goes under.
///
/// **Pure data, so it lives here rather than in a panel.** The sections are a
/// reading aid — where a thing is, what it looks like, how it collides, what
/// a light does, an entity's own properties — and which key belongs to which
/// is a fact about the level format and the plugins installed, not about
/// widgets. The editor's panel draws what [inspectorSections] answers.
library;

import 'editor_pieces.dart';
import 'gizmos.dart';

/// The editor's own components, in the order an inspector shows them, each
/// piece's last one taking every key no section names.
///
/// A plugin's [EditorComponent] lands after the ones of its piece and before
/// that last one — see [inspectorComponents].
const List<EditorComponent> builtInComponents = <EditorComponent>[
  EditorComponent(
    kind: 'brush.transform',
    title: 'Transform',
    piece: Piece.brush,
    keys: <String>{'at', 'size'},
  ),
  EditorComponent(
    kind: 'brush.rendering',
    title: 'Rendering',
    piece: Piece.brush,
    keys: <String>{
      'material',
      'castsShadow',
      'shadowCasting',
      'layer',
      'drawOrder',
      'depthLayer',
    },
  ),
  EditorComponent(
    kind: 'brush.collision',
    title: 'Collision',
    piece: Piece.brush,
    keys: <String>{'solid', 'surface', 'ramp'},
  ),
  EditorComponent(kind: 'brush.other', title: 'Other', piece: Piece.brush),
  EditorComponent(
    kind: 'light.transform',
    title: 'Transform',
    piece: Piece.light,
    keys: <String>{'at', 'direction'},
  ),
  EditorComponent(
    kind: 'light.light',
    title: 'Light',
    piece: Piece.light,
    keys: <String>{
      'type',
      'intensity',
      'range',
      'color',
      'castsShadow',
      'name',
    },
  ),
  EditorComponent(kind: 'light.other', title: 'Other', piece: Piece.light),
  EditorComponent(
    kind: 'entity.entity',
    title: 'Entity',
    keys: <String>{'type', 'name'},
  ),
  EditorComponent(
    kind: 'entity.transform',
    title: 'Transform',
    keys: <String>{'at', 'yaw'},
  ),
  // An instance's link and what it changes in its template; empty, and so
  // not shown, for every entity that is not an instance.
  EditorComponent(
    kind: 'entity.prefab',
    title: 'Prefab',
    keys: <String>{'prefab', 'overrides'},
  ),
  EditorComponent(kind: 'entity.properties', title: 'Properties'),
];

/// The components an inspector shows for a [piece] of entity type [type], in
/// order: the editor's own but the last, then the ones [pieces] adds that
/// belong there, then the editor's last, which takes every key none names.
List<EditorComponent> inspectorComponents(
  Piece piece, {
  String? type,
  EditorPieces? pieces,
}) {
  final own = <EditorComponent>[
    for (final component in builtInComponents)
      if (component.piece == piece) component,
  ];
  return <EditorComponent>[
    ...own.take(own.length - 1),
    ...?pieces?.componentsFor(piece, type),
    own.last,
  ];
}

/// [keys] sorted into the [inspectorComponents] of [piece]: each section's
/// title with the keys it holds, in order, and sections left empty dropped.
///
/// A key two sections name goes to the first; a key none names goes to the
/// last, so the grouping can never hide a field.
List<(String, List<String>)> inspectorSections(
  Piece piece,
  Iterable<String> keys, {
  String? type,
  EditorPieces? pieces,
}) {
  final all = inspectorComponents(piece, type: type, pieces: pieces);
  final sorted = keys.toList()..sort();
  final placed = <String>{};
  return <(String, List<String>)>[
    for (final (index, component) in all.indexed)
      if (<String>[
            for (final key in sorted)
              if ((component.fields.contains(key) ||
                      (index == all.length - 1 &&
                          !all.any((c) => c.fields.contains(key)))) &&
                  placed.add(key))
                key,
          ]
          case final held when held.isNotEmpty)
        (component.title, held),
  ];
}
