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

  /// The name went internal: one diagnostic per import of
  /// [MigrationRule.package] in a file that uses one, listing them.
  internal,

  /// Say what to do, with a link; change nothing.
  manual,
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
    );
  }

  /// Which uses a manual rule reports.
  final MigrationMatch match;

  /// For [MigrationMatch.uses]: only these members of [type] — the type's
  /// own name standing for its unnamed constructor. Empty for every use.
  /// For [MigrationKind.regroup]: the named arguments that move.
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
  /// receiver (dropped with its dot when there is none) and `{0}`, `{1}`…
  /// for the arguments of a call.
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

  /// For [MigrationKind.regroup]: the group's class.
  final String? options;

  /// For [MigrationKind.recordToClass]: each record field (`$1`, `name`) to
  /// the class's getter.
  final Map<String, String> fields;

  /// For [MigrationKind.nullToThrow]: what the call throws now.
  final String? exception;

  /// For [MigrationKind.internal]: what stays public in its place.
  final String? instead;

  /// For [MigrationKind.internal]: whether [type] is a library's URI, a
  /// library gone whole, rather than a name.
  final bool library;
}
