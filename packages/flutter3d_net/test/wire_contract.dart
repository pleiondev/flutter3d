/// `api/flutter3d_net.wire`, read for the tests that hold the code and the
/// golden messages to it.
library;

import 'dart:io';

import 'package:test/test.dart';

/// One block of the wire snapshot: a message or a relay address.
final class WireBlock {
  WireBlock(this.kind, this.name);

  /// `message` or `address`.
  final String kind;
  final String name;

  /// What tells a message apart: key to value, `*` for any value.
  final Map<String, String> tags = <String, String>{};

  /// The keys (a message's) or query parameters (an address's) it always
  /// carries, and those it may.
  final Set<String> required = <String>{};
  final Set<String> optional = <String>{};

  Set<String> get keys => <String>{...required, ...optional};
}

/// The snapshot's protocol line and its blocks, by name.
({String protocol, Map<String, WireBlock> blocks}) readWire([
  String path = 'api/flutter3d_net.wire',
]) {
  var protocol = '';
  final blocks = <String, WireBlock>{};
  WireBlock? current;
  for (final line in File(path).readAsLinesSync()) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final words = line.trim().split(' ');
    if (!line.startsWith(' ')) {
      switch (words) {
        case ['protocol', final String version]:
          protocol = version;
        case [final String kind, final String name]:
          current = blocks[name] = WireBlock(kind, name);
      }
      continue;
    }
    final block = current;
    if (block == null) continue;
    switch (words) {
      case ['tag', final String pair]:
        final cut = pair.indexOf('=');
        block.tags[pair.substring(0, cut)] = pair.substring(cut + 1);
      case ['key' || 'query', final String name]:
        block.required.add(name);
      case ['key' || 'query', final String name, 'optional']:
        block.optional.add(name);
    }
  }
  return (protocol: protocol, blocks: blocks);
}

/// What is wrong with [message] as the snapshot's [block]: a tag missing
/// or different, a key it always carries absent, or a key it never
/// declared. Empty when it is that message.
List<String> wireProblems(WireBlock block, Map<String, Object?> message) => [
  for (final MapEntry(:key, :value) in block.tags.entries)
    if (!message.containsKey(key) || value != '*' && message[key] != value)
      'tag $key is ${message[key]}, the snapshot says $value',
  for (final key in block.required)
    if (!message.containsKey(key)) 'key $key is missing',
  for (final key in message.keys)
    if (!block.tags.containsKey(key) && !block.keys.contains(key))
      'key $key is in no line of the snapshot',
];

/// Expects [message] to be the snapshot's message [name].
void expectOnTheWire(Map<String, Object?> message, String name) {
  final block = readWire().blocks[name];
  expect(block, isNotNull, reason: 'the snapshot has no message $name');
  expect(wireProblems(block!, message), isEmpty, reason: '$name: $message');
}
