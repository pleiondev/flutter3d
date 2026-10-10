import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'editing.dart';
import 'gizmos.dart';
import 'palette_items.dart';

/// One thing somebody can do to a document, as a value rather than as a call.
///
/// **Why an object at all, when [Editing] already has the methods.** A method
/// can be called and nothing else. A command can be named, listed, written
/// down, sent over a socket and read back — which is what a tool server needs
/// before it can offer anything: [editorCommandNames] is the list it builds a
/// table of tools from, and [arguments] is what one call carries. None of that
/// is reachable from a `void nudge(Vector3)` however well written it is.
///
/// **Nothing here reverses itself, and that is a decision rather than a gap.**
/// The obvious shape for a command is a pair — do it, and undo it — and this
/// hierarchy deliberately does not have the second half. Going back is
/// implemented once, in [EditorHistory], by putting a snapshot of the whole
/// document back; the reason is the one `editing.dart` had already written down
/// when the only mechanism was a stack of snapshots: *an undo that reconstructs
/// state is an undo with its own bugs*. A level is a few hundred numbers, and a
/// snapshot of it is cheap. An inverse per command is ten more places where the
/// way back can disagree with the way there — and the disagreement does not
/// show up as a crash, it shows up as somebody's brush a quarter of a metre
/// from where they left it, three undos later, with nothing to blame.
///
/// So a command is a one-way thing: it changes the document, and the history
/// remembers what the document was. Somebody who reads a plan that says
/// "commands carry their own inverse" and finds none here has found this
/// paragraph rather than an oversight.
///
/// **Two families.** The editor's own commands are [EditorCommand], sealed: a
/// `switch` over them is exhaustive, and the day another arrives the compiler
/// names every place that has to grow. A plugin's are [PluginCommand], open,
/// registered by name with `EditorPieces.addCommand` and read back through
/// `EditorPieces.readCommand`. A `switch` over a [DocumentCommand] has the two
/// cases, `EditorCommand()` and `PluginCommand()`, and is exhaustive too.
///
/// Everything else — [EditorHistory.run], a step of undo named by [says] — takes
/// either family alike.
sealed class DocumentCommand {
  const DocumentCommand();

  /// What this is called on the wire, and in a list of tools.
  ///
  /// One word in lower camel case, matching the method it stands for, so a
  /// person reading a log of what an agent did reads verbs rather than numbers.
  String get name;

  /// What it does, read as a sentence, with the numbers in it: what a status
  /// bar prints and what a step of undo is called.
  String get says;

  /// Everything this carries except its [name].
  Map<String, Object?> get arguments;

  /// Does it, to [editing]. False, having changed nothing, when it cannot —
  /// see [EditorCommand.apply].
  bool apply(Editing editing);

  /// This command as a map, ready for `jsonEncode`: [name] under `command`,
  /// then [arguments].
  Map<String, Object?> toJson() => <String, Object?>{
    'command': name,
    ...arguments,
  };
}

/// A command a plugin brings: one thing somebody can do to a document that the
/// editor itself does not know.
///
/// **Extended outside this package**, where [EditorCommand] cannot be. A plugin
/// writes one subclass per command and registers a reader for its [name] with
/// `EditorPieces.addCommand`, so a tool server, a script or a recorded session
/// reads it back from JSON the way it reads a built-in one. Like every command
/// here it does not reverse itself: [EditorHistory] keeps the document it
/// changed.
///
/// **Its [name] is the published one, `<pluginId>.<name>`**: the reader is
/// registered as `addCommand('sink', …)` and `EditorPieces` files it under the
/// plugin's id, so the command writes `boats.sink` under `command`, and that
/// is what reads it back.
///
/// `base`, so a member added here in a 1.x release arrives with a body.
abstract base class PluginCommand extends DocumentCommand {
  const PluginCommand();
}

/// One of the editor's own commands — the ones [editorCommandNames] lists.
///
/// Sealed, in the shape the rest of the repository uses for a closed set: a
/// `switch` over the kinds is exhaustive, and the day a twelfth arrives the
/// compiler names every place that has to grow. A plugin's commands are
/// [PluginCommand]s instead, so opening the editor left this switch closed.
sealed class EditorCommand extends DocumentCommand {
  const EditorCommand();

  /// What this is called on the wire, and in a list of tools.
  ///
  /// One word in lower camel case, matching the method it stands for, so a
  /// person reading a log of what an agent did reads verbs rather than numbers.
  @override
  String get name;

  /// What it does, read as a sentence.
  ///
  /// The same job [Editing.says] does for the selection: something a status bar
  /// can print and a history can label a step with. With the numbers in it,
  /// because "move" and "move by 0.25, 0, 0" answer different questions when
  /// somebody is looking for the step they want to go back past.
  @override
  String get says;

  /// Everything this carries except its [name].
  ///
  /// Split out so one place writes the discriminator — see [toJson] — and so a
  /// caller that already knows which command it is holding can read the
  /// arguments without having to look past the name it just wrote.
  @override
  Map<String, Object?> get arguments;

  /// Does it, to [editing].
  ///
  /// **False rather than a throw**, the way [Editing.setField] already answers a
  /// value the format cannot read. A command arrives from a keystroke, a click
  /// or a socket, and every one of those can name a thing that is not selected:
  /// resizing with a light picked, turning with nothing picked at all. That is a
  /// question with an answer — no — rather than an error, and a caller that has
  /// to catch one to find out is a caller that will eventually catch it in the
  /// wrong place.
  ///
  /// A command that answers false has changed nothing.
  @override
  bool apply(Editing editing);

  /// This command as a map, ready for `jsonEncode`.
  @override
  Map<String, Object?> toJson() => super.toJson();

  /// Reads one back, or null when it cannot.
  ///
  /// **Null rather than a throw, for the same reason [apply] answers false.**
  /// What is being read here is JSON somebody else wrote — a tool call from an
  /// agent, a script, a recorded session — and "I do not know that command" and
  /// "that command's arguments are not the shape I need" are answers a server
  /// hands back to its caller, not failures of the editor. A missing or
  /// unreadable argument refuses the whole command rather than defaulting it:
  /// a `moveBy` with an unreadable `by` that quietly moved nothing would look
  /// exactly like a `moveBy` that ran.
  ///
  /// The two arguments that do have defaults are a new light's [AddLevelLight]
  /// strength and reach, because the method they stand for has them too.
  static EditorCommand? fromJson(Map<String, Object?> json) {
    final at = _vector(json['at']);
    final by = _vector(json['by']);
    final amount = _number(json['by']);
    final key = _text(json['key']);
    final what = _text(json['what']);
    final kind = _kind(json['kind']);
    return switch (json['command']) {
      'moveBy' when by != null => MoveSelectionBy(by),
      'resize' when by != null => Resize(by),
      'addBrush' when at != null => AddBrush(
        at,
        size: _vector(json['size']),
        material: _text(json['material']),
      ),
      'addLight' when at != null => AddLevelLight(
        at,
        intensity: _number(json['intensity']) ?? 4.0,
        range: _number(json['range']) ?? 8.0,
      ),
      'place' when at != null && kind != null && what != null => Place(
        kind,
        what,
        at,
        properties: switch (json['properties']) {
          final Map<String, Object?> given => given,
          _ => const <String, Object?>{},
        },
      ),
      'duplicate' => const Duplicate(),
      'delete' => const Delete(),
      'setField' when key != null => SetField(key, json['value']),
      'brighten' when amount != null => Brighten(amount),
      'turn' when amount != null => Turn(amount),
      'setLights' => SetLights.fromArguments(json),
      'createPrefab' => switch (_text(json['prefab'])) {
        final String id => CreatePrefab(id),
        null => null,
      },
      'placePrefab' when at != null => switch (_text(json['prefab'])) {
        final String id => PlacePrefab(
          id,
          at,
          called: _text(json['name']),
          yaw: _number(json['yaw']) ?? 0.0,
        ),
        null => null,
      },
      'setOverride' when key != null => switch (_text(json['path'])) {
        final String path => SetOverride(path, key, json['value']),
        null => null,
      },
      'applyOverrides' => ApplyOverrides(path: _text(json['path'])),
      'revertOverrides' => RevertOverrides(path: _text(json['path']), key: key),
      'unpackPrefab' => const UnpackPrefab(),
      'setPrefabField' when key != null => switch ((
        _text(json['prefab']),
        _text(json['path']),
      )) {
        (final String id, final String path) => SetPrefabField(
          id,
          path,
          key,
          json['value'],
        ),
        _ => null,
      },
      _ => null,
    };
  }

  static Vector3? _vector(Object? value) =>
      value is List && value.length == 3 && value.every((Object? e) => e is num)
      ? Vector3(
          (value[0]! as num).toDouble(),
          (value[1]! as num).toDouble(),
          (value[2]! as num).toDouble(),
        )
      : null;

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  static String? _text(Object? value) => value is String ? value : null;

  static Piece? _kind(Object? value) {
    for (final piece in Piece.values) {
      if (piece.name == value) return piece;
    }
    return null;
  }

  static List<double> _numbers(Vector3 it) => <double>[it.x, it.y, it.z];

  /// A number in a sentence: two decimals, and no trailing zeros to read past.
  ///
  /// The grid is quarters, so `0.25` survives while `4.00` reads as `4` and
  /// `22.50` as `22.5` — which is what the generators write into these
  /// documents and what a person says out loud.
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

  static String _where(Vector3 it) =>
      '${_round(it.x)}, ${_round(it.y)}, ${_round(it.z)}';
}

/// Every command name, in the order a list of tools should offer them.
///
/// **The list belongs here rather than to whatever builds the tools.** A server
/// that kept its own copy would be a server that silently cannot call the
/// eleventh command, and nothing would say so until somebody asked for it. This
/// is the one place that knows the set is closed, because the set is a sealed
/// hierarchy in this file.
const List<String> editorCommandNames = <String>[
  'moveBy',
  'resize',
  'addBrush',
  'addLight',
  'place',
  'duplicate',
  'delete',
  'setField',
  'brighten',
  'turn',
  'setLights',
  'createPrefab',
  'placePrefab',
  'setOverride',
  'applyOverrides',
  'revertOverrides',
  'unpackPrefab',
  'setPrefabField',
];

/// Moves whatever is selected, by a vector, onto the grid.
///
/// One command for all three kinds, because [Editing.nudge] is one method for
/// all three: a position is a position, and a command per kind would be three
/// places to get the grid wrong.
final class MoveSelectionBy extends EditorCommand {
  /// The vector is copied rather than kept, because a `Vector3` is mutable and a
  /// command somebody holds on to must not change meaning under them.
  MoveSelectionBy(Vector3 by) : by = by.clone();

  final Vector3 by;

  @override
  String get name => 'moveBy';

  @override
  String get says => 'move by ${EditorCommand._where(by)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': EditorCommand._numbers(by),
  };

  /// Everything selected moves, so a row of torches picked in the outliner
  /// shifts as a row; with one thing selected that is [Editing.nudge].
  @override
  bool apply(Editing editing) {
    if (editing.where == null) return false;
    editing.nudgeAll(by);
    return true;
  }
}

/// Grows or shrinks the selected brush about its own centre.
///
/// Brushes only, like [Editing.grow]: a light has no size, and what the same
/// two keys do to one is [Brighten].
final class Resize extends EditorCommand {
  Resize(Vector3 by) : by = by.clone();

  final Vector3 by;

  @override
  String get name => 'resize';

  @override
  String get says => 'resize by ${EditorCommand._where(by)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': EditorCommand._numbers(by),
  };

  @override
  bool apply(Editing editing) {
    if (editing.brush == null) return false;
    editing.grow(by);
    return true;
  }
}

/// Puts a new brush down and selects it.
///
/// A size and a material may be left out, and then the document decides: two
/// metres cubed, in whatever the level is mostly made of. See [Editing.add] for
/// why guessing a material would be worse than asking the document for one.
final class AddBrush extends EditorCommand {
  AddBrush(Vector3 at, {Vector3? size, this.material})
    : at = at.clone(),
      size = size?.clone();

  final Vector3 at;
  final Vector3? size;
  final String? material;

  @override
  String get name => 'addBrush';

  @override
  String get says =>
      'add a ${material ?? 'brush'} at ${EditorCommand._where(at)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'at': EditorCommand._numbers(at),
    // Left out rather than written as null: what the document does when a size
    // or a material is absent is decide one, and a key with nothing under it
    // would read as somebody having asked for nothing in particular.
    if (size != null) 'size': EditorCommand._numbers(size!),
    if (material != null) 'material': material,
  };

  @override
  bool apply(Editing editing) {
    editing.add(at, size: size, material: material);
    return true;
  }
}

/// Puts a new light down and selects it.
final class AddLevelLight extends EditorCommand {
  AddLevelLight(Vector3 at, {this.intensity = 4.0, this.range = 8.0})
    : at = at.clone();

  final Vector3 at;

  /// The light's strength in the level's units, as [LevelLight.intensity]:
  /// a pre-1.0 multiple that `Photometric.legacyUnit` turns into candela.
  final double intensity;

  /// How far the light reaches, in metres.
  final double range;

  @override
  String get name => 'addLight';

  @override
  String get says => 'add a light at ${EditorCommand._where(at)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'at': EditorCommand._numbers(at),
    'intensity': intensity,
    'range': range,
  };

  @override
  bool apply(Editing editing) {
    editing.addLight(at, intensity: intensity, range: range);
    return true;
  }
}

/// Puts one of what a palette row offers where it was dropped.
///
/// **A kind and a word, not the palette row itself.** A [Placeable] also carries
/// how many of these the level has and what colour to draw the row in, and
/// neither survives being written down and read back as anything but noise: they
/// are how a row is *shown*, and this is what a row *does*. [Editing.place]
/// reads exactly these two.
final class Place extends EditorCommand {
  Place(
    this.kind,
    this.what,
    Vector3 at, {
    this.properties = const <String, Object?>{},
  }) : at = at.clone();

  /// Which of the document's three lists this adds to.
  final Piece kind;

  /// A material for a brush, an entity type for an entity, [paletteLight] for a light.
  final String what;

  final Vector3 at;

  /// What a placed entity starts with when the level has none of its type to
  /// copy: a plugin's palette entry's `PaletteEntry.properties`. Written into
  /// [arguments] only when there are any, so a placement without them reads
  /// and writes as it always did.
  final Map<String, Object?> properties;

  @override
  String get name => 'place';

  @override
  String get says => 'place a $what at ${EditorCommand._where(at)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'kind': kind.name,
    'what': what,
    'at': EditorCommand._numbers(at),
    if (properties.isNotEmpty) 'properties': properties,
  };

  @override
  bool apply(Editing editing) {
    editing.place(
      Placeable(
        kind: kind,
        what: what,
        count: 0,
        tint: Vector3.zero(),
        properties: properties,
      ),
      at,
    );
    return true;
  }
}

/// Copies whatever is selected, a step to the side, and selects the copy.
final class Duplicate extends EditorCommand {
  const Duplicate();

  @override
  String get name => 'duplicate';

  @override
  String get says => 'duplicate the selection';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  bool apply(Editing editing) {
    if (editing.piece == null) return false;
    editing.duplicate();
    return true;
  }
}

/// Removes whatever is selected — all of it, when several things are.
final class Delete extends EditorCommand {
  const Delete();

  @override
  String get name => 'delete';

  @override
  String get says => 'delete the selection';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  bool apply(Editing editing) {
    if (editing.piece == null) return false;
    editing.removeAll();
    return true;
  }
}

/// Writes one field of the selected thing, or removes it when [value] is null.
///
/// The one command that can answer false for a reason that is not "nothing is
/// selected": [Editing.setField] refuses a value the format cannot read rather
/// than writing a document that will not load.
final class SetField extends EditorCommand {
  const SetField(this.key, this.value);

  final String key;
  final Object? value;

  @override
  String get name => 'setField';

  @override
  String get says => value == null ? 'clear $key' : 'set $key to $value';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'key': key,
    'value': value,
  };

  @override
  bool apply(Editing editing) => editing.setField(key, value);
}

/// Makes the selected light stronger or weaker, by a factor.
///
/// A factor rather than an amount, for the reason [Editing.brighten] gives:
/// light is read that way, and the step from 1 to 2 is the step from 8 to 16.
final class Brighten extends EditorCommand {
  const Brighten(this.by);

  /// A unitless multiplier on the light's strength.
  final double by;

  @override
  String get name => 'brighten';

  @override
  String get says => 'brighten by ${EditorCommand._round(by)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'by': by};

  @override
  bool apply(Editing editing) {
    if (editing.light == null) return false;
    editing.brighten(by);
    return true;
  }
}

/// Turns the selected entity about the vertical.
///
/// Radians on the wire, because that is what the document holds and what
/// [Editing.turn] takes; degrees in [says], because that is what a person
/// reading a status bar is thinking in.
final class Turn extends EditorCommand {
  const Turn(this.by);

  /// In radians, added to the entity's yaw.
  final double by;

  @override
  String get name => 'turn';

  @override
  String get says => 'turn by ${EditorCommand._round(by * 180.0 / math.pi)}°';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'by': by};

  @override
  bool apply(Editing editing) {
    if (editing.entity == null) return false;
    editing.turn(by);
    return true;
  }
}

/// Puts a whole set of lights in place of the level's own.
///
/// **How the light optimizer's answer reaches the document.** The optimizer
/// decides about every light at once — which go, which merge, how strong the
/// rest are — and that is one edit a person takes or leaves, so it is one
/// command and one step of undo rather than a delete per light removed.
/// [why] is what the step is called: the optimizer's own sentence, "3 → 1
/// lights" and the numbers, so the history says what the change bought.
final class SetLights extends EditorCommand {
  SetLights(List<LevelLight> lights, {this.why})
    : lights = List<LevelLight>.unmodifiable(lights);

  /// Reads the command's arguments, or null when a light in them cannot be
  /// read — the whole set refused rather than the readable part applied, for
  /// the reason [EditorCommand.fromJson] gives.
  static SetLights? fromArguments(Map<String, Object?> json) {
    final rows = json['lights'];
    if (rows is! List || rows.any((Object? row) => row is! Map)) return null;
    final why = json['why'];
    try {
      return SetLights(<LevelLight>[
        for (final row in rows)
          LevelLight.fromJson((row as Map).cast<String, Object?>()),
      ], why: why is String ? why : null);
    } on LevelFormatException {
      return null;
    }
  }

  final List<LevelLight> lights;

  /// What the change was for, or null.
  final String? why;

  @override
  String get name => 'setLights';

  @override
  String get says => why ?? 'set the lights to ${lights.length}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'lights': <Map<String, Object?>>[
      for (final light in lights) light.toJson(),
    ],
    if (why != null) 'why': why,
  };

  @override
  bool apply(Editing editing) {
    editing.setLights(lights);
    return true;
  }
}

/// Turns the selected entities into a prefab called [prefab], and puts one
/// instance of it where they were — see [Editing.createPrefab].
final class CreatePrefab extends EditorCommand {
  const CreatePrefab(this.prefab);

  final String prefab;

  @override
  String get name => 'createPrefab';

  @override
  String get says => 'make prefab $prefab from the selection';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'prefab': prefab};

  @override
  bool apply(Editing editing) => editing.createPrefab(prefab);
}

/// Puts an instance of [prefab] down and selects it — see
/// [Editing.placePrefab].
final class PlacePrefab extends EditorCommand {
  PlacePrefab(this.prefab, Vector3 at, {this.called, this.yaw = 0.0})
    : at = at.clone();

  final String prefab;
  final Vector3 at;

  /// What the instance is called — `name` on the wire — and so the first
  /// segment of the names of everything it stands for. Null leaves those
  /// names as the template has them.
  final String? called;

  /// Its facing, in radians about the vertical.
  final double yaw;

  @override
  String get name => 'placePrefab';

  @override
  String get says => 'place prefab $prefab at ${EditorCommand._where(at)}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'prefab': prefab,
    'at': EditorCommand._numbers(at),
    if (called != null) 'name': called,
    if (yaw != 0.0) 'yaw': yaw,
  };

  @override
  bool apply(Editing editing) =>
      editing.placePrefab(prefab, at, name: called, yaw: yaw);
}

/// Makes the selected instance's [key] of the entity at [path] say [value],
/// in that instance only — null takes the key away there.
///
/// [path] is the entity's name in the template, or `#<index>`, with the
/// names of nested instances before it: `top/bulb`. A dotted [key] reaches
/// one field of an object property: `glow.strength`.
final class SetOverride extends EditorCommand {
  const SetOverride(this.path, this.key, this.value);

  final String path;
  final String key;
  final Object? value;

  @override
  String get name => 'setOverride';

  @override
  String get says => 'override $path $key with $value';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'path': path,
    'key': key,
    'value': value,
  };

  @override
  bool apply(Editing editing) => editing.setOverride(path, key, value);
}

/// Writes the selected instance's overrides into its prefab — all of them,
/// or those of the entity at [path] — so every instance gets them.
final class ApplyOverrides extends EditorCommand {
  const ApplyOverrides({this.path});

  final String? path;

  @override
  String get name => 'applyOverrides';

  @override
  String get says => path == null
      ? 'apply the overrides to the prefab'
      : 'apply the overrides of $path to the prefab';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    if (path != null) 'path': path,
  };

  @override
  bool apply(Editing editing) => editing.applyOverrides(path: path);
}

/// Drops the selected instance's overrides — all, those at [path], or the
/// one [key] there — so it shows its prefab again.
final class RevertOverrides extends EditorCommand {
  const RevertOverrides({this.path, this.key});

  final String? path;
  final String? key;

  @override
  String get name => 'revertOverrides';

  @override
  String get says => switch ((path, key)) {
    (null, _) => 'revert the overrides',
    (final String path, null) => 'revert the overrides of $path',
    (final String path, final String key) => 'revert $key of $path',
  };

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    if (path != null) 'path': path,
    if (key != null) 'key': key,
  };

  @override
  bool apply(Editing editing) =>
      editing.revertOverrides(path: path, key: path == null ? null : key);
}

/// Breaks the selected instance's link to its prefab, one level down — see
/// [Editing.unpackPrefab].
final class UnpackPrefab extends EditorCommand {
  const UnpackPrefab();

  @override
  String get name => 'unpackPrefab';

  @override
  String get says => 'unpack the prefab instance';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  bool apply(Editing editing) => editing.unpackPrefab();
}

/// Writes [key] of the entity at [path] in [prefab]'s template, or takes it
/// away when [value] is null: the edit every instance sees.
final class SetPrefabField extends EditorCommand {
  const SetPrefabField(this.prefab, this.path, this.key, this.value);

  final String prefab;
  final String path;
  final String key;
  final Object? value;

  @override
  String get name => 'setPrefabField';

  @override
  String get says => value == null
      ? 'clear $key of $path in $prefab'
      : 'set $key of $path in $prefab to $value';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'prefab': prefab,
    'path': path,
    'key': key,
    'value': value,
  };

  @override
  bool apply(Editing editing) =>
      editing.setPrefabField(prefab, path, key, value);
}
