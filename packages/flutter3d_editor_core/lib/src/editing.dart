import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'editor_history.dart';
import 'gizmos.dart';
import 'lesson_authoring.dart';
import 'palette_items.dart';

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

  /// The document. Replaced wholesale by [history] when it goes back, which is
  /// why it is not final.
  Level level;

  /// Where it came from, for writing it back and for saying so on screen.
  final String path;

  /// What is being worked on: which list, and which one in it.
  ///
  /// An index rather than the object itself, because the list is what gets
  /// edited and a reference into a list that undo has just replaced is a
  /// reference to something no longer in the document.
  ///
  /// **A kind as well as an index, because a level is three lists.** The first
  /// version of this could only hold a brush, which meant an editor that could
  /// not touch a light, a monster, a lift or the point the player starts at —
  /// most of what a level *is* once its walls are up.
  Piece? kind;
  int? selected;

  /// `edu-01`'s "разборка перетаскиванием" — which `edu_step`, if any, a
  /// nudge writes into instead of moving the selection.
  ///
  /// **A UI mode, not a document field.** Toggling it changes nothing in
  /// [level] by itself — an MCP caller reaches the identical result through
  /// a plain `setField('offsets', ...)`, the same as [nudgeOffset] ends up
  /// calling. This field only decides which entity the *keyboard* is
  /// presently talking to — a fact about the session, gone the moment the
  /// document reopens, the same as [grid]. What *is* new is [NudgeOffset]
  /// (`editor_command.dart`) — one more command, not the "no new
  /// architecture" this comment used to claim: a keystroke or a tool server
  /// has to reach [nudgeOffset] through [EditorHistory.run] like every other
  /// change, and that needs a name in the sealed hierarchy the same as the
  /// ten before it.
  String? activeStepForOffsets;

  /// What is selected, whatever kind it is, or null.
  Object? get piece => switch (kind) {
    Piece.brush => brush,
    Piece.light => light,
    Piece.entity => entity,
    null => null,
  };

  Brush? get brush => kind != Piece.brush ? null : _at(level.brushes, selected);

  LevelLight? get light =>
      kind != Piece.light ? null : _at(level.lights, selected);

  EntityDef? get entity =>
      kind != Piece.entity ? null : _at(level.entities, selected);

  static T? _at<T>(List<T> list, int? index) =>
      index == null || index < 0 || index >= list.length ? null : list[index];

  /// Where the selected thing is, or null.
  Vector3? get where => switch (piece) {
    final Brush it => it.centre,
    final LevelLight it => it.position,
    final EntityDef it => it.position,
    _ => null,
  };

  /// What to call it on screen.
  String get says => switch (piece) {
    final Brush it => 'brush $selected · ${it.material}',
    final LevelLight it =>
      'light $selected · ${it.type.name} · ${it.intensity.toStringAsFixed(1)}',
    final EntityDef it =>
      'entity $selected · ${it.type}${it.name == null ? '' : ' "${it.name}"'}',
    _ => 'nothing selected — click something',
  };

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

  /// Everything that has been done to this document, and the way back.
  ///
  /// **The stack, what is unsaved and what one command means all live there**,
  /// and this is the only handle on them. An application drives the document
  /// through it — `history.run(const Delete())` rather than `remove()` — because
  /// that is where a name for the step and a transaction around a drag come
  /// from; the methods below stay because they are what a command is made of,
  /// and because a caller with one thing to do should not have to build an
  /// object to do it.
  ///
  /// Built on demand and then kept, so a document that is only ever read never
  /// makes one.
  late final EditorHistory history = EditorHistory(this);

  /// Whether anything has been changed since the last save.
  ///
  /// The history's answer; here because "has this document got unsaved work in
  /// it" is a question about the document, and because the bar that prints it
  /// has an [Editing] in its hand.
  bool get isDirty => history.isDirty;

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

  /// Remembers the document as it stands, before a change [says] describes.
  ///
  /// Every method below that changes anything begins with this, and that is
  /// deliberately the only injection point: a document layer where some edits
  /// were recorded and others were not would be a document layer with an undo
  /// that works most of the time. Inside `EditorHistory.transaction` this costs
  /// nothing — the transaction has already taken its snapshot.
  void _remember(String says) => history.remember(says);

  /// Whether there is anything to go back to.
  bool get canUndo => history.canUndo;

  /// Whether there is anything to go forward to.
  bool get canRedo => history.canRedo;

  /// Puts the document back the way it was before the last change.
  void undo() => history.undo();

  /// Puts back the change [undo] took away.
  void redo() => history.redo();

  /// Picks something, or nothing.
  void select(Piece? kind, int? index) {
    this.kind = kind;
    selected = index;
    if (piece == null) {
      this.kind = null;
      selected = null;
    }
  }

  /// Picks whatever a click found.
  void selectHandle(Handle? handle) => select(handle?.kind, handle?.index);

  /// Moves whatever is selected, snapping it to the grid.
  ///
  /// One method for all three, because a position is a position: the document
  /// keeps a monster's in `at` and a brush's in `at`, and an editor that had a
  /// separate verb per kind would be an editor with three places to get the
  /// grid wrong.
  void nudge(Vector3 by) {
    final at = where;
    if (at == null) return;
    _remember('move');
    at.setValues(_snap(at.x + by.x), _snap(at.y + by.y), _snap(at.z + by.z));
  }

  /// `edu-01`'s "разборка перетаскиванием": adds [by] to whatever
  /// [activeStepForOffsets] already has recorded for the *selected* entity,
  /// and writes the sum back into that step's own `offsets` — [mergedOffsets]
  /// (`lesson_authoring.dart`) does the merge, this does the reading and the
  /// selection round trip `setField` needs to reach a different entity than
  /// the one on screen.
  ///
  /// A no-op — same as [nudge] on nothing selected — when no step is active,
  /// nothing is selected, the selection has no name to key `offsets` by, or
  /// the selection *is* the active step: nudging a step is what [nudge]
  /// already means (the step's own camera position), not a part's offset.
  bool nudgeOffset(Vector3 by) {
    final stepName = activeStepForOffsets;
    final node = entity;
    final nodeName = node?.name;
    if (stepName == null || nodeName == null || nodeName == stepName) {
      return false;
    }
    final stepIndex = indexOfNamed(level, stepName);
    if (stepIndex == null) return false;
    final step = level.entities[stepIndex];
    if (step.type != 'edu_step') return false;

    final current = _offsetOf(step, nodeName) ?? Vector3.zero();
    final merged = mergedOffsets(step, nodeName, current + by);

    final savedKind = kind;
    final savedSelected = selected;
    select(Piece.entity, stepIndex);
    final wrote = setField('offsets', merged);
    select(savedKind, savedSelected);
    return wrote;
  }

  /// [step]'s own recorded offset for [nodePath], or null — the read half of
  /// [mergedOffsets], which only ever writes. Parses the same `[x, y, z]`
  /// shape `flutter3d_bridge`'s own `_offsetVector` reads at playback time;
  /// malformed or absent is null rather than a thrown format error, the
  /// reading side of the same forgiveness `mergedOffsets` already extends to
  /// writing.
  static Vector3? _offsetOf(EntityDef step, String nodePath) {
    final offsets = step.properties['offsets'];
    if (offsets is! Map) return null;
    final raw = offsets[nodePath];
    if (raw is! List || raw.length < 3) return null;
    final x = raw[0];
    final y = raw[1];
    final z = raw[2];
    if (x is! num || y is! num || z is! num) return null;
    return Vector3(x.toDouble(), y.toDouble(), z.toDouble());
  }

  /// Grows or shrinks the selected brush about its own centre.
  ///
  /// Brushes only: a light has no size and a monster's is the game's business.
  /// What the same two keys do to a light is [brighten].
  void grow(Vector3 by) {
    final it = brush;
    if (it == null) return;
    _remember('resize');
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
  void add(Vector3 at, {Vector3? size, String? material}) {
    _remember('add a brush');
    level.brushes.add(
      Brush(
        centre: Vector3(_snap(at.x), _snap(at.y), _snap(at.z)),
        size: size ?? Vector3(2.0, 2.0, 2.0),
        material: material ?? commonestMaterial,
      ),
    );
    kind = Piece.brush;
    selected = level.brushes.length - 1;
  }

  /// Copies whatever is selected, a step to the side, and selects the copy.
  ///
  /// Beside rather than on top: two things in the same place are one thing as
  /// far as anybody can see, and an editor whose duplicate is invisible is an
  /// editor that appears not to have done anything.
  ///
  /// **This is how a level gets a second monster.** The editor has no
  /// vocabulary of its own — it cannot know what a `monster` needs in it, or
  /// which of a lift's twelve properties matter — so it does not invent one.
  /// It copies one that the level already has, with everything it was carrying,
  /// and lets somebody move it. A copy is honest about the things a program
  /// cannot know.
  void duplicate() {
    final it = piece;
    if (it == null) return;
    _remember('duplicate');
    switch (it) {
      case final Brush brush:
        level.brushes.add(
          Brush(
            centre: brush.centre + Vector3(brush.size.x, 0.0, 0.0),
            size: brush.size,
            material: brush.material,
            surface: brush.surface == brush.material ? null : brush.surface,
            solid: brush.solid,
            // The mode rather than the boolean: a copy of a `doubleSided`
            // wall is a wall, and a copy that quietly became an ordinary
            // caster is exactly the kind of thing a duplicate must not do.
            shadowCasting: brush.shadowCasting,
            layer: brush.layer,
            ramp: brush.ramp,
          ),
        );
        selected = level.brushes.length - 1;
      case final LevelLight light:
        level.lights.add(
          LevelLight.fromJson(<String, Object?>{
            ...light.toJson(),
            'at': <double>[
              light.position.x + _step,
              light.position.y,
              light.position.z,
            ],
          }),
        );
        selected = level.lights.length - 1;
      case final EntityDef entity:
        level.entities.add(
          EntityDef.fromJson(<String, Object?>{
            ...entity.toJson(),
            'at': <double>[
              entity.position.x + _step,
              entity.position.y,
              entity.position.z,
            ],
          }),
        );
        selected = level.entities.length - 1;
    }
  }

  /// How far a copy lands from what it was copied from, when the thing has no
  /// size to step by.
  double get _step => grid <= 0.0 ? 1.0 : grid * 4;

  /// Adds a light where somebody is looking.
  ///
  /// **A light the editor may invent, unlike an entity.** A `LevelLight` is a
  /// typed thing the engine defines — a place, a colour, a strength and a
  /// reach — so writing a new one down is not the editor guessing at a game's
  /// vocabulary. What a `monster` needs in it is not knowable here; what a
  /// point light needs is.
  void addLight(Vector3 at, {double intensity = 4.0, double range = 8.0}) {
    _remember('add a light');
    level.lights.add(
      LevelLight(
        position: Vector3(_snap(at.x), _snap(at.y), _snap(at.z)),
        intensity: intensity,
        range: range,
      ),
    );
    kind = Piece.light;
    selected = level.lights.length - 1;
  }

  /// Puts one of [it] at [at], and selects it.
  ///
  /// **An entity is placed by copying one**, for the reason [duplicate] gives:
  /// the editor cannot know what a `monster` needs in it, and a bare one with
  /// the right `type` and nothing else is a monster that may not spawn. The
  /// last one in the document is the model, because the last one placed is
  /// usually the one somebody has just got right. A type with nothing to copy
  /// — which cannot come from a palette, but can come from a caller — is made
  /// bare rather than refused.
  ///
  /// A brush is placed in the material the row names, which is what makes a
  /// palette row mean something: `wall` puts down a wall.
  void place(Placeable it, Vector3 at) {
    final snapped = Vector3(_snap(at.x), _snap(at.y), _snap(at.z));
    switch (it.kind) {
      case Piece.brush:
        add(snapped, material: it.what);
      case Piece.light:
        addLight(snapped);
      case Piece.entity:
        _remember('place a ${it.what}');
        final model = level.entities.lastWhere(
          (EntityDef entity) => entity.type == it.what,
          orElse: () => EntityDef(type: it.what),
        );
        level.entities.add(
          EntityDef.fromJson(<String, Object?>{
            ...model.toJson(),
            'type': it.what,
            'at': <double>[snapped.x, snapped.y, snapped.z],
          }),
        );
        kind = Piece.entity;
        selected = level.entities.length - 1;
    }
  }

  /// Makes the selected light stronger or weaker, by a factor.
  ///
  /// A factor rather than an amount, because light is read that way: the step
  /// from 1 to 2 is the step from 8 to 16, and an editor that added a constant
  /// would be useless at one end and unusable at the other.
  ///
  /// Never quite to nothing: a light of zero is a light that cannot be found
  /// again except by reading the file.
  void brighten(double by) {
    final it = light;
    if (it == null) return;
    _remember('brighten');
    level.lights[selected!] = LevelLight.fromJson(<String, Object?>{
      ...it.toJson(),
      'intensity': double.parse(
        (it.intensity * by).clamp(0.05, 1000.0).toStringAsFixed(3),
      ),
    });
  }

  /// Turns the selected entity about the vertical, in radians.
  ///
  /// Entities only: a brush has no facing in this format, and a light's is its
  /// direction rather than a yaw.
  void turn(double by) {
    final it = entity;
    if (it == null) return;
    _remember('turn');
    final turned = it.yaw + by;
    level.entities[selected!] = EntityDef.fromJson(<String, Object?>{
      ...it.toJson(),
      'yaw': double.parse(turned.toStringAsFixed(4)),
    });
  }

  /// Deletes whatever is selected.
  void remove() {
    final index = selected;
    if (piece == null || index == null) return;
    _remember('delete');
    switch (kind!) {
      case Piece.brush:
        level.brushes.removeAt(index);
      case Piece.light:
        level.lights.removeAt(index);
      case Piece.entity:
        level.entities.removeAt(index);
    }
    kind = null;
    selected = null;
  }

  /// Every field of the selected thing, as the document holds them.
  ///
  /// The document rather than the object, deliberately. `Brush` and
  /// `LevelLight` are immutable value types whose fields are `final`, so there
  /// is nothing to assign to — and both write through a `_source` map, which
  /// means a document can carry a field this build has never heard of and keep
  /// it. Reading the row back gives an editor every field the format has,
  /// including the ones added after it was written.
  ///
  /// Empty when nothing is selected.
  Map<String, Object?> get fields {
    final row = _rowOf(level.toJson());
    return row == null
        ? const <String, Object?>{}
        : Map<String, Object?>.unmodifiable(row);
  }

  /// Fields the format defines for the selected kind that this row omits, at
  /// the value the reader would use for them.
  ///
  /// **Without this the panel edits only what is already written**, and the
  /// gap it exists to close is exactly the other case: a brush is solid and
  /// casts a shadow *by omission*, so a document that has never said otherwise
  /// carries neither key — and a one-way platform or a piece of non-solid
  /// decoration is made by adding one. An inspector built purely from the row
  /// would have shown three fields for the crypt's every wall and offered no
  /// way to reach the two that matter.
  ///
  /// A hand-written list, which is the one place in this design that is: the
  /// format has no schema to ask, and offering a field means knowing its name
  /// and its default. Kept beside [setField] rather than in the panel because
  /// it is a fact about the level format rather than about widgets — and kept
  /// short, because anything a document already carries comes from [fields]
  /// and needs no entry here.
  ///
  /// Entities are deliberately almost empty: everything not reserved *is* a
  /// property there, so the format grows by writing new keys and there is no
  /// finite list to offer.
  Map<String, Object?> get offerable {
    final has = fields;
    if (has.isEmpty) return const <String, Object?>{};
    final all = switch (kind!) {
      Piece.brush => const <String, Object?>{
        'solid': true,
        'castsShadow': true,
        'surface': '',
        'layer': 0,
        'ramp': '+x',
      },
      Piece.light => const <String, Object?>{
        'type': 'point',
        'intensity': 1.0,
        'range': 0.0,
        'color': <double>[1.0, 1.0, 1.0],
        'direction': <double>[0.0, -1.0, 0.0],
        'castsShadow': false,
        'name': '',
      },
      Piece.entity => const <String, Object?>{'name': ''},
    };
    return <String, Object?>{
      for (final entry in all.entries)
        if (!has.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  /// Sets one field of the selected thing, or removes it when [value] is null.
  ///
  /// **This is what the editor was missing**, and the shape of what was missing
  /// is the point: it could move any of the three kinds, resize a brush,
  /// brighten a light and turn an entity, and it could not touch a brush's
  /// material, `solid`, `castsShadow`, `layer` or `ramp`, a light's colour,
  /// range or type, or an entity's properties. Those are the one-way platforms
  /// and the non-solid decoration the level format documents as its point, and
  /// they were unauthorable in the editor that exists to author them.
  ///
  /// Through the document and back rather than field by field, for the same
  /// reason [undo] works that way: a level is a few hundred numbers, and an
  /// editor that reconstructs state is an editor with its own bugs. It also
  /// means this needs no case per field and no case per kind — the day the
  /// format grows a field, this edits it.
  ///
  /// A value that the format cannot read is refused rather than written: it
  /// would be a document that will not load, produced by the tool whose job is
  /// producing documents that will.
  ///
  /// **Copies the list and the row before touching either.** `Level.toJson`
  /// hands back the *original* decoded objects, unchanged, for anything that
  /// still reads the same as when the document was opened
  /// (`writeThrough`'s own diff-minimising rule) — so the list this reads and
  /// the row inside it are, the first time either is touched, the very same
  /// objects an earlier snapshot (a transaction's own, taken on the way in)
  /// is holding onto. Writing into either object in place therefore also
  /// rewrites that snapshot, and an undo restores the document already
  /// carrying the change it was supposed to remove. A fresh list and a fresh
  /// row are cheap next to that.
  bool setField(String key, Object? value) {
    if (piece == null) return false;
    final document = level.toJson();
    final at = selected;
    final listKey = switch (kind!) {
      Piece.brush => 'brushes',
      Piece.light => 'lights',
      Piece.entity => 'entities',
    };
    final rawList = document[listKey];
    if (at == null || rawList is! List || at < 0 || at >= rawList.length) {
      return false;
    }
    final rawRow = rawList[at];
    if (rawRow is! Map<String, Object?>) return false;

    final list = List<Object?>.of(rawList);
    document[listKey] = list;
    final row = Map<String, Object?>.of(rawRow);
    if (value == null) {
      row.remove(key);
    } else {
      row[key] = value;
    }
    list[at] = row;

    final Level rebuilt;
    try {
      rebuilt = Level.fromJson(document);
    } catch (_) {
      // `document`, `list` and `row` are all copies nothing else holds, so
      // there is nothing to put back — the caller's document was never
      // touched.
      return false;
    }

    _remember(value == null ? 'clear $key' : 'set $key');
    level = rebuilt;
    return true;
  }

  /// The selected thing's own row inside [document], or null.
  Map<String, Object?>? _rowOf(Map<String, Object?> document) {
    final at = selected;
    if (at == null || kind == null) return null;
    final list =
        document[switch (kind!) {
          Piece.brush => 'brushes',
          Piece.light => 'lights',
          Piece.entity => 'entities',
        }];
    if (list is! List || at < 0 || at >= list.length) return null;
    final row = list[at];
    return row is Map<String, Object?> ? row : null;
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
  ///
  /// The history's, because what "unsaved" means is where the stack stood when
  /// the file was written — see `EditorHistory.saved`.
  void saved() => history.saved();

  double _snap(double value) =>
      grid <= 0.0 ? value : (value / grid).roundToDouble() * grid;
}
