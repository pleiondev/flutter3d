import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// A level document, open and being changed.
///
/// **Everything an editor does that is not drawing.** Selecting, moving,
/// resizing, adding, deleting, undoing and writing back — none of which needs a
/// window, and all of which is the part that can lose somebody's work. The
/// widget above it owns a camera and a mouse; this owns the document.
final class Editing {
  Editing({required this.level, required this.path});

  /// Reads a document off the disk.
  ///
  /// [text] rather than a file, because the caller knows where documents come
  /// from and this does not: on a desktop that is `File.readAsString`, in a
  /// test it is a string in the test.
  factory Editing.parse(String text, {required String path}) => Editing(
        level: Level.fromJson(jsonDecode(text) as Map<String, Object?>),
        path: path,
      );

  /// The document. Replaced wholesale by [undo], which is why it is not final.
  Level level;

  /// Where it came from, for writing it back and for saying so on screen.
  final String path;

  /// Which brush is being worked on, or null.
  ///
  /// An index rather than the brush itself: the list is what gets edited, and a
  /// reference into a list that undo has just replaced is a reference to a
  /// brush that is no longer in the document.
  int? selected;

  Brush? get brush {
    final index = selected;
    if (index == null || index < 0 || index >= level.brushes.length) return null;
    return level.brushes[index];
  }

  /// Who wrote this document, if it says.
  ///
  /// **The question an editor has to ask before it is allowed to save**, and
  /// the document format already had the answer: `generatedBy` is written by
  /// the Python that produced most of the levels in this repository, and the
  /// level's own doc comment says a writer that dropped the key "would quietly
  /// erase the answer to who owns this document".
  String? get generatedBy {
    final source = level.toJson()['generatedBy'];
    return source is String ? source : null;
  }

  /// Whether saving over this document is allowed.
  ///
  /// **A generated file belongs to its generator.** Editing `crypt.json` by
  /// hand and saving it produces a file that looks edited right up until
  /// somebody runs `make_crypt.py` again, at which point the afternoon is
  /// gone — and nothing would have said so. The editor can open one, fly
  /// around it and change it; what it will not do is write it back over the
  /// tool that owns it. Saving it somewhere else is a decision a person makes
  /// rather than one a program makes for them.
  bool get mayOverwrite => generatedBy == null;

  /// Whether anything has been changed since the last save.
  bool get isDirty => _dirty;
  bool _dirty = false;

  /// How far a nudge moves, and what every edited number is rounded to.
  ///
  /// **A quarter of a metre, because an editor without a grid writes documents
  /// full of 3.0000001.** Every level in this repository was produced by a
  /// generator writing rounded numbers, and a hand-edited brush sitting a
  /// millionth of a metre off is a diff nobody can read and a seam a player can
  /// see light through.
  double grid = 0.25;

  /// The smallest a brush may be made. Below this it is invisible, unclickable
  /// and impossible to get back.
  static const double minimumSize = 0.25;

  final List<Map<String, Object?>> _undo = <Map<String, Object?>>[];

  /// How many steps back an editor can go. Whole documents rather than a list
  /// of reversible operations: a level is a few hundred numbers, and an undo
  /// that reconstructs state is an undo with its own bugs.
  static const int undoDepth = 64;

  void _remember() {
    _undo.add(level.toJson());
    if (_undo.length > undoDepth) _undo.removeAt(0);
    _dirty = true;
  }

  /// Whether there is anything to go back to.
  bool get canUndo => _undo.isNotEmpty;

  /// Puts the document back the way it was before the last change.
  ///
  /// The selection survives if it still points at something, which is what
  /// makes undoing a nudge feel like undoing a nudge rather than like losing
  /// the brush.
  void undo() {
    if (_undo.isEmpty) return;
    level = Level.fromJson(_undo.removeLast());
    final index = selected;
    if (index != null && index >= level.brushes.length) selected = null;
    _dirty = true;
  }

  /// Picks a brush, or nothing.
  void select(int? index) {
    if (index != null && (index < 0 || index >= level.brushes.length)) {
      selected = null;
      return;
    }
    selected = index;
  }

  /// Moves the selected brush, snapping it to the grid.
  void nudge(Vector3 by) {
    final it = brush;
    if (it == null) return;
    _remember();
    it.centre.setValues(
      _snap(it.centre.x + by.x),
      _snap(it.centre.y + by.y),
      _snap(it.centre.z + by.z),
    );
  }

  /// Grows or shrinks the selected brush about its own centre.
  void grow(Vector3 by) {
    final it = brush;
    if (it == null) return;
    _remember();
    it.size.setValues(
      math.max(minimumSize, _snap(it.size.x + by.x)),
      math.max(minimumSize, _snap(it.size.y + by.y)),
      math.max(minimumSize, _snap(it.size.z + by.z)),
    );
  }

  /// Adds a brush and selects it.
  ///
  /// The material is whatever the document already uses most, because a brush
  /// naming a material the level does not have draws as grey and reads as a
  /// bug — the validator says so, and an editor that produced them by default
  /// would be an editor whose first act is a warning.
  void add(Vector3 at, {Vector3? size}) {
    _remember();
    level.brushes.add(Brush(
      centre: Vector3(_snap(at.x), _snap(at.y), _snap(at.z)),
      size: size ?? Vector3(2.0, 2.0, 2.0),
      material: commonestMaterial,
    ));
    selected = level.brushes.length - 1;
  }

  /// Copies the selected brush, one of its own widths to the side.
  ///
  /// Beside rather than on top: two brushes in the same place are one brush as
  /// far as anybody can see, and an editor whose duplicate is invisible is an
  /// editor that appears not to have done anything.
  void duplicate() {
    final it = brush;
    if (it == null) return;
    _remember();
    level.brushes.add(Brush(
      centre: it.centre + Vector3(it.size.x, 0.0, 0.0),
      size: it.size,
      material: it.material,
      surface: it.surface == it.material ? null : it.surface,
      solid: it.solid,
      castsShadow: it.castsShadow,
      layer: it.layer,
      ramp: it.ramp,
    ));
    selected = level.brushes.length - 1;
  }

  /// Deletes the selected brush.
  void remove() {
    final index = selected;
    if (index == null || index >= level.brushes.length) return;
    _remember();
    level.brushes.removeAt(index);
    selected = null;
  }

  /// The material most of this level is made of, or `default`.
  String get commonestMaterial {
    if (level.brushes.isEmpty) return 'default';
    final counts = <String, int>{};
    for (final brush in level.brushes) {
      counts[brush.material] = (counts[brush.material] ?? 0) + 1;
    }
    var best = level.brushes.first.material;
    for (final entry in counts.entries) {
      if (entry.value > (counts[best] ?? 0)) best = entry.key;
    }
    return best;
  }

  /// What everything this level names is worth, as the game would see it.
  ///
  /// The editor's own reason for existing beside a generator: a level that
  /// cannot be finished is not a level, and finding that out twenty minutes
  /// into playing it is worse than being told while it is being built.
  List<LevelIssue> issuesFor(EntityRegistry registry) =>
      LevelValidator(registry: registry).validate(level);

  /// The document as text, ready to be written.
  ///
  /// Indented, because these files are read by people and compared by `git
  /// diff` — the generators write them that way, and an editor that collapsed
  /// one onto a single line would turn a two-line change into a whole-file one.
  ///
  /// [claiming] takes ownership: `generatedBy` becomes this editor's name
  /// rather than the tool's. **A copy of a generated document has to claim
  /// it**, and this is the other half of [mayOverwrite]: a file saved beside
  /// `crypt.json` still saying it was written by `make_crypt.py` is a file that
  /// invites somebody to regenerate it, and regenerating it is exactly what
  /// throws the work away.
  String write({String? claiming}) {
    final document = level.toJson();
    if (claiming != null) document['generatedBy'] = claiming;
    return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
  }

  /// Says the document has been written, so it stops calling itself unsaved.
  void saved() => _dirty = false;

  double _snap(double value) =>
      grid <= 0.0 ? value : (value / grid).roundToDouble() * grid;
}
