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
  });

  /// Which uses a manual rule reports.
  final MigrationMatch match;

  /// For [MigrationMatch.uses]: only these members of [type] — the type's
  /// own name standing for its unnamed constructor. Empty for every use.
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
}
