import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'editor_history.dart';
import 'gizmos.dart';
import 'palette_items.dart';

/// Where the ids of rows a person adds come from: unseeded, since nothing
/// replays an edit, and a level's ids only have to differ from each other.
final math.Random _ids = math.Random();

/// One selected thing: which of the level's three lists, and which one in it.
///
/// What [Editing.kind] and [Editing.selected] hold for the primary, as one
/// value, so a selection of several can be a list of them.
typedef Picked = ({Piece kind, int index});

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
  /// **Held as the thing's id** ([Brush.id], [LevelLight.id],
  /// [EntityDef.id]), and answered as an index into the list as it stands
  /// now. Not the object itself, because the list is what gets edited and a
  /// reference into a list that undo has just replaced is a reference to
  /// something no longer in the document; not the index alone, because an
  /// index names whatever moved into the place — after an undo that put a
  /// row back before it, after a reorder — and an id names the same thing
  /// for as long as it is there. Something whose id is gone is no longer
  /// selected.
  ///
  /// **A kind as well as an index, because a level is three lists.** The first
  /// version of this could only hold a brush, which meant an editor that could
  /// not touch a light, a monster, a lift or the point the player starts at —
  /// most of what a level *is* once its walls are up.
  ///
  /// **The primary selection, with others beside it.** An outliner row
  /// command-clicked adds to what is selected rather than replacing it, and
  /// [also] is where those others are kept. Assigning either of these two
  /// drops them: every method below that selects what it just made — [add],
  /// [place], [duplicate] — means "this one, now", and a selection that kept
  /// three unrelated walls beside a brush that was just added would move
  /// them all on the next arrow key.
  Piece? get kind => _kind;
  set kind(Piece? value) {
    _kind = value;
    _also.clear();
  }

  int? get selected {
    final primary = _kind;
    final id = _selectedId;
    return primary == null || id == null ? null : _indexOf(primary, id);
  }

  set selected(int? value) {
    final primary = _kind;
    _selectedId = primary == null || value == null
        ? null
        : idOf((kind: primary, index: value));
    _also.clear();
  }

  /// The primary selection's id, or null when nothing is selected.
  String? get selectedId => selected == null ? null : _selectedId;

  /// Picks the [kind] whose id is [id], or nothing when there is none.
  ///
  /// For a tool that names a row by its stable id rather than by where it
  /// happens to sit in the list: an agent through the editor's MCP server, a
  /// plugin's editor tool.
  void selectId(Piece kind, String id) => select(kind, _indexOf(kind, id));

  Piece? _kind;
  String? _selectedId;

  /// What is selected beside the primary, in the order it was added, by id.
  final List<({Piece kind, String id})> _also = <({Piece kind, String id})>[];

  /// The id of [it] in the document as it stands, or null when there is no
  /// such row.
  String? idOf(Picked it) => !_exists(it)
      ? null
      : switch (it.kind) {
          Piece.brush => level.brushes[it.index].id,
          Piece.light => level.lights[it.index].id,
          Piece.entity => level.entities[it.index].id,
        };

  int? _indexOf(Piece kind, String id) {
    final at = switch (kind) {
      Piece.brush => level.brushes.indexWhere((Brush b) => b.id == id),
      Piece.light => level.lights.indexWhere((LevelLight l) => l.id == id),
      Piece.entity => level.entities.indexWhere((EntityDef e) => e.id == id),
    };
    return at < 0 ? null : at;
  }

  /// Everything selected: the primary first, then the others.
  ///
  /// **Read against the document every time**: undo puts a whole document
  /// back, and an id that is no longer in it names nothing. One that does
  /// not is dropped here rather than remembered, so a stale entry can never
  /// be moved or deleted.
  List<Picked> get selection {
    final primary = _kind;
    final at = selected;
    if (primary == null || at == null || piece == null) {
      return const <Picked>[];
    }
    return <Picked>[
      (kind: primary, index: at),
      for (final it in _also)
        if (_indexOf(it.kind, it.id) case final int index
            when !(it.kind == primary && index == at))
          (kind: it.kind, index: index),
    ];
  }

  /// Whether [kind] number [index] is part of [selection].
  bool isSelected(Piece kind, int index) =>
      selection.any((Picked it) => it.kind == kind && it.index == index);

  /// Adds [kind] number [index] to the selection, or takes it out when it is
  /// already there — what a command-click on an outliner row does.
  ///
  /// Taking out the primary promotes the next one, so what the inspector
  /// shows is always something still selected. Adding to an empty selection
  /// makes it the primary.
  void toggle(Piece kind, int index) {
    final picked = (kind: kind, index: index);
    if (!_exists(picked)) return;
    final now = selection;
    if (now.isEmpty) {
      select(kind, index);
      return;
    }
    if (isSelected(kind, index)) {
      final rest = <Picked>[
        for (final it in now)
          if (!(it.kind == kind && it.index == index)) it,
      ];
      select(rest.firstOrNull?.kind, rest.firstOrNull?.index);
      _also.addAll(<({Piece kind, String id})>[
        for (final it in rest.skip(1))
          if (idOf(it) case final String id) (kind: it.kind, id: id),
      ]);
      return;
    }
    _also
      ..removeWhere(
        (({Piece kind, String id}) it) => _indexOf(it.kind, it.id) == null,
      )
      ..add((kind: kind, id: idOf(picked)!));
  }

  bool _exists(Picked it) =>
      it.index >= 0 &&
      it.index <
          switch (it.kind) {
            Piece.brush => level.brushes.length,
            Piece.light => level.lights.length,
            Piece.entity => level.entities.length,
          };

  /// Where [it] is in the document, or null when it is not there.
  Vector3? whereOf(Picked it) => !_exists(it)
      ? null
      : switch (it.kind) {
          Piece.brush => level.brushes[it.index].center,
          Piece.light => level.lights[it.index].position,
          Piece.entity => level.entities[it.index].position,
        };

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
    final Brush it => it.center,
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
  bool get canOverwrite => generatedBy == null;

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
  /// and impossible to get back. In metres, along each side.
  static const double minimumSize = 0.25;

  /// Remembers the document as it stands, before a change [says] describes.
  ///
  /// Every method below that changes anything begins with this, and that is
  /// deliberately the only injection point: a document layer where some edits
  /// were recorded and others were not would be a document layer with an undo
  /// that works most of the time. Inside `EditorHistory.transaction` this costs
  /// nothing — the transaction has already taken its snapshot.
  void _remember(String says) => history.remember(says);

  /// Puts [next] where the level was, as one step of undo [says] names —
  /// a level made whole by a generator, which an author then edits like any
  /// other. The selection goes: what it pointed at is not there.
  void replaceLevel(Level next, {required String says}) {
    _remember(says);
    level = next;
    select(null, null);
  }

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

  /// Moves everything in [selection] by [by], as one change.
  ///
  /// [nudge] for each of them, so each lands on the grid the way one moved
  /// alone would; one step of undo, because `MoveSelectionBy` runs inside the
  /// history's transaction and that is what takes the snapshot.
  void nudgeAll(Vector3 by) {
    final all = selection;
    if (all.isEmpty) return;
    _remember('move');
    for (final it in all) {
      final at = whereOf(it);
      if (at == null) continue;
      at.setValues(_snap(at.x + by.x), _snap(at.y + by.y), _snap(at.z + by.z));
    }
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
        id: LevelIds.fresh(_ids),
        center: Vector3(_snap(at.x), _snap(at.y), _snap(at.z)),
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
            id: LevelIds.fresh(_ids),
            center: brush.center + Vector3(brush.size.x, 0.0, 0.0),
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
            drawOrder: brush.drawOrder,
            depthLayer: brush.depthLayer,
          ),
        );
        selected = level.brushes.length - 1;
      case final LevelLight light:
        level.lights.add(
          LevelLight.fromJson(<String, Object?>{
            ...light.toJson(),
            // A copy is a thing of its own, so it has an id of its own.
            'id': LevelIds.fresh(_ids),
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
            'id': LevelIds.fresh(_ids),
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

  /// Adds [recipe] to the document and answers what it builds, on its own.
  ///
  /// **The recipe goes in, not what it expands to.** A room written as its
  /// recipe stays one line that a seed and a size decide, and the level is
  /// expanded wherever it is used — loaded, validated, baked — so the brushes
  /// in the answer are the brushes a player gets.
  ///
  /// Expanded once before it is added, so a recipe no kit can build throws the
  /// kit's own [LevelFormatException] and leaves the document as it was,
  /// rather than being written into a document that then fails to validate.
  Level addRecipe(LevelRecipe recipe) {
    final alone = expandRecipes(
      Level(name: level.name, recipes: <LevelRecipe>[recipe]),
    );
    _remember('generate a ${recipe.kind} from seed ${recipe.seed}');
    level.recipes.add(recipe);
    return alone;
  }

  /// The leaf and consideration kinds a behaviour tree is read against: the
  /// standard ones unless the game the level is for says which it has.
  BehaviorKinds behaviorKinds = BehaviorKinds();

  /// Writes [document] as the behaviour tree called [name], in place of any
  /// tree of that name, and says what is wrong with it — nothing, when it was
  /// written.
  ///
  /// **Refused with every problem rather than written**, the rule
  /// [setField] keeps: a tree that does not read is a level that does not
  /// load in the game, and the place to hear about it is here, with the path
  /// to each problem, not at the first tick.
  List<String> setBehavior(String name, Map<String, Object?> document) {
    if (name.isEmpty) return <String>['a behaviour needs a name'];
    final problems = BehaviorTree.read(document, behaviorKinds).problems;
    if (problems.isNotEmpty) return problems;
    _remember('set behaviour $name');
    level.behaviors[name] = document;
    return const <String>[];
  }

  /// The step rate a cutscene's moments are read for: the game's, sixty
  /// unless the game the level is for says otherwise.
  int cutsceneStepsPerSecond = 60;

  /// The level's cutscenes, by name: the `cutscene` entities and their
  /// `sequence` documents.
  Map<String, Map<String, Object?>> get cutscenes =>
      <String, Map<String, Object?>>{
        for (final entity in level.ofType(EntityTypes.cutscene))
          if ((entity.name, entity.properties['sequence']) case (
            final String name,
            final Map<Object?, Object?> document,
          ))
            name: document.cast<String, Object?>(),
      };

  /// Writes [sequence] as the cutscene called [name] — the `sequence` of the
  /// `cutscene` entity of that name, made at [at] when there is none yet —
  /// and says what is wrong with it: nothing, when it was written.
  ///
  /// Refused, with every problem and where it is, as [setBehavior] is: the
  /// document is read as the game will read it, at
  /// [cutsceneStepsPerSecond], and a name another entity already answers
  /// to is refused rather than given twice.
  List<String> setCutscene(
    String name,
    Map<String, Object?> sequence, {
    Vector3? at,
  }) {
    if (name.isEmpty) return <String>['a cutscene needs a name'];
    final problems = Sequence.read(
      sequence,
      stepsPerSecond: cutsceneStepsPerSecond,
    ).problems;
    if (problems.isNotEmpty) return problems;
    final index = level.entities.indexWhere(
      (EntityDef e) => e.type == EntityTypes.cutscene && e.name == name,
    );
    if (index < 0 && level.named(name) != null) {
      return <String>['"$name" is already the name of something else'];
    }
    _remember('set cutscene $name');
    final old = index < 0 ? null : level.entities[index];
    final entity = EntityDef(
      type: EntityTypes.cutscene,
      id: old?.id ?? LevelIds.fresh(_ids),
      name: name,
      position: old?.position ?? at ?? Vector3.zero(),
      yaw: old?.yaw ?? 0.0,
      properties: <String, Object?>{...?old?.properties, 'sequence': sequence},
    );
    if (index < 0) {
      level.entities.add(entity);
    } else {
      level.entities[index] = entity;
    }
    return const <String>[];
  }

  /// Takes the cutscene called [name] out, and says whether there was one.
  /// A trigger that started it is left naming it, which the validator
  /// reports.
  bool removeCutscene(String name) {
    final index = level.entities.indexWhere(
      (EntityDef e) => e.type == EntityTypes.cutscene && e.name == name,
    );
    if (index < 0) return false;
    _remember('remove cutscene $name');
    level.entities.removeAt(index);
    // An entity selected by its index may now be the next one along.
    if (piece == Piece.entity) select(null, null);
    return true;
  }

  /// Takes the behaviour tree called [name] out, and says whether there was
  /// one. An entity that ran it is left naming it, which `BehaviorsRead`
  /// reports: the editor does not guess which tree it should run instead.
  bool removeBehavior(String name) {
    if (!level.behaviors.containsKey(name)) return false;
    _remember('remove behaviour $name');
    level.behaviors.remove(name);
    return true;
  }

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
        id: LevelIds.fresh(_ids),
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
          EntityDef(
            type: it.what,
            id: LevelIds.fresh(_ids),
            position: snapped,
            yaw: model.yaw,
            name: model.name,
            // A plugin's palette entry says what a new one starts with; the
            // last one of its type in the level, when there is one, wins.
            properties: <String, Object?>{
              ...it.properties,
              ...model.properties,
            },
            components: model.components,
          ),
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

  /// Puts [lights] where the level's lights were, all at once.
  ///
  /// One change rather than a delete and an add per light, because what
  /// produces a whole set — the light optimizer — made one decision about all
  /// of them, and one undo is what puts that decision back. A light selected
  /// before is selected no longer: the index it had now names another light,
  /// or none.
  void setLights(List<LevelLight> lights) {
    _remember('set the lights');
    level.lights
      ..clear()
      ..addAll(lights);
    if (kind == Piece.light) {
      kind = null;
      selected = null;
    }
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

  /// Deletes everything in [selection].
  ///
  /// Highest index first within each list, so taking one out does not move
  /// the next one to a different number before its turn comes.
  void removeAll() {
    final all = selection;
    if (all.isEmpty) return;
    _remember('delete');
    final ordered = List<Picked>.of(all)
      ..sort((Picked a, Picked b) => b.index.compareTo(a.index));
    for (final it in ordered) {
      switch (it.kind) {
        case Piece.brush:
          level.brushes.removeAt(it.index);
        case Piece.light:
          level.lights.removeAt(it.index);
        case Piece.entity:
          level.entities.removeAt(it.index);
      }
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
  ///
  /// **An entity's properties are listed beside its own keys**, as they were
  /// before level format 3 moved them under `props` in the document: to the
  /// person editing it a monster's `health` is a field like its `name`.
  /// [setField] puts each back where it belongs. The `id` is not a field:
  /// it is what everything else finds the row by, and is not edited.
  Map<String, Object?> get fields {
    final row = _rowOf(level.toJson());
    if (row == null) return const <String, Object?>{};
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final MapEntry(:key, :value) in row.entries)
        if (key != 'id' && !(kind == Piece.entity && key == 'props'))
          key: value,
      if (kind == Piece.entity)
        if (row['props'] case final Map<String, Object?> props) ...props,
    });
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
        'drawOrder': 0,
        // Unset means the material's layer; offered at the layer everything
        // is on, so setting it is one number away.
        'depthLayer': 0,
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
  bool setField(String key, Object? value) {
    if (piece == null || key == 'id') return false;
    final document = _detached(level.toJson());
    final row = _rowOf(document);
    if (row == null) return false;

    final before = Map<String, Object?>.from(row);
    // An entity's property lives under `props`; its own keys at the top.
    final target = kind == Piece.entity && !EntityDef.reservedKeys.contains(key)
        ? (row['props'] = <String, Object?>{
            ...?row['props'] as Map<String, Object?>?,
          })
        : row;
    if (value == null) {
      target.remove(key);
    } else {
      target[key] = value;
    }

    final Level rebuilt;
    try {
      rebuilt = Level.fromJson(document);
    } catch (_) {
      // Put the row back so the caller's document is untouched, and say no.
      row
        ..clear()
        ..addAll(before);
      return false;
    }

    _remember(value == null ? 'clear $key' : 'set $key');
    level = rebuilt;
    return true;
  }

  /// [document] with the selected thing's list and row copied, so editing
  /// the row edits nothing else.
  ///
  /// **The undo of every inspector edit depended on this, and it was
  /// missing.** `Level.toJson` writes through what it read, and hands back
  /// the very list and row maps it was read from wherever nothing changed —
  /// the same objects on every call. The history's snapshot, taken a moment
  /// before, held those same maps; [setField] wrote the new value into the
  /// row, and so into the snapshot, and undo put back a document that
  /// already had the change in it.
  Map<String, Object?> _detached(Map<String, Object?> document) {
    final name = switch (kind) {
      Piece.brush => 'brushes',
      Piece.light => 'lights',
      Piece.entity => 'entities',
      null => null,
    };
    final list = document[name];
    final at = selected;
    if (name == null || list is! List || at == null) return document;
    return <String, Object?>{
      ...document,
      name: <Object?>[
        for (final (index, row) in list.indexed)
          index == at && row is Map<String, Object?>
              ? Map<String, Object?>.of(row)
              : row,
      ],
    };
  }

  /// The selected thing's own row inside [document], or null.
  ///
  /// Live rather than a copy: [setField] edits it in place and hands the whole
  /// document back to `Level.fromJson`.
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

  // MARK: - Prefabs

  /// The selected entity as a prefab instance, or null when it is not one.
  PrefabInstance? get instance {
    final it = entity;
    if (it == null) return null;
    try {
      return PrefabInstance.of(it);
    } on LevelFormatException {
      return null;
    }
  }

  /// The document as plain JSON nobody else holds, to change and read back.
  ///
  /// A deep copy, for the reason [_detached] gives: `Level.toJson` hands back
  /// the maps it was read from, and the history's snapshot holds the same
  /// ones, so writing into them would write into the step undo puts back.
  Map<String, Object?> _copy() =>
      jsonDecode(jsonEncode(level.toJson())) as Map<String, Object?>;

  /// Puts [document] in place of the level as one step [says] names, or
  /// answers false and changes nothing when it is not a level that expands —
  /// a prefab that would contain itself, an instance of one that is not
  /// there, an override of a key no override may touch.
  bool _commitPrefabs(Map<String, Object?> document, String says) {
    final Level next;
    try {
      next = Level.fromJson(document);
      expandPrefabs(next);
    } on LevelFormatException {
      return false;
    }
    _remember(says);
    level = next;
    return true;
  }

  /// Turns the selected entities into the prefab [id], and puts one instance
  /// of it where they were.
  ///
  /// The primary selection's place is the prefab's origin, so the instance
  /// lands where the thing somebody clicked first was and everything else
  /// keeps its place around it. An instance among the selection goes into
  /// the template as an instance — a nested prefab. False, having changed
  /// nothing, for an empty or taken [id] or a selection with no entity in it.
  bool createPrefab(String id) {
    final picked = <int>[
      for (final it in selection)
        if (it.kind == Piece.entity) it.index,
    ];
    if (id.isEmpty || level.prefabs.containsKey(id) || picked.isEmpty) {
      return false;
    }
    final origin = level.entities[picked.first].position.clone();
    final document = _copy();
    final rows = (document['entities']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final template = <Object?>[
      for (final index in picked)
        <String, Object?>{
          ...rows[index],
          'at': (level.entities[index].position - origin).toJson(),
        },
    ];
    final first = picked.reduce(math.min);
    final kept = <Map<String, Object?>>[
      for (final (index, row) in rows.indexed)
        if (!picked.contains(index)) row,
    ];
    final at = math.min(first, kept.length);
    document['entities'] = <Object?>[
      ...kept.take(at),
      PrefabInstance.create(id, at: origin).toJson(),
      ...kept.skip(at),
    ];
    document['prefabs'] = <String, Object?>{
      ...?document['prefabs'] as Map<String, Object?>?,
      id: <String, Object?>{'entities': template},
    };
    if (!_commitPrefabs(document, 'make prefab $id')) return false;
    select(Piece.entity, at);
    return true;
  }

  /// Puts an instance of the prefab [id] at [at], and selects it.
  bool placePrefab(String id, Vector3 at, {String? name, double yaw = 0.0}) {
    if (!level.prefabs.containsKey(id)) return false;
    if (name != null && level.named(name) != null) return false;
    final document = _copy();
    document['entities'] = <Object?>[
      ...?document['entities'] as List<Object?>?,
      PrefabInstance.create(
        id,
        at: Vector3(_snap(at.x), _snap(at.y), _snap(at.z)),
        yaw: yaw,
        name: name,
      ).toJson(),
    ];
    if (!_commitPrefabs(document, 'place prefab $id')) return false;
    select(Piece.entity, level.entities.length - 1);
    return true;
  }

  /// The selected instance's row inside [document], or null.
  Map<String, Object?>? _instanceRow(Map<String, Object?> document) =>
      instance == null ? null : _rowOf(document);

  /// The overrides [row] carries under its `props`, as a fresh map to change.
  static Map<String, Map<String, Object?>> _overridesOf(
    Map<String, Object?> row,
  ) => <String, Map<String, Object?>>{
    for (final MapEntry(:key, :value) in PrefabInstance.readOverrides(
      EntityDef.fromJson(row).properties,
    ).entries)
      key: <String, Object?>{...value},
  };

  /// Writes [overrides] into [row]'s `props`, the place format 3 keeps them,
  /// moving a row in the older shape into that one first.
  static void _putOverrides(
    Map<String, Object?> row,
    Map<String, Map<String, Object?>> overrides,
  ) {
    overrides.removeWhere(
      (String _, Map<String, Object?> keys) => keys.isEmpty,
    );
    final shaped = EntityDef.fromJson(row).toJson();
    final props = <String, Object?>{
      ...?shaped['props'] as Map<String, Object?>?,
    };
    if (overrides.isEmpty) {
      props.remove('overrides');
    } else {
      props['overrides'] = overrides;
    }
    row
      ..clear()
      ..addAll(shaped)
      ..['props'] = props;
  }

  /// [path] inside prefab [prefab] as the id path the document keeps.
  ///
  /// **A person may type names**: each segment is an entity's id, or its
  /// name or `#<index>` in the prefab it walks through, which is looked up
  /// and written as the id. So `top/bulb` from an agent that read the
  /// prefab listing lands on the same override as the ids would.
  String _idPath(String prefab, String path) => legacyOverridesToIds(
    <String, Map<String, Object?>>{path: const <String, Object?>{}},
    prefab,
    level.prefabs,
  ).keys.single;

  /// Makes the selected instance's [key] of the entity at [path] say
  /// [value] — null takes the key away in this instance only.
  ///
  /// [path] is ids joined by `/`; a segment may also be a name, see
  /// [_idPath].
  bool setOverride(String path, String key, Object? value) {
    final document = _copy();
    final row = _instanceRow(document);
    final picked = instance;
    if (row == null || picked == null || path.isEmpty || key.isEmpty) {
      return false;
    }
    final overrides = _overridesOf(row);
    (overrides[_idPath(picked.prefab, path)] ??= <String, Object?>{})[key] =
        value;
    _putOverrides(row, overrides);
    return _commitPrefabs(document, 'override $path $key');
  }

  /// Drops the selected instance's overrides — all of them, those of the
  /// entity at [path], or the one [key] there — so it shows its template
  /// again.
  bool revertOverrides({String? path, String? key}) {
    final document = _copy();
    final row = _instanceRow(document);
    final picked = instance;
    if (row == null || picked == null) return false;
    final overrides = _overridesOf(row);
    if (overrides.isEmpty) return false;
    final at = path == null ? null : _idPath(picked.prefab, path);
    if (at == null) {
      overrides.clear();
    } else if (key == null) {
      if (overrides.remove(at) == null) return false;
    } else {
      final keys = overrides[at];
      if (keys == null || !keys.containsKey(key)) return false;
      keys.remove(key);
    }
    _putOverrides(row, overrides);
    return _commitPrefabs(document, 'revert ${path ?? 'overrides'}');
  }

  /// Writes the selected instance's overrides — all of them, or those of the
  /// entity at [path] — into its prefab, and drops them from the instance.
  ///
  /// **Every instance of the prefab changes**, which is the point: one torch
  /// got right in place becomes how every torch is. An override that reaches
  /// into a nested instance is written into that instance's own overrides in
  /// the template, so the nested prefab itself is untouched and the change
  /// stays where it was made.
  bool applyOverrides({String? path}) {
    final picked = instance;
    if (picked == null) return false;
    final at = path == null ? null : _idPath(picked.prefab, path);
    final applied = <String, Map<String, Object?>>{
      for (final MapEntry(:key, :value) in picked.overrides.entries)
        if (at == null || key == at) key: value,
    };
    if (applied.isEmpty) return false;
    final document = _copy();
    final prefab =
        (document['prefabs']! as Map<String, Object?>)[picked.prefab]!
            as Map<String, Object?>;
    final rows = <Map<String, Object?>>[
      ...?(prefab['entities'] as List<Object?>?)?.cast<Map<String, Object?>>(),
    ];
    final segments = <String>[
      for (final row in rows) prefabSegment(EntityDef.fromJson(row)),
    ];
    for (final MapEntry(key: target, value: keys) in applied.entries) {
      final slash = target.indexOf('/');
      final head = slash < 0 ? target : target.substring(0, slash);
      final at = segments.indexOf(head);
      if (at < 0) return false;
      if (slash < 0) {
        try {
          rows[at] = applyPrefabOverride(rows[at], keys);
        } on LevelFormatException {
          return false;
        }
        continue;
      }
      final nested = <String, Object?>{...rows[at]};
      final inner = _overridesOf(nested);
      final rest = target.substring(slash + 1);
      inner[rest] = <String, Object?>{
        for (final MapEntry(key: k, value: v)
            in (inner[rest] ?? const {}).entries)
          if (!keys.containsKey(k)) k: v,
        ...keys,
      };
      _putOverrides(nested, inner);
      rows[at] = nested;
    }
    prefab['entities'] = rows;
    final row = _rowOf(document)!;
    final left = _overridesOf(row)
      ..removeWhere((String key, _) => applied.containsKey(key));
    _putOverrides(row, left);
    return _commitPrefabs(document, 'apply overrides to ${picked.prefab}');
  }

  /// Breaks the selected instance's link: the entities it stands for take
  /// its place in the level as entities of their own, and a later edit of
  /// the prefab no longer reaches them.
  ///
  /// One level only. A nested instance comes out as an instance, still
  /// linked to its own prefab and carrying the overrides that reached it,
  /// so unpacking a building does not also unpack every lamp in it.
  bool unpackPrefab() {
    final picked = instance;
    final index = selected;
    if (picked == null || index == null) return false;
    final List<EntityDef> rows;
    try {
      rows = expandPrefabInstance(picked, level.prefabs, deep: false);
    } on LevelFormatException {
      return false;
    }
    final document = _copy();
    final entities = document['entities']! as List<Object?>;
    // Things of their own now, so ids of their own: the path ids an
    // expansion gives them name a place in a prefab that is no longer there.
    entities.replaceRange(index, index + 1, <Object?>[
      for (final row in rows) row.withId(LevelIds.fresh(_ids)).toJson(),
    ]);
    if (!_commitPrefabs(document, 'unpack ${picked.prefab}')) return false;
    if (rows.isEmpty) {
      select(null, null);
    } else {
      select(Piece.entity, index);
      for (var i = 1; i < rows.length; i++) {
        toggle(Piece.entity, index + i);
      }
    }
    return true;
  }

  /// Writes [key] of the entity at [path] in the prefab [id]'s template — the
  /// entity's id — or takes it away when [value] is null. A key that is not
  /// one of the row's own ([EntityDef.reservedKeys]) is a property.
  ///
  /// **The edit every instance sees**, the next time the level is expanded;
  /// an instance that overrides the same key keeps its own value. Refused,
  /// having changed nothing, when it would make the prefab contain itself or
  /// leave a row the format cannot read.
  bool setPrefabField(String id, String path, String key, Object? value) {
    if (key.isEmpty) return false;
    final document = _copy();
    final prefab = switch (document['prefabs']) {
      final Map<String, Object?> all => all[id],
      _ => null,
    };
    if (prefab is! Map<String, Object?>) return false;
    final rows = <Map<String, Object?>>[
      ...?(prefab['entities'] as List<Object?>?)?.cast<Map<String, Object?>>(),
    ];
    final at = <String>[
      for (final row in rows) prefabSegment(EntityDef.fromJson(row)),
    ].indexOf(_idPath(id, path));
    if (at < 0 || key == 'id') return false;
    final row = EntityDef.fromJson(rows[at]).toJson();
    final target = EntityDef.reservedKeys.contains(key)
        ? row
        : (row['props'] = <String, Object?>{
            ...?row['props'] as Map<String, Object?>?,
          });
    if (value == null) {
      target.remove(key);
    } else {
      target[key] = value;
    }
    rows[at] = row;
    prefab['entities'] = rows;
    return _commitPrefabs(document, 'set $key of $path in $id');
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
  List<LevelIssue> issuesFor(EntityRegistry registry) => LevelValidator(
    registry: registry,
    rules: <LevelRule>[BehaviorsRead(behaviorKinds)],
  ).validate(level);

  /// The document as text, ready to be written.
  ///
  /// Indented, because these files are read by people and compared by `git
  /// diff` — the generators write them that way, and an editor that collapsed
  /// one onto a single line would turn a two-line change into a whole-file one.
  ///
  /// [claiming] takes ownership: `generatedBy` becomes this editor's name
  /// rather than the tool's. **A copy of a generated document has to claim
  /// it**, and this is the other half of [canOverwrite]: a file saved beside
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
