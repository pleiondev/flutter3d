/// What a tool is and what it answers, in flutter3d's own types.
///
/// **The MCP library underneath is not part of the contract.** It is
/// pre-1.0, and a type of its in one of our signatures would make every one
/// of its breaks ours. So a tool is a [ToolSpec] and an answer a
/// [ToolResult], both plain values with the JSON shape the protocol sends,
/// and the servers translate at the edge. Decision 10 of
/// `tasks/1.0-api-review.md`.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What a tool does to the world it is called on, as the protocol's
/// annotations say it to a host — which may ask a person before a
/// destructive call, and may call a read-only one without asking.
///
/// **Hints, not guarantees**, in the protocol's own words: a host decides
/// what to do with them. Ours are kept honest by the snapshot, which prints
/// them, so a tool that starts deleting things shows up in review.
final class ToolHints {
  const ToolHints({
    this.readOnly = false,
    this.destructive = false,
    this.idempotent = false,
    this.openWorld = false,
    this.title,
  }) : assert(
         !(readOnly && destructive),
         'a tool that changes nothing destroys nothing',
       );

  /// Reads and changes nothing: a listing, a picture, a check.
  static const ToolHints reads = ToolHints(readOnly: true);

  /// Changes something, and a change can be taken back (an undo step) or
  /// only adds.
  static const ToolHints writes = ToolHints();

  /// Removes or overwrites something that may not come back: a file
  /// written over, a document replaced, a process stopped.
  static const ToolHints destroys = ToolHints(destructive: true);

  final bool readOnly;
  final bool destructive;

  /// Calling it twice with the same arguments does what calling it once did.
  final bool idempotent;

  /// Reaches outside the project: the network, another process.
  final bool openWorld;

  /// A name for a person to read, when the tool's own is a code word.
  final String? title;

  /// The protocol's `annotations` object.
  Map<String, Object?> toJson() => <String, Object?>{
    'title': ?title,
    'readOnlyHint': readOnly,
    'destructiveHint': destructive,
    'idempotentHint': idempotent,
    'openWorldHint': openWorld,
  };

  /// Reads the protocol's `annotations` object; absent hints are false.
  factory ToolHints.fromJson(Map<String, Object?> json) => ToolHints(
    readOnly: json['readOnlyHint'] == true,
    destructive:
        json['destructiveHint'] == true && json['readOnlyHint'] != true,
    idempotent: json['idempotentHint'] == true,
    openWorld: json['openWorldHint'] == true,
    title: json['title'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ToolHints &&
      other.readOnly == readOnly &&
      other.destructive == destructive &&
      other.idempotent == idempotent &&
      other.openWorld == openWorld &&
      other.title == title;

  @override
  int get hashCode =>
      Object.hash(readOnly, destructive, idempotent, openWorld, title);
}

/// One tool, as `tools/list` offers it: a name, a sentence, the JSON Schema
/// of its arguments, the JSON Schema of the `structuredContent` it answers
/// with when it answers one, and its [ToolHints].
///
/// **Schemas are JSON**, the maps the protocol sends, so a tool can be
/// written with any schema builder or by hand, and nothing here pins one.
final class ToolSpec {
  ToolSpec({
    required this.name,
    this.description,
    Map<String, Object?> inputSchema = const <String, Object?>{
      'type': 'object',
    },
    Map<String, Object?>? outputSchema,
    this.hints = ToolHints.writes,
    Map<String, Object?> meta = const <String, Object?>{},
  }) : inputSchema = Map<String, Object?>.unmodifiable(inputSchema),
       outputSchema = outputSchema == null
           ? null
           : Map<String, Object?>.unmodifiable(outputSchema),
       meta = Map<String, Object?>.unmodifiable(meta);

  /// Reads the protocol's tool object, as `tools/list` sends it.
  factory ToolSpec.fromJson(Map<String, Object?> json) => ToolSpec(
    name: json['name']! as String,
    description: json['description'] as String?,
    inputSchema:
        _object(json['inputSchema']) ??
        const <String, Object?>{'type': 'object'},
    outputSchema: _object(json['outputSchema']),
    hints: switch (_object(json['annotations'])) {
      final Map<String, Object?> a => ToolHints.fromJson(a),
      null => ToolHints.writes,
    },
    meta: _object(json['_meta']) ?? const <String, Object?>{},
  );

  /// What an agent calls it by.
  final String name;

  /// What it does, for a model to read. The first sentence is what the
  /// snapshot keeps.
  final String? description;

  /// The JSON Schema of its arguments: an object schema.
  final Map<String, Object?> inputSchema;

  /// The JSON Schema of the `structuredContent` its answers carry, or null
  /// for a tool that answers in words and pictures only.
  ///
  /// **Required wherever an answer is structured**: a host validates the
  /// structured half against it, and an agent reads it to know the fields
  /// it may act on before it calls.
  final Map<String, Object?>? outputSchema;

  final ToolHints hints;

  /// The protocol's `_meta`, for what a server says about the tool beyond
  /// the protocol's own fields — its schema version, under
  /// `flutter3d/schemaVersion`.
  final Map<String, Object?> meta;

  /// The properties [inputSchema] names, by name; empty when it names none.
  Map<String, Object?> get properties =>
      _object(inputSchema['properties']) ?? const <String, Object?>{};

  /// The arguments [inputSchema] requires.
  List<String> get required => <String>[
    for (final Object? name in inputSchema['required'] as List? ?? const [])
      '$name',
  ];

  /// This tool under another name, with [description] when given, and with
  /// [meta] merged over its own.
  ToolSpec copyWith({
    String? name,
    String? description,
    Map<String, Object?>? inputSchema,
    Map<String, Object?>? outputSchema,
    ToolHints? hints,
    Map<String, Object?>? meta,
  }) => ToolSpec(
    name: name ?? this.name,
    description: description ?? this.description,
    inputSchema: inputSchema ?? this.inputSchema,
    outputSchema: outputSchema ?? this.outputSchema,
    hints: hints ?? this.hints,
    meta: <String, Object?>{...this.meta, ...?meta},
  );

  /// The protocol's tool object.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': ?description,
    'inputSchema': inputSchema,
    'outputSchema': ?outputSchema,
    'annotations': hints.toJson(),
    if (meta.isNotEmpty) '_meta': meta,
  };

  @override
  String toString() => 'ToolSpec($name)';
}

/// One piece of what a tool answers: words, a picture, a sound, a resource
/// or a link to one, as the protocol's content objects say them.
///
/// **An `abstract base class`, not `sealed`.** The protocol adds kinds of
/// content in its own releases; a sealed type would make each of them a
/// break for every exhaustive `switch` here and in a host. A kind this
/// build has no class for arrives as [ToolOtherContent], with its JSON as
/// it came, so a result read and written again keeps it rather than turning
/// it into empty words.
abstract base class ToolContent {
  const ToolContent();

  /// Reads one of the protocol's content objects: `text`, `image`, `audio`,
  /// `resource` and `resource_link` by their own classes, anything else as
  /// [ToolOtherContent].
  factory ToolContent.fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'text' when json['text'] is String => ToolText(json['text']! as String),
        'image' when json['data'] is String => ToolImage(
          base64Decode(json['data']! as String),
          mimeType: json['mimeType'] as String? ?? 'image/png',
        ),
        'audio' when json['data'] is String && json['mimeType'] is String =>
          ToolAudio(
            base64Decode(json['data']! as String),
            mimeType: json['mimeType']! as String,
          ),
        'resource' => switch (_object(json['resource'])) {
          final Map<String, Object?> r when r['uri'] is String => ToolResource(
            uri: r['uri']! as String,
            mimeType: r['mimeType'] as String?,
            text: r['text'] as String?,
            blob: switch (r['blob']) {
              final String data => base64Decode(data),
              _ => null,
            },
          ),
          _ => ToolOtherContent(json),
        },
        'resource_link' when json['uri'] is String && json['name'] is String =>
          ToolResourceLink(
            uri: json['uri']! as String,
            name: json['name']! as String,
            description: json['description'] as String?,
            mimeType: json['mimeType'] as String?,
          ),
        _ => ToolOtherContent(json),
      };

  /// The protocol's content object.
  Map<String, Object?> toJson();
}

/// Words a tool answers with.
final class ToolText extends ToolContent {
  const ToolText(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'text',
    'text': text,
  };
}

/// A picture a tool answers with: the encoded bytes and their media type.
final class ToolImage extends ToolContent {
  const ToolImage(this.bytes, {this.mimeType = 'image/png'});

  final Uint8List bytes;
  final String mimeType;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'image',
    'data': base64Encode(bytes),
    'mimeType': mimeType,
  };
}

/// A sound a tool answers with: the encoded bytes and their media type
/// (`audio/wav`, `audio/ogg`).
final class ToolAudio extends ToolContent {
  const ToolAudio(this.bytes, {required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'audio',
    'data': base64Encode(bytes),
    'mimeType': mimeType,
  };
}

/// A resource carried inside the answer: its [uri], and its contents as
/// [text] or as bytes ([blob]).
final class ToolResource extends ToolContent {
  const ToolResource({required this.uri, this.mimeType, this.text, this.blob})
    : assert(
        (text == null) != (blob == null),
        'a resource carries text or bytes, one of them',
      );

  final String uri;
  final String? mimeType;
  final String? text;
  final Uint8List? blob;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'resource',
    'resource': <String, Object?>{
      'uri': uri,
      'mimeType': ?mimeType,
      'text': ?text,
      if (blob case final Uint8List bytes) 'blob': base64Encode(bytes),
    },
  };
}

/// A link to a resource the client may read, rather than its contents.
final class ToolResourceLink extends ToolContent {
  const ToolResourceLink({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'resource_link',
    'uri': uri,
    'name': name,
    'description': ?description,
    'mimeType': ?mimeType,
  };
}

/// Content of a kind this build has no class for, kept as the JSON it came
/// as and written back unchanged.
final class ToolOtherContent extends ToolContent {
  ToolOtherContent(Map<String, Object?> json)
    : json = Map<String, Object?>.unmodifiable(json);

  /// The content object as it arrived, `type` included.
  final Map<String, Object?> json;

  /// The kind it says it is, or null when it says none.
  String? get type => json['type'] as String?;

  @override
  Map<String, Object?> toJson() => json;
}

/// What a tool call answers: [content] for a model to read, and the
/// machine-readable [structuredContent] when the tool declares an
/// `outputSchema`.
///
/// **A refusal is an answer**, marked [isError]: the agent is told to try
/// something else. An exception is the server failing, which is reported
/// to the host as that.
final class ToolResult {
  ToolResult({
    List<ToolContent> content = const <ToolContent>[],
    Map<String, Object?>? structuredContent,
    this.isError = false,
  }) : content = List<ToolContent>.unmodifiable(content),
       structuredContent = structuredContent == null
           ? null
           : Map<String, Object?>.unmodifiable(structuredContent);

  /// One sentence, as most tools answer.
  factory ToolResult.text(String text, {bool isError = false}) =>
      ToolResult(content: <ToolContent>[ToolText(text)], isError: isError);

  /// Reads the protocol's result object.
  factory ToolResult.fromJson(Map<String, Object?> json) => ToolResult(
    content: <ToolContent>[
      for (final Object? item in json['content'] as List? ?? const [])
        if (_object(item) case final Map<String, Object?> c)
          ToolContent.fromJson(c),
    ],
    structuredContent: _object(json['structuredContent']),
    isError: json['isError'] == true,
  );

  final List<ToolContent> content;
  final Map<String, Object?>? structuredContent;
  final bool isError;

  /// The words of every [ToolText], one per line.
  String get text =>
      content.whereType<ToolText>().map((t) => t.text).join('\n');

  /// The protocol's result object.
  Map<String, Object?> toJson() => <String, Object?>{
    'content': <Object?>[for (final c in content) c.toJson()],
    'structuredContent': ?structuredContent,
    if (isError) 'isError': true,
  };
}

Map<String, Object?>? _object(Object? value) => switch (value) {
  final Map<String, Object?> m => m,
  final Map<Object?, Object?> m => m.cast<String, Object?>(),
  _ => null,
};
