/// What a plugin tells an editor about the things it brings, without
/// depending on one: the hints an inspector is built from.
///
/// **A game's plugin should not need the editor to be edited.** A plugin
/// that adds a component, an entity kind or a lit model is a dependency of a
/// game, and the editor (`flutter3d_editor_core`, a Flutter-free package that
/// still pulls in the collision world and the software rasteriser) is not.
/// So the words a plugin describes its fields in live here, over the
/// foundation alone, and the registry it hands them to,
/// [EditorHintRegistry], is a slot an engine with no editor simply does not
/// have:
///
/// ```dart
/// void install(PluginHost host) {
///   host.maybeRegistry<EditorHintRegistry>()
///     ?..addComponent(const ComponentHints(
///         id: 'boats.buoyancy',
///         title: 'Buoyancy',
///         fields: <FieldHint>[
///           FieldHint.number('buoyancy', min: 0, max: 4, defaultValue: 1.0),
///           FieldHint.number('drag', min: 0, max: 1, defaultValue: 0.4),
///         ],
///         entityTypes: <String>{'boat'},
///       ))
///     ..addEntityKind(const EntityKindHints(type: 'boat', label: 'Boat'));
/// }
/// ```
///
/// An editor fills the slot (`EditorHints` in `flutter3d_editor_core`, which
/// `EditorPieces` brings along) and builds a section of its inspector from
/// each hint: a slider for a number with ends, a switch for a toggle, a list
/// for a choice. A data plugin says the same in its `.f3dplugin`'s `editor:`
/// section, read into the same registry; [FieldHint.toJson] is that shape.
///
/// **A hint describes a control and never constrains a reader**, as a
/// material's hint does: a value outside a number's ends is what the game
/// receives, and the editor says it is outside rather than refusing it. What
/// a hint does refuse is a value of the wrong shape ([FieldHint.refusalOf]):
/// a word where a number goes.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show DocumentFormatException, LinearColor, Registration, Unit;

import 'src/registration.dart';

/// What kind of control a field is shown with, and what shape its value
/// has.
///
/// A class with constants rather than an enum, so a kind added in a minor
/// breaks no `switch`: [name] is what a document writes, and [byName] reads
/// it back. An editor that meets a kind it does not know shows the value as
/// text.
final class FieldKind {
  const FieldKind._(this.name);

  /// A decimal number, optionally with ends, a step and a unit.
  static const FieldKind number = FieldKind._('number');

  /// A whole number, optionally with ends.
  static const FieldKind integer = FieldKind._('integer');

  /// Yes or no.
  static const FieldKind toggle = FieldKind._('toggle');

  /// One word of [FieldHint.choices].
  static const FieldKind choice = FieldKind._('choice');

  /// A linear colour, three numbers from 0 (or four, with alpha).
  static const FieldKind color = FieldKind._('color');

  /// Three numbers: a position, a size, a direction.
  static const FieldKind vector3 = FieldKind._('vector3');

  /// Free text.
  static const FieldKind text = FieldKind._('text');

  /// A path to a file of the project, relative to its assets, ending in one
  /// of [FieldHint.suffixes] when it names any.
  static const FieldKind asset = FieldKind._('asset');

  /// The name of another entity of the same level.
  static const FieldKind entity = FieldKind._('entity');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<FieldKind> values = <FieldKind>[
    number,
    integer,
    toggle,
    choice,
    color,
    vector3,
    text,
    asset,
    entity,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a document written by a later version can carry.
  static FieldKind? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'FieldKind.$name';
}

/// How an inspector shows one field, and what shape its value has.
///
/// **Keyed by the field's name in the thing it describes**: a property of an
/// entity, a parameter of a material, a field of a component's encoded map,
/// an argument of a command.
final class FieldHint {
  /// A field of any [kind]; the named constructors below say the same with
  /// only the members their kind reads.
  const FieldHint(
    this.key,
    this.kind, {
    this.label,
    this.help,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.choices = const <String>[],
    this.suffixes = const <String>[],
    this.defaultValue,
    this.readOnly = false,
  });

  /// A decimal number.
  const FieldHint.number(
    this.key, {
    this.label,
    this.help,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.number,
       choices = const <String>[],
       suffixes = const <String>[];

  /// A whole number.
  const FieldHint.integer(
    this.key, {
    this.label,
    this.help,
    this.min,
    this.max,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.integer,
       step = 1,
       unit = null,
       choices = const <String>[],
       suffixes = const <String>[];

  /// Yes or no.
  const FieldHint.toggle(
    this.key, {
    this.label,
    this.help,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.toggle,
       min = null,
       max = null,
       step = null,
       unit = null,
       choices = const <String>[],
       suffixes = const <String>[];

  /// One of [choices].
  const FieldHint.choice(
    this.key,
    this.choices, {
    this.label,
    this.help,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.choice,
       min = null,
       max = null,
       step = null,
       unit = null,
       suffixes = const <String>[];

  /// A linear colour.
  const FieldHint.color(
    this.key, {
    this.label,
    this.help,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.color,
       min = null,
       max = null,
       step = null,
       unit = null,
       choices = const <String>[],
       suffixes = const <String>[];

  /// Three numbers.
  const FieldHint.vector3(
    this.key, {
    this.label,
    this.help,
    this.unit,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.vector3,
       min = null,
       max = null,
       step = null,
       choices = const <String>[],
       suffixes = const <String>[];

  /// Free text.
  const FieldHint.text(
    this.key, {
    this.label,
    this.help,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.text,
       min = null,
       max = null,
       step = null,
       unit = null,
       choices = const <String>[],
       suffixes = const <String>[];

  /// A path to one of the project's files.
  const FieldHint.asset(
    this.key, {
    this.suffixes = const <String>[],
    this.label,
    this.help,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.asset,
       min = null,
       max = null,
       step = null,
       unit = null,
       choices = const <String>[];

  /// The name of another entity.
  const FieldHint.entity(
    this.key, {
    this.label,
    this.help,
    this.defaultValue,
    this.readOnly = false,
  }) : kind = FieldKind.entity,
       min = null,
       max = null,
       step = null,
       unit = null,
       choices = const <String>[],
       suffixes = const <String>[];

  /// The field's name in what it describes.
  final String key;

  /// The control it is shown with.
  final FieldKind kind;

  /// What the row says, or null for [key].
  final String? label;

  /// A sentence shown beside the control, or null.
  final String? help;

  /// The low end of a number's control, in [unit] (a plain number when the
  /// field names none), or null for none.
  final double? min;

  /// The high end of a number's control, in [unit] (a plain number when the
  /// field names none), or null for none.
  final double? max;

  /// The step a number's control moves in, or null for a free one.
  final double? step;

  /// The unit a number or a vector is in, shown beside it and never applied
  /// to it: the value is written as it was entered.
  final Unit? unit;

  /// The words a [FieldKind.choice] picks from, in order.
  final List<String> choices;

  /// The file suffixes an [FieldKind.asset] takes (`.glb`, `.png`); empty
  /// for any file.
  final List<String> suffixes;

  /// The value an inspector offers where the field is not set, or null for
  /// a field it shows only when it is.
  final Object? defaultValue;

  /// Whether the inspector shows the value without letting it be changed.
  final bool readOnly;

  /// What the row says: [label], or [key].
  String get title => label ?? key;

  /// Why [value] is not the shape this field takes, or null when it is.
  ///
  /// Null is always taken: an absent field is what every optional field
  /// means by "not set". A number outside [min] and [max] is taken too; see
  /// [isInside].
  String? refusalOf(Object? value) {
    if (value == null) return null;
    bool numbers(int count) =>
        value is List &&
        value.length == count &&
        value.every((Object? e) => e is num && e.isFinite);
    final fits = switch (kind) {
      FieldKind.number => value is num && value.isFinite,
      FieldKind.integer => value is int || (value is num && value % 1 == 0),
      FieldKind.toggle => value is bool,
      FieldKind.choice => value is String && choices.contains(value),
      FieldKind.color => numbers(3) || numbers(4),
      FieldKind.vector3 => numbers(3),
      FieldKind.text || FieldKind.entity => value is String,
      FieldKind.asset =>
        value is String &&
            (suffixes.isEmpty ||
                suffixes.any(
                  (String s) => value.toLowerCase().endsWith(s.toLowerCase()),
                )),
      // A kind this build does not know takes what a document can hold.
      _ => true,
    };
    if (fits) return null;
    return switch (kind) {
      FieldKind.choice => '"$key" is one of ${choices.join(', ')}, not $value',
      FieldKind.color =>
        '"$key" is a colour, three or four numbers, not $value',
      FieldKind.vector3 => '"$key" is three numbers, not $value',
      FieldKind.asset when suffixes.isNotEmpty =>
        '"$key" is a path ending in ${suffixes.join(' or ')}, not $value',
      _ => '"$key" is ${_article(kind.name)}, not $value',
    };
  }

  /// Whether [value], a number, is between [min] and [max]; true for
  /// anything else and for a field without ends.
  bool isInside(Object? value) {
    if (value is! num) return true;
    return (min == null || value >= min!) && (max == null || value <= max!);
  }

  /// This hint as a document writes it: [key] and the kind's name, then
  /// only what was given.
  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'kind': kind.name,
    'label': ?label,
    'help': ?help,
    'min': ?min,
    'max': ?max,
    'step': ?step,
    if (unit case final Unit unit) 'unit': unit.toJson(),
    if (choices.isNotEmpty) 'choices': choices,
    if (suffixes.isNotEmpty) 'suffixes': suffixes,
    'default': ?defaultValue,
    if (readOnly) 'readOnly': true,
  };

  /// The hint [json] holds, as [toJson] writes it. A kind this version does
  /// not know is read as [FieldKind.text], so a document a later editor
  /// wrote still opens.
  ///
  /// Throws a [DocumentFormatException] for anything that is not that shape.
  static FieldHint fromJson(Object? json) {
    if (json is! Map) {
      throw DocumentFormatException('a field hint is a map, not $json');
    }
    final key = json['key'];
    if (key is! String || key.isEmpty) {
      throw DocumentFormatException('a field hint names its "key": $json');
    }
    final kindName = json['kind'];
    if (kindName is! String) {
      throw DocumentFormatException('the field "$key" names no "kind"');
    }
    double? number(String name) => switch (json[name]) {
      null => null,
      final num n when n.isFinite => n.toDouble(),
      final other => throw DocumentFormatException(
        'the field "$key" has "$name" $other, which is not a number',
      ),
    };
    List<String> words(String name) => switch (json[name]) {
      null => const <String>[],
      final List<Object?> list when list.every((Object? e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      final other => throw DocumentFormatException(
        'the field "$key" has "$name" $other, which is not a list of words',
      ),
    };
    String? word(String name) => switch (json[name]) {
      null => null,
      final String text => text,
      final other => throw DocumentFormatException(
        'the field "$key" has "$name" $other, which is not text',
      ),
    };
    final Unit? unit;
    try {
      unit = json['unit'] == null ? null : Unit.fromJson(json['unit']);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DocumentFormatException('the field "$key": ${error.message}'),
        stackTrace,
      );
    }
    return FieldHint(
      key,
      FieldKind.byName(kindName) ?? FieldKind.text,
      label: word('label'),
      help: word('help'),
      min: number('min'),
      max: number('max'),
      step: number('step'),
      unit: unit,
      choices: words('choices'),
      suffixes: words('suffixes'),
      defaultValue: json['default'],
      readOnly: json['readOnly'] == true,
    );
  }

  /// This field as a JSON Schema property, for a tool that takes it as an
  /// argument: a command's, offered to an agent.
  Map<String, Object?> get jsonSchema {
    final about = help == null ? title : '$title: $help';
    final description = unit == null ? about : '$about (${unit!.symbol})';
    Map<String, Object?> numbers(int count, [int? most]) => <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'number'},
      'minItems': count,
      'maxItems': most ?? count,
    };
    return <String, Object?>{
      ...switch (kind) {
        FieldKind.number => <String, Object?>{'type': 'number'},
        FieldKind.integer => <String, Object?>{'type': 'integer'},
        FieldKind.toggle => <String, Object?>{'type': 'boolean'},
        FieldKind.choice => <String, Object?>{
          'type': 'string',
          'enum': choices,
        },
        FieldKind.color => numbers(3, 4),
        FieldKind.vector3 => numbers(3),
        _ => <String, Object?>{'type': 'string'},
      },
      'description': description,
      if (kind == FieldKind.number || kind == FieldKind.integer) ...{
        'minimum': ?min,
        'maximum': ?max,
      },
      'default': ?defaultValue,
    };
  }

  @override
  String toString() => 'FieldHint($key, ${kind.name})';
}

String _article(String word) =>
    '${'aeiou'.contains(word[0]) ? 'an' : 'a'} $word';

List<FieldHint> _fieldsOf(Object? json, String owner) => switch (json) {
  null => const <FieldHint>[],
  final List<Object?> list => List<FieldHint>.unmodifiable(
    list.map(FieldHint.fromJson),
  ),
  final other => throw DocumentFormatException(
    '$owner has "fields" $other, which is not a list',
  ),
};

Set<String> _wordsOf(Object? json, String owner, String name) => switch (json) {
  null => const <String>{},
  final List<Object?> list when list.every((Object? e) => e is String) =>
    Set<String>.unmodifiable(list.cast<String>()),
  final other => throw DocumentFormatException(
    '$owner has "$name" $other, which is not a list of words',
  ),
};

String _named(Map<Object?, Object?> json, String name, String what) =>
    switch (json[name]) {
      final String text when text.isNotEmpty => text,
      _ => throw DocumentFormatException('$what names its "$name": $json'),
    };

/// The fields of one component type a plugin registers, as an inspector
/// shows them under one heading.
///
/// **Keyed by [id], the component's codec id** (`boats.buoyancy`), which is
/// the plugin's namespace and the component's name in every file. An
/// entity of one of [entityTypes] shows the section; empty shows it on
/// every entity.
final class ComponentHints {
  const ComponentHints({
    required this.id,
    required this.title,
    this.fields = const <FieldHint>[],
    this.entityTypes = const <String>{},
  });

  /// The component's codec id.
  final String id;

  /// The heading the inspector shows.
  final String title;

  /// Its fields, in the order the inspector lists them.
  final List<FieldHint> fields;

  /// The entity types it belongs on; empty for all of them.
  final Set<String> entityTypes;

  /// As a document writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'fields': <Object?>[for (final field in fields) field.toJson()],
    if (entityTypes.isNotEmpty) 'entityTypes': entityTypes.toList(),
  };

  /// What [json] holds, as [toJson] writes it. Throws a
  /// [DocumentFormatException] for anything else.
  static ComponentHints fromJson(Object? json) {
    if (json is! Map) {
      throw DocumentFormatException('a component\'s hints are a map: $json');
    }
    final id = _named(json, 'id', 'a component');
    return ComponentHints(
      id: id,
      title: switch (json['title']) {
        final String title => title,
        _ => id,
      },
      fields: _fieldsOf(json['fields'], 'the component "$id"'),
      entityTypes: _wordsOf(
        json['entityTypes'],
        'the component "$id"',
        'entityTypes',
      ),
    );
  }

  @override
  String toString() => 'ComponentHints($id)';
}

/// What an editor shows for one entity type: its name in the palette, its
/// colour, its own fields, and the components an entity of it carries.
///
/// **Keyed by [type], the level format's word** (`boat`), not namespaced:
/// a type is read by every genre that speaks it, as `EntityKinds` keys its
/// kinds.
final class EntityKindHints {
  const EntityKindHints({
    required this.type,
    this.label,
    this.tint,
    this.fields = const <FieldHint>[],
    this.components = const <String>{},
  });

  /// The entity type.
  final String type;

  /// What a palette row and an inspector heading say, or null for [type].
  final String? label;

  /// The colour its mark is drawn in, or null for the one the type's name
  /// picks.
  final LinearColor? tint;

  /// Its own properties, in the order the inspector lists them; their
  /// defaults are what a placed one starts with.
  final List<FieldHint> fields;

  /// The ids of the [ComponentHints] an entity of this type shows besides
  /// those that name the type themselves.
  final Set<String> components;

  /// What the inspector heading says.
  String get title => label ?? type;

  /// The properties a newly placed one starts with: every field's default.
  Map<String, Object?> get defaults => <String, Object?>{
    for (final field in fields)
      if (field.defaultValue != null) field.key: field.defaultValue,
  };

  /// As a document writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'label': ?label,
    if (tint case final LinearColor tint)
      'tint': <double>[tint.r, tint.g, tint.b],
    'fields': <Object?>[for (final field in fields) field.toJson()],
    if (components.isNotEmpty) 'components': components.toList(),
  };

  /// What [json] holds, as [toJson] writes it. Throws a
  /// [DocumentFormatException] for anything else.
  static EntityKindHints fromJson(Object? json) {
    if (json is! Map) {
      throw DocumentFormatException('an entity kind\'s hints are a map: $json');
    }
    final type = _named(json, 'type', 'an entity kind');
    return EntityKindHints(
      type: type,
      label: switch (json['label']) {
        final String label => label,
        _ => null,
      },
      tint: switch (json['tint']) {
        null => null,
        [final num r, final num g, final num b] => LinearColor(
          r.toDouble(),
          g.toDouble(),
          b.toDouble(),
        ),
        final other => throw DocumentFormatException(
          'the entity kind "$type" has "tint" $other, which is not three '
          'numbers',
        ),
      },
      fields: _fieldsOf(json['fields'], 'the entity kind "$type"'),
      components: _wordsOf(
        json['components'],
        'the entity kind "$type"',
        'components',
      ),
    );
  }

  @override
  String toString() => 'EntityKindHints($type)';
}

/// The parameters of one lit model a plugin brings, as a material panel
/// shows them for a material that names it.
///
/// **Keyed by [model], the lighting model's stage name** (`acme_Velvet`, or
/// `acme.velvet`): what a material file's `shader` names, the model's
/// `shaderName`.
final class MaterialHints {
  const MaterialHints({required this.model, this.fields = const <FieldHint>[]});

  /// The lighting model's stage name.
  final String model;

  /// Its parameters, by uniform name.
  final List<FieldHint> fields;

  /// The hint for [key], or null.
  FieldHint? operator [](String key) {
    for (final field in fields) {
      if (field.key == key) return field;
    }
    return null;
  }

  /// As a document writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'fields': <Object?>[for (final field in fields) field.toJson()],
  };

  /// What [json] holds, as [toJson] writes it. Throws a
  /// [DocumentFormatException] for anything else.
  static MaterialHints fromJson(Object? json) {
    if (json is! Map) {
      throw DocumentFormatException('a material\'s hints are a map: $json');
    }
    final model = _named(json, 'model', 'a material');
    return MaterialHints(
      model: model,
      fields: _fieldsOf(json['fields'], 'the material "$model"'),
    );
  }

  @override
  String toString() => 'MaterialHints($model)';
}

/// The hints an editor builds its inspectors from: the slot a plugin hands
/// its [ComponentHints], [EntityKindHints] and [MaterialHints] to,
/// `host.maybeRegistry<EditorHintRegistry>()`.
///
/// **Only an editor has one.** A game's engine hands its host no such
/// registry, so a plugin asks with `maybeRegistry` and skips the hints when
/// the answer is null; an editor's `EditorPieces` brings one along.
///
/// **Namespaced as every registration is** (`PluginManifest.namespace`):
/// through a plugin's view a component id and a lit model's name are
/// `<namespace>.<name>`, given whole or given bare and prefixed for it, and a
/// lit model may be `<namespace>_<name>`, the stage name a shader has; a
/// name in another namespace is refused. An entity type is the level
/// format's word and is not.
///
/// Extended by the editor, called by plugins: `base`, so a member added in
/// a minor arrives with a default.
abstract base class EditorHintRegistry extends PluginRegistry {
  const EditorHintRegistry();

  /// Shows [hints] in the inspector of every entity they belong on. Throws
  /// an [ArgumentError] for an id another owner already hinted, naming it.
  Registration addComponent(ComponentHints hints);

  /// Shows [hints] in the inspector of every entity of its type, and offers
  /// the type in the palette. Throws an [ArgumentError] for a type another
  /// owner already hinted, naming it.
  Registration addEntityKind(EntityKindHints hints);

  /// Shows [hints] in the material panel of every material whose lighting
  /// model is [MaterialHints.model]. Throws an [ArgumentError] for a model
  /// another owner already hinted, naming it.
  Registration addMaterial(MaterialHints hints);

  /// Every component's hints, in order: the application's, then each
  /// plugin's by install order.
  List<ComponentHints> get components;

  /// Every entity kind's hints, in the same order.
  List<EntityKindHints> get entityKinds;

  /// Every lit model's hints, in the same order.
  List<MaterialHints> get materials;

  @override
  EditorHintRegistry forPlugin(PluginScope scope);
}

/// A change to an editor's document as a typed value: a command's name and
/// what it carries.
///
/// **The one shape every route into the document takes**: a key, a menu,
/// an agent over MCP and a plugin's panel all run a command, and an editor
/// reads it back from [toJson] by its [name]. An editor's own command
/// hierarchy (`DocumentCommand` in `flutter3d_editor_core`) is one of
/// these, and so is a plugin's (`PluginCommand`); a panel written against
/// the widgets alone, which cannot see that package, extends this
/// directly. A panel hands one to its context (`EditorPanelContext.runCommand`)
/// rather than spelling the map by hand.
///
/// `base`, so a member added here in a 1.x release arrives with a body.
abstract base class EditorCommandValue {
  const EditorCommandValue();

  /// What the command is called: `<namespace>.<name>` for a plugin's, one
  /// word for one of the editor's own.
  String get name;

  /// Everything it carries but its [name], as JSON writes it.
  Map<String, Object?> get arguments;

  /// The command as a map, ready for `jsonEncode`: [name] under `command`,
  /// then [arguments].
  Map<String, Object?> toJson() => <String, Object?>{
    'command': name,
    ...arguments,
  };
}
