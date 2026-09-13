/// What a tool call did, as the servers in this repository answer it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';

/// What a tool call actually did, and the sentence to say about it.
///
/// **A refusal is an answer here, not an exception.** [resultOf] turns a
/// [did] of false into a result marked as an error, which is how an agent is
/// told to try something else rather than told nothing; an exception is
/// reported to the host as the server having failed. "Resize did nothing
/// because a light is selected" is information for whoever called, not a
/// broken server.
typedef Answer = ({bool did, String says});

/// An [Answer] with the picture a drawing tool hands back beside the sentence,
/// null for every tool that draws nothing.
typedef PictureAnswer = ({bool did, String says, Uint8List? png});

/// [answer] as a tool result: the sentence, marked as an error when it is a
/// refusal.
CallToolResult resultOf(Answer answer) => CallToolResult(
  content: <Content>[Content.text(text: answer.says)],
  isError: answer.did ? null : true,
);

/// [answer] as a tool result: the sentence, then the PNG when there is one.
CallToolResult pictureResultOf(PictureAnswer answer) => CallToolResult(
  content: <Content>[
    Content.text(text: answer.says),
    if (answer.png case final Uint8List png)
      Content.image(data: base64Encode(png), mimeType: 'image/png'),
  ],
  isError: answer.did ? null : true,
);
