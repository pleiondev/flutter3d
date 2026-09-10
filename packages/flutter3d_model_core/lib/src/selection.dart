/// What is selected, at whatever level the modeller is working at.
///
/// **One value carrying both halves, because a command needs both.** "Extrude"
/// is a command about faces of one object; "move" is a command about either
/// three objects or forty vertices of one, and which it is decided by the mode.
/// A selection that held only the objects would leave every mesh command to
/// find the elements somewhere else, and a selection that held only the
/// elements would not know which object they were in.
///
/// **It is part of a command's arguments, not part of the document.** A step of
/// history replays with the selection it was made against, so an undo followed
/// by a redo does the same thing to the same elements even if the person has
/// clicked elsewhere in between. That is `doc-05`'s rule and it is the reason
/// this type is here rather than in the application.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// Which kind of thing is being selected.
enum SelectionMode { object, mesh }

/// Everything selected, in one value.
final class ProjectSelection {
  const ProjectSelection({
    this.mode = SelectionMode.object,
    this.objects = const <int>[],
    this.level = ElementLevel.vertex,
    this.elements = const <int>[],
  });

  /// Nothing selected, in the mode a project opens in.
  static const ProjectSelection none = ProjectSelection();

  final SelectionMode mode;

  /// Object ids, in the order they were picked, so the last one is the one a
  /// tool needing a single object should use.
  final List<int> objects;

  /// The level [elements] are at. Meaningless in object mode and kept anyway:
  /// a person who switches to mesh mode and back expects the level they left.
  final ElementLevel level;

  /// Element ids within [objects]`.last`, ascending.
  final List<int> elements;

  bool get isEmpty =>
      mode == SelectionMode.object ? objects.isEmpty : elements.isEmpty;

  /// The object a mesh command acts on, or null.
  ///
  /// The last picked rather than the first, because that is the one a person
  /// just clicked, and a mesh operation is always about the thing under the
  /// pointer.
  ///
  /// **The caller is the mesh commands of `doc-07`**, every one of which acts
  /// on one object and its elements — extrude, loop cut, dissolve — together
  /// with an editor's properties panel, which shows that object's name.
  int? get activeObject => objects.isEmpty ? null : objects.last;

  /// What the mesh package's own selection would be, for the element half.
  ///
  /// **The caller is the mesh commands of `doc-07`**, which hand it straight to
  /// `extrudeFaces`, `loopCut` and the rest: those take a `Selection` from
  /// `flutter3d_mesh` and know nothing about objects or modes.
  Selection get asMeshSelection => Selection.of(level, elements);

  ProjectSelection copyWith({
    SelectionMode? mode,
    List<int>? objects,
    ElementLevel? level,
    List<int>? elements,
  }) => ProjectSelection(
    mode: mode ?? this.mode,
    objects: objects ?? this.objects,
    level: level ?? this.level,
    elements: elements ?? this.elements,
  );

  /// This selection with anything the project no longer holds dropped.
  ///
  /// **What makes a selection survive an undo.** A step that deleted an object
  /// is undone, the object comes back under the id it had, and a selection that
  /// still names it is right again. A selection that had been cleared on the
  /// delete would not be. So nothing is cleared eagerly; it is filtered when it
  /// is read against a project, and an id that comes back comes back selected.
  ProjectSelection within(ModelProjectView project) => copyWith(
    objects: <int>[
      for (final int id in objects)
        if (project.holds(id)) id,
    ],
  );

  /// A sentence for the status line.
  String get says => switch (mode) {
    SelectionMode.object => switch (objects.length) {
      0 => 'nothing selected',
      1 => '1 object',
      final int many => '$many objects',
    },
    SelectionMode.mesh => switch (elements.length) {
      0 => 'nothing selected',
      1 => '1 ${level.name}',
      final int many => '$many ${level.name}s',
    },
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'objects': objects,
    'level': level.name,
    'elements': elements,
  };

  /// Reads one back, or null when the JSON is not one.
  ///
  /// **Null rather than an exception, and it is the same rule commands
  /// follow.** A project file is read a section at a time and a section that
  /// does not parse is skipped, so the failure has to be a value. Throwing here
  /// would make one stale selection lose a whole document.
  static ProjectSelection? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final mode = SelectionMode.values
        .where((SelectionMode each) => each.name == json['mode'])
        .firstOrNull;
    final level = ElementLevel.values
        .where((ElementLevel each) => each.name == json['level'])
        .firstOrNull;
    final objects = _ints(json['objects']);
    final elements = _ints(json['elements']);
    if (mode == null || level == null || objects == null || elements == null) {
      return null;
    }
    return ProjectSelection(
      mode: mode,
      objects: objects,
      level: level,
      elements: elements,
    );
  }

  static List<int>? _ints(Object? json) {
    if (json is! List) return null;
    final out = <int>[];
    for (final Object? each in json) {
      if (each is! int) return null;
      out.add(each);
    }
    return out;
  }

  @override
  String toString() => 'ProjectSelection(${mode.name}: $says)';
}

/// The one thing a selection asks a project.
///
/// An interface rather than the project itself, so that this file does not
/// depend on `project.dart` for a single question — and so a test can filter a
/// selection against a set of ids without building a document.
abstract interface class ModelProjectView {
  /// Whether an object with [id] is in the project.
  bool holds(int id);
}
