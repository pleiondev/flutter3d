import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// One step system of a data plugin written in the expression language, as
/// its document's `expressions` declares it.
///
/// **What took the place of interpreted Dart.** Version 2 of the format had
/// `scripts`, step systems in Dart behind a runtime the application was to
/// provide; none ever shipped, and what a script was for, a deterministic
/// rule over declared world fields, is what an expression says without a
/// compiler in the game. Version 3 reads a `scripts` entry as one of these,
/// with its `source` kept, for its author to rewrite in the expression
/// language.
///
/// The system is named `<plugin id>.<system>` in a step phase, reaches the
/// world only through the fields it [reads] and [writes], and publishes only
/// the [events] its plugin declares: the rules a Wasm system keeps.
final class ExpressionSystemSpec {
  /// A system named [system] in the step phase [phase]. Asserts that
  /// exactly one of [source] and [text] is given.
  const ExpressionSystemSpec({
    required this.system,
    required this.phase,
    this.source,
    this.text,
    this.after = const <String>[],
    this.before = const <String>[],
    this.reads = const <String>[],
    this.writes = const <String>[],
    this.events = const <String>[],
    this.unknown = const <String, Object?>{},
  }) : assert(
         (source == null) != (text == null),
         'an expression system is a source file or its text, not both',
       );

  /// Reads a declaration, or throws a [DocumentFormatException] saying why
  /// not.
  factory ExpressionSystemSpec.fromJson(Map<String, Object?> json) {
    String text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => throw DocumentFormatException(
        'an expression system names no "$key"',
      ),
    };
    List<String> names(String key) => switch (json[key]) {
      null => const <String>[],
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw DocumentFormatException(
        'an expression system\'s "$key" is not a list of names',
      ),
    };
    final system = text('system');
    final (source, written) = switch ((json['source'], json['text'])) {
      (final String source, null) when source.isNotEmpty => (source, null),
      (null, final String written) when written.isNotEmpty => (null, written),
      _ => throw DocumentFormatException(
        'expression system "$system" is a "source" file or its "text", one '
        'of the two',
      ),
    };
    return ExpressionSystemSpec(
      system: system,
      phase: text('phase'),
      source: source,
      text: written,
      after: names('after'),
      before: names('before'),
      reads: names('reads'),
      writes: names('writes'),
      events: names('events'),
      unknown: FormatDocument.nestedUnknownIn(json, known: keys),
    );
  }

  /// The file the expressions are in, relative to the plugin's own
  /// directory; null when they are written in place as [text].
  final String? source;

  /// The expressions written in the document; null when they are in
  /// [source].
  final String? text;

  /// The system's name; the loop has it as `<plugin id>.<system>`.
  final String system;

  /// A step phase.
  final String phase;

  /// Systems it runs after, as `addSystem` takes them.
  final List<String> after;

  /// Systems it runs before, as `addSystem` takes them.
  final List<String> before;

  /// World fields it reads, and those it may also write.
  final List<String> reads;

  /// World fields it may also write.
  final List<String> writes;

  /// Events it may publish, without the plugin's prefix.
  final List<String> events;

  /// The keys a declaration is written with.
  static const Set<String> keys = <String>{
    'system',
    'phase',
    'source',
    'text',
    'after',
    'before',
    'reads',
    'writes',
    'events',
  };

  /// The keys this build does not read, as the document had them: written
  /// back after its own, so a document a later minor wrote and this one
  /// opened and saved keeps what the later one added here
  /// (`FormatDocument.nestedUnknownIn`).
  final Map<String, Object?> unknown;

  /// The declaration as a document writes it, an empty list left out and
  /// [unknown] written back after its own keys.
  Map<String, Object?> toJson() => FormatDocument.writeNested(<String, Object?>{
    'system': system,
    'phase': phase,
    'source': ?source,
    'text': ?text,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
    if (reads.isNotEmpty) 'reads': reads,
    if (writes.isNotEmpty) 'writes': writes,
    if (events.isNotEmpty) 'events': events,
  }, unknown);
}
