/// The one envelope every flutter3d JSON format is written in.
///
/// The registry that knows the formats an engine reads, `FormatRegistry`, is
/// the plugin contract's (`flutter3d_plugin_api`): a plugin registers its
/// formats there. What a format is and how a document is opened is here,
/// so a package that reads one of its own files needs no plugin API.
///
/// **Every JSON document the engine writes starts the same way:**
///
/// ```json
/// {"format": "f3d.level", "version": 3, "requires": [], "generator": "flutter3d"}
/// ```
///
/// * `format` says what the document is, so a tool handed a file can tell a
///   level from a save without guessing from the suffix;
/// * `version` is that format's version, read by a chain of migrations: a 1.x
///   engine reads every 1.x file, and refuses a newer one with a sentence
///   (decision 8 of `tasks/1.0-stability.md`);
/// * `requires` names what a reader has to understand to open the document
///   at all — a plugin's component namespace, a feature added in a minor —
///   so an older reader refuses instead of quietly dropping it;
/// * `generator` is who wrote it.
///
/// **The shapes from before the envelope still read**, as version 1: a bare
/// `{"version": N}`, a format's own key (`{"f3dfx": 1}`,
/// `{"f3dplugin": 1}`), `{"format": "<old id>", "version": N}` with an id the
/// format lists among its [FormatSpec.aliases], and no version at all.
///
/// **Unknown keys are kept.** A [FormatDocument] holds every top-level key
/// its reader did not take in [FormatDocument.unknown], and writes them back,
/// so a document written by a later minor survives being opened and saved by
/// an earlier one.
library;

import 'exceptions.dart';

/// One step of a format's migration chain: a document at one version, as
/// the next version writes it. Handed a copy, so it may change it in place.
typedef FormatMigration =
    Map<String, Object?> Function(Map<String, Object?> document);

/// Turns a sentence into the format's own exception, so a level reader
/// still throws `LevelFormatException` when the envelope is what refused.
typedef FormatRefusal = Flutter3dFormatException Function(String message);

/// What one format is: its id, its suffixes, the version this build writes,
/// the chain that lifts older documents, and where the fixtures that prove
/// each version still reads are kept.
///
/// **Declared once, as a constant, beside the format's reader**:
///
/// ```dart
/// static const FormatSpec spec = FormatSpec(
///   id: 'f3d.level',
///   version: formatVersion,
///   suffixes: <String>['.level.json'],
///   fixture: 'test/fixtures/v<N>/first.level.json',
///   migrations: <FormatMigration>[_identity, _toIds],
/// );
/// ```
///
/// The repository's structure check reads these declarations and fails when
/// a version has no fixture, so a bump without a file minted at it does not
/// get in.
final class FormatSpec {
  const FormatSpec({
    required this.id,
    required this.version,
    this.suffixes = const <String>[],
    this.fixture,
    this.since = 1,
    this.migrations = const <FormatMigration>[],
    this.aliases = const <String>[],
    this.legacyVersionKey,
    this.understands = const <String>{},
    this.enveloped = true,
    this.magic,
  }) : assert(version >= since, 'a format reads its own version');

  /// The format's name in the envelope: `f3d.<kind>` for the engine's,
  /// `<pluginId>.<kind>` for a plugin's.
  final String id;

  /// The version this build writes, and the newest it reads.
  final int version;

  /// The file suffixes the format is saved under, with the dot, longest
  /// first when one ends another (`.level.json` before `.json`).
  final List<String> suffixes;

  /// Where the fixture minted at each version lives, from the package root,
  /// with `<N>` for the version: `test/fixtures/v<N>/first.level.json`.
  final String? fixture;

  /// The oldest version this build reads.
  final int since;

  /// Entry `i` lifts a document from version `since + i` to `since + i + 1`.
  /// Shorter than `version - since` only while the missing steps are the
  /// identity, which [lift] treats them as.
  final List<FormatMigration> migrations;

  /// Ids the format was written under before the envelope, read as this one.
  final List<String> aliases;

  /// The key an old document kept its version under instead of `version`:
  /// `f3dfx` for an effect, `f3dplugin` for a data plugin.
  final String? legacyVersionKey;

  /// The `requires` entries this build understands. A document requiring
  /// anything else is refused, naming it.
  final Set<String> understands;

  /// Whether a document of this format starts with the JSON envelope ([open]
  /// and [envelope] are for it). False for a format whose file is bytes, or
  /// text that is not JSON (the material language): its envelope is its own
  /// magic and version, and it is in the registry for its id, suffixes,
  /// version and fixtures, with [magic] what `FormatRegistry.sniff` looks
  /// for.
  final bool enveloped;

  /// The bytes a file of this format starts with, for a format that is not
  /// [enveloped].
  final List<int>? magic;

  /// The envelope's keys, which no format may use for anything else.
  static const Set<String> envelopeKeys = <String>{
    'format',
    'version',
    'requires',
    'generator',
  };

  /// What [envelope] names as the writer when nobody says otherwise.
  ///
  /// **A constant, not the engine's release number**, because some documents
  /// are digested — a level's digest is what a recorded run is checked
  /// against — and a field that moved with every release would move every
  /// digest with it.
  static const String defaultGenerator = 'flutter3d';

  /// Whether [document] says it is this format, under its id or an alias,
  /// or carries this format's [legacyVersionKey].
  bool claims(Map<String, Object?> document) {
    final said = document['format'];
    if (said is String) return said == id || aliases.contains(said);
    final legacy = legacyVersionKey;
    return legacy != null && document.containsKey(legacy);
  }

  /// The version [document] was written at: `version`, else the legacy key,
  /// else 1 — a document from before the key existed is the first version.
  /// A 0 or a negative is what it says, for [open] to refuse.
  int versionOf(Map<String, Object?> document) {
    final said =
        document['version'] ??
        switch (legacyVersionKey) {
          final String key => document[key],
          null => null,
        };
    return said is num ? said.toInt() : 1;
  }

  /// [document] checked against this format and lifted to [version].
  ///
  /// Refuses, through [refuse] so the format's own exception is what a
  /// caller catches:
  ///
  /// * a document whose `format` names another format;
  /// * a version newer than this build reads, naming both numbers;
  /// * a version older than [since];
  /// * a `requires` entry this build does not [understands].
  ///
  /// The result is a fresh map: [document] is not changed.
  Map<String, Object?> open(
    Map<String, Object?> document, {
    required FormatRefusal refuse,
  }) {
    final said = document['format'];
    if (said != null && said is! String) {
      throw refuse('"format" must be a string naming the format, not $said');
    }
    if (said is String && said != id && !aliases.contains(said)) {
      throw refuse('this is a "$said" document, not "$id"');
    }
    final raw =
        document['version'] ??
        switch (legacyVersionKey) {
          final String key => document[key],
          null => null,
        };
    if (raw != null && (raw is! num || raw != raw.roundToDouble())) {
      throw refuse('"version" must be a whole number, not $raw');
    }
    final at = versionOf(document);
    if (at < 1) throw refuse('"version" counts from 1, not $at');
    if (at > version) {
      throw refuse(
        '$id version $at is newer than this build reads ($version): '
        'update flutter3d to open it',
      );
    }
    if (at < since) {
      throw refuse(
        '$id version $at is older than this build reads ($since and up): '
        'open it with an earlier flutter3d and save it again',
      );
    }
    final requires = switch (document['requires']) {
      null => const <String>[],
      final List<Object?> list when list.every((Object? e) => e is String) =>
        list.cast<String>(),
      final other => throw refuse(
        '"requires" must be a list of names, not $other',
      ),
    };
    final missing = <String>[
      for (final name in requires)
        if (!understands.contains(name)) name,
    ];
    if (missing.isNotEmpty) {
      throw refuse(
        'this $id document requires ${missing.join(', ')}, which this '
        'build does not understand: install the plugin or the flutter3d '
        'release that provides ${missing.length == 1 ? 'it' : 'them'}',
      );
    }
    return lift(<String, Object?>{...document}, from: at);
  }

  /// [document], written at version [from], lifted through [migrations] to
  /// [version]. A step past the end of the list is the identity.
  Map<String, Object?> lift(
    Map<String, Object?> document, {
    required int from,
  }) => Iterable<int>.generate(version - from, (int i) => from + i - since)
      .where((int index) => index >= 0 && index < migrations.length)
      .fold(
        document,
        (Map<String, Object?> lifted, int index) =>
            migrations[index](<String, Object?>{...lifted}),
      );

  /// The envelope this build writes for a document of this format, in the
  /// order it goes at the top of the file.
  Map<String, Object?> envelope({
    int? version,
    List<String> requires = const <String>[],
    String generator = defaultGenerator,
  }) => <String, Object?>{
    'format': id,
    'version': version ?? this.version,
    'requires': <String>[...requires],
    'generator': generator,
  };

  @override
  String toString() => '$id@$version';
}

/// The formats one program knows, gathered from the packages that own them:
/// each adds its [FormatSpec]s, and a tool that walks a project asks which
/// format a file is.
///
/// **What `flutter3d migrate --data` and `doctor` read.** A tool that knows
/// every format can lift every file in a project to the version this build
/// writes, or say which ones are behind. The registry knows nothing of any
/// one format: the program that builds it names the packages it can load,
/// so foundation depends on none of them.
///
/// The plugin contract's `FormatRegistry` is the running engine's view, with
/// the plugin that registered each format; this is the plain list a command
/// line needs.
final class FormatSpecs {
  /// A registry holding [formats].
  FormatSpecs([Iterable<FormatSpec> formats = const <FormatSpec>[]]) {
    addAll(formats);
  }

  final Map<String, FormatSpec> _byId = <String, FormatSpec>{};

  /// Every format added, in the order it was added.
  Iterable<FormatSpec> get all => _byId.values;

  /// Adds [spec]. The same spec added again is one registration; another
  /// format under an id or alias already held is refused, naming it, since
  /// a file would otherwise go to whichever reader came last.
  void add(FormatSpec spec) {
    if (identical(_byId[spec.id], spec)) return;
    for (final name in <String>[spec.id, ...spec.aliases]) {
      if (byId(name) case final FormatSpec held) {
        throw ArgumentError(
          'two formats claim "$name": $held and $spec',
          'spec',
        );
      }
    }
    _byId[spec.id] = spec;
  }

  /// Adds each of [specs]: what a package that owns formats calls.
  void addAll(Iterable<FormatSpec> specs) => specs.forEach(add);

  /// The format named [id], under its own id or an alias; null when none
  /// was added.
  FormatSpec? byId(String id) =>
      _byId[id] ??
      _byId.values
          .where((FormatSpec spec) => spec.aliases.contains(id))
          .firstOrNull;

  /// The format a file at [path] is saved as, by its longest matching
  /// suffix, ignoring case; null when no format claims it.
  FormatSpec? forPath(String path) {
    final lower = path.toLowerCase();
    final matches = <(int, FormatSpec)>[
      for (final spec in _byId.values)
        for (final suffix in spec.suffixes)
          if (lower.endsWith(suffix.toLowerCase())) (suffix.length, spec),
    ];
    return matches.fold<(int, FormatSpec?)>(
      (0, null),
      ((int, FormatSpec?) best, (int, FormatSpec) next) =>
          next.$1 > best.$1 ? next : best,
    ).$2;
  }
}

/// A document read through a [FormatSpec], which keeps every top-level key
/// its reader did not take.
///
/// **Extended by every format's document type**, so the rule "unknown keys
/// are kept" is written once. A reader passes the keys it reads to
/// [unknownIn]; the writer calls [write] with its own body, and gets the
/// envelope first, then the body, then whatever was not understood, in the
/// order it arrived.
abstract base class FormatDocument {
  FormatDocument({Map<String, Object?> unknown = const <String, Object?>{}})
    : unknown = Map<String, Object?>.unmodifiable(unknown);

  /// The format this document is.
  FormatSpec get spec;

  /// The top-level keys the reader did not understand, as they were.
  final Map<String, Object?> unknown;

  /// What `requires` says when this document is written. Empty by default;
  /// a document that holds something an older reader must not drop — a
  /// plugin's components — names it here.
  List<String> get requires => const <String>[];

  /// The keys of [document] that are neither the envelope's, a legacy
  /// version key, nor in [known].
  static Map<String, Object?> unknownIn(
    Map<String, Object?> document, {
    required Set<String> known,
    FormatSpec? spec,
  }) => <String, Object?>{
    for (final MapEntry(:key, :value) in document.entries)
      if (!FormatSpec.envelopeKeys.contains(key) &&
          key != spec?.legacyVersionKey &&
          !known.contains(key))
        key: value,
  };

  /// [body] in the envelope, with [unknown] after it. A key in both [body]
  /// and [unknown] is written from [body].
  Map<String, Object?> write(
    Map<String, Object?> body, {
    String generator = FormatSpec.defaultGenerator,
  }) => <String, Object?>{
    ...spec.envelope(requires: requires, generator: generator),
    ...body,
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!body.containsKey(key)) key: value,
  };
}

/// A document the envelope refused, when the format has no exception of its
/// own: another format's document, a version from the future, a `requires`
/// this build does not understand.
final class DocumentFormatException extends Flutter3dFormatException {
  const DocumentFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'DocumentFormatException: $message';
}
