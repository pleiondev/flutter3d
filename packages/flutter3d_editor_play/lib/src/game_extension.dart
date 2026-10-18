import 'package:vm_service/vm_service.dart';

import 'vm_connect.dart';

/// Asks the game whose VM service is at [vmService] for [method] — an
/// `ext.flutter3d.*` extension it registered — with string [args], and
/// answers what it said, or what stopped it.
///
/// The isolate is found by what it registered rather than assumed to be the
/// first: a game with a worker isolate has two, and only one of them draws.
///
/// **Answers rather than throws.** An agent reading the answer needs the
/// game's own sentence — "there is no draw 40: this frame described 12" —
/// which arrives as an `RPCError`'s details; a game that registered nothing
/// of the name, or one that cannot be reached, is a sentence too.
Future<GameExtensionReply> callGameExtension(
  String vmService,
  String method, {
  Map<String, String> args = const <String, String>{},
  ConnectVmService connect = connectVmService,
}) async {
  final VmService service;
  try {
    service = await connect(vmService);
  } on Object catch (error) {
    return GameExtensionReply(refused: 'could not reach $vmService: $error');
  }
  try {
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      if (!(isolate.extensionRPCs ?? const <String>[]).contains(method)) {
        continue;
      }
      try {
        final response = await service.callServiceExtension(
          method,
          isolateId: ref.id,
          args: args,
        );
        return GameExtensionReply(
          json: response.json ?? const <String, Object?>{},
        );
      } on RPCError catch (error) {
        return GameExtensionReply(refused: error.details ?? error.message);
      }
    }
    return GameExtensionReply(
      refused: 'the running game answers no $method: it never registered it',
    );
  } finally {
    await service.dispose();
  }
}

/// What [callGameExtension] answers: the extension's JSON reply, or the
/// sentence that stopped it. Exactly one of the two is set.
final class GameExtensionReply {
  /// A reply; give [json] for an answer or [refused] for a refusal, not
  /// both.
  const GameExtensionReply({this.json, this.refused});

  /// What the extension answered, decoded; null when it was refused.
  final Map<String, Object?>? json;

  /// Why there is no answer — the game's own sentence, or why the game
  /// could not be asked; null when it answered.
  final String? refused;

  @override
  bool operator ==(Object other) =>
      other is GameExtensionReply &&
      other.refused == refused &&
      _sameJson(other.json, json);

  @override
  int get hashCode => Object.hash(refused, switch (json) {
    final Map<String, Object?> json => Object.hashAllUnordered(json.keys),
    null => null,
  });

  @override
  String toString() => refused == null
      ? 'GameExtensionReply($json)'
      : 'GameExtensionReply(refused: $refused)';
}

/// Whether two decoded JSON values hold the same thing, maps and lists
/// compared entry by entry.
bool _sameJson(Object? a, Object? b) => switch ((a, b)) {
  (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
    a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key])),
  (final List<Object?> a, final List<Object?> b) =>
    a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _sameJson(a[i], b[i])),
  _ => a == b,
};
