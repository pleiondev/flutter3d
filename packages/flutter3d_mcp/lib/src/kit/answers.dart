/// What a tool call did, as the servers in this repository answer it.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/tools.dart';

/// What a tool call actually did, and the sentence to say about it.
///
/// **A refusal is an answer here, not an exception.** [resultOf] turns a
/// [did] of false into a result marked as an error, which is how an agent is
/// told to try something else rather than told nothing; an exception is
/// reported to the host as the server having failed. "Resize did nothing
/// because a light is selected" is information for whoever called, not a
/// broken server.
///
/// **A class, so an answer can carry more in a minor.** It was a record,
/// which never gains a field: the picture a drawing tool hands back needed
/// a second record type beside it, and every tool a plugin writes returns
/// one of these. A field added here, with a default, breaks nobody.
final class Answer {
  const Answer({required this.did, required this.says, this.png});

  /// Whether the call did what it was asked; false is a refusal.
  final bool did;

  /// The sentence to say about it, refusal or not.
  final String says;

  /// The picture a drawing tool hands back beside the sentence, PNG-encoded;
  /// null for every tool that draws nothing.
  final Uint8List? png;

  /// Equal to another answer with the same [did], [says] and [png], as the
  /// record it was compared.
  @override
  bool operator ==(Object other) =>
      other is Answer &&
      other.did == did &&
      other.says == says &&
      other.png == png;

  @override
  int get hashCode => Object.hash(did, says, png);

  @override
  String toString() => 'Answer(did: $did, says: $says)';
}

/// [answer] as a tool result: the sentence, marked as an error when it is a
/// refusal.
ToolResult resultOf(Answer answer) =>
    ToolResult.text(answer.says, isError: !answer.did);

/// [answer] as a tool result: the sentence, then the PNG when there is one.
ToolResult pictureResultOf(Answer answer) => ToolResult(
  content: <ToolContent>[
    ToolText(answer.says),
    if (answer.png case final Uint8List png) ToolImage(png),
  ],
  isError: !answer.did,
);
