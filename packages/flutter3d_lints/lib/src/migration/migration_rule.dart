/// One row of the migration table as the analyzer plugin and the batch
/// migrator use it: an entry `dart fix` cannot carry out, because it needs
/// the resolved code — a receiver's type, a class's own clauses — to write
/// the replacement.
library;

/// What [MigrationRule] asks of a use it matches.
enum MigrationKind {
  /// Replace the use with [MigrationRule.template].
  rewrite,

  /// Move the type from a class's `implements` to its `with`, and make the
  /// class `base` when it is not `base`, `final` or `sealed` already.
  implementsToWith,

  /// [MigrationRule.type] became a `base` or a `final` class
  /// ([MigrationRule.to]). Under a `base` one, a class of the project's own
  /// below it, directly or through its own classes, becomes `base` too, and
  /// one that implemented it extends it instead where nothing else is its
  /// superclass. A `final` one cannot be extended or implemented outside
  /// its package at all: the clause naming it gets a TODO.
  subclassModifier,

  /// Move the named arguments [MigrationRule.members] of a call into
  /// `[MigrationRule.into]: [MigrationRule.options](…)`.
  regroup,

  /// Give a `switch` over [MigrationRule.switchOver] with no wildcard one
  /// that throws, with a TODO: the type is no longer an enum or sealed, so
  /// naming every value it had is no longer every value.
  enumToClass,

  /// Read a record field of [MigrationRule.type], a class now, through the
  /// getter [MigrationRule.fields] names; a destructuring pattern is left to
  /// a person.
  recordToClass,

  /// Turn a null check right beside a call that throws
  /// [MigrationRule.exception] now into `try … on`, with a TODO; a call with
  /// no check beside it gets the TODO alone.
  nullToThrow,

  /// Rewrite the value passed to, or assigned to, a parameter or a field
  /// of [MigrationRule.members] through [MigrationRule.template], and name
  /// it [MigrationRule.to] where it was renamed; only a value of one of
  /// [MigrationRule.types] when there are any.
  argument,

  /// The name went internal: one diagnostic per import of
  /// [MigrationRule.package] in a file that uses one, listing them.
  internal,

  /// Say what to do, with a link; change nothing.
  manual,

  /// The class [MigrationRule.type] is [MigrationRule.to]: written where a
  /// creation names it and the analyzer finds no type there (`const
  /// Old()`), which is the one place `dart fix`'s rename does not reach.
  rename,

  /// Name the positional arguments a call of [MigrationRule.type] (or its
  /// [MigrationRule.member]) still passes by place where they became named:
  /// [MigrationRule.fields] maps each old index to the parameter's name.
  /// `dart fix` has the same change and offers no fix for an extra
  /// positional argument, so this is what carries it out.
  parameters,

  /// The hook [MigrationRule.member] of [MigrationRule.type] takes one
  /// [MigrationRule.options] where it took a list of parameters. An
  /// override takes the context and reads each old parameter from the
  /// field [MigrationRule.fields] maps it to (by its old index, or its name
  /// for a named one); a call passes `Options(field: argument, …)`.
  hookContext,

  /// The name [MigrationRule.type] is declared in another library since the
  /// release: imported from [MigrationRule.imports] (and named
  /// [MigrationRule.to] where it was renamed on the way) where the analyzer
  /// finds no such name. `dart fix` carries the same move only in a file
  /// that imports a library its fix names, not one that reached the name
  /// through the project's own re-export.
  moved,
}

/// Which uses of a rule's name a [MigrationKind.manual] rule is about.
enum MigrationMatch {
  /// Every reference to the name, or to [MigrationRule.members] of it.
  uses,

  /// Only `implements` and `extends` clauses naming it: the change is one an
  /// implementer or a subclass has to make. A class that mixes it in gets
  /// the new members' bodies with it.
  subtypes,

  /// Only a `switch` over a value of [MigrationRule.switchOver] with no
  /// default: the new case is what it lacks.
  switches,
}

/// One migration a resolved unit can be checked against.
final class MigrationRule {
  const MigrationRule({
    required this.id,
    required this.kind,
    required this.package,
    required this.type,
    required this.message,
    required this.link,
    this.member,
    this.template,
    this.imports = const <String>[],
    this.switchOver,
    this.match = MigrationMatch.uses,
    this.members = const <String>[],
    this.into,
    this.options,
    this.fields = const <String, String>{},
    this.exception,
    this.instead,
    this.library = false,
    this.to,
    this.types = const <String>[],
    this.receiver,
    this.throughClass = false,
    this.renamedTo,
    this.awaits = false,
  });

  /// A rule from the plain data `flutter3d_build`'s `lintsRules` writes:
  /// the same fields, named the same, with the kind and the match by name.
  /// What the batch migrator's `--rules` reads, so a table of a test's own
  /// runs through the same scan.
  factory MigrationRule.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? v) => <String>[
      for (final s in (v as List<Object?>?) ?? const <Object?>[]) '$s',
    ];
    return MigrationRule(
      id: json['id']! as String,
      kind: MigrationKind.values.byName(json['kind']! as String),
      package: json['package']! as String,
      type: json['type']! as String,
      message: json['message']! as String,
      link: json['link']! as String,
      member: json['member'] as String?,
      template: json['template'] as String?,
      imports: strings(json['imports']),
      switchOver: json['switchOver'] as String?,
      match: MigrationMatch.values.byName(
        (json['match'] as String?) ?? MigrationMatch.uses.name,
      ),
      members: strings(json['members']),
      into: json['into'] as String?,
      options: json['options'] as String?,
      fields: <String, String>{
        for (final MapEntry(:key, :value)
            in ((json['fields'] as Map<String, Object?>?) ??
                    const <String, Object?>{})
                .entries)
          key: '$value',
      },
      exception: json['exception'] as String?,
      instead: json['instead'] as String?,
      library: (json['library'] as bool?) ?? false,
      to: json['to'] as String?,
      types: strings(json['types']),
      receiver: json['receiver'] as String?,
      throughClass: (json['throughClass'] as bool?) ?? false,
      renamedTo: json['renamedTo'] as String?,
      awaits: (json['awaits'] as bool?) ?? false,
    );
  }

  /// Which uses a manual rule reports.
  final MigrationMatch match;

  /// For [MigrationMatch.uses]: only these members of [type] — the type's
  /// own name standing for its unnamed constructor. Empty for every use.
  /// For [MigrationKind.regroup]: the named arguments that move. For
  /// [MigrationKind.argument]: the parameters and fields whose value it
  /// rewrites.
  final List<String> members;

  /// The table entry's id: also the anchor of its line in the guide.
  final String id;
  final MigrationKind kind;

  /// The package that declared [type] at the release migrated from.
  final String package;

  /// The top-level name the entry is about.
  final String type;

  /// The member of [type] it is about, or null for the type itself.
  final String? member;

  /// For [MigrationKind.rewrite]: the replacement, with `{target}` for the
  /// receiver (dropped with its dot when there is none), `{0}`, `{1}`… for
  /// the arguments of a call, `{arguments}` for all of them as written and
  /// `{typeArguments}` for its type arguments. For [MigrationKind.argument]: the value
  /// written, with `{value}` for the old one and `{components}` for its
  /// components, as a vector's creation lists them or `v.x, v.y, …`.
  final String? template;

  /// The libraries [template] needs in scope, imported when it is not.
  final List<String> imports;

  /// For a new case of a sealed type or a new enum value: the type whose
  /// exhaustive `switch`es lost their exhaustiveness.
  final String? switchOver;

  /// One sentence for a person.
  final String message;

  /// The guide's line for it.
  final String link;

  /// For [MigrationKind.regroup]: the parameter that takes the group.
  final String? into;

  /// For [MigrationKind.regroup]: the group's class. For
  /// [MigrationKind.hookContext]: the context's class.
  final String? options;

  /// For [MigrationKind.recordToClass]: each record field (`$1`, `name`) to
  /// the class's getter. For [MigrationKind.parameters]: each old position
  /// (`0`, `1`) to the name its argument is passed by now. For
  /// [MigrationKind.argument]: each member of the old type read off the
  /// field (`x`) to the new type's (`r`). For [MigrationKind.hookContext]:
  /// each old parameter, by position or by name for a named one, to the
  /// context's field that holds it.
  final Map<String, String> fields;

  /// For [MigrationKind.nullToThrow]: what the call throws now.
  final String? exception;

  /// For [MigrationKind.internal]: what stays public in its place.
  final String? instead;

  /// For [MigrationKind.internal]: whether [type] is a library's URI, a
  /// library gone whole, rather than a name.
  final bool library;

  /// For [MigrationKind.argument]: the parameter's new name, null where it
  /// kept its own. For [MigrationKind.rename]: the class's new name. For
  /// [MigrationKind.subclassModifier]: the modifier the class took, `base`
  /// or `final`.
  final String? to;

  /// For [MigrationKind.argument]: the types (by name) of the values it
  /// rewrites, the parameter's old ones; for [MigrationKind.rewrite], those
  /// of a call's first argument, the only calls it rewrites. Empty for any
  /// value.
  final List<String> types;

  /// For a [MigrationKind.rewrite] of an extension's member: the type the
  /// extension was on (`List`), whose values the gone member is matched on.
  final String? receiver;

  /// For a [MigrationKind.rewrite] of a static member that is an instance's
  /// now: only a use named through the class is rewritten, since a use
  /// through an instance is already 1.0 code.
  final bool throughClass;

  /// [type]'s name in the release migrated to, where a `rename` entry
  /// renamed the class: `dart fix` renames the uses first, so the code the
  /// scan reads names the new class.
  final String? renamedTo;

  /// For a [MigrationKind.manual] rule about members that became
  /// asynchronous: a call of one inside an `async` body is awaited, which
  /// is all it needs there; elsewhere the TODO stays.
  final bool awaits;
}
