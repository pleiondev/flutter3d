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
Future<({Map<String, Object?>? json, String? refused})> callGameExtension(
  String vmService,
  String method, {
  Map<String, String> args = const <String, String>{},
  ConnectVmService connect = connectVmService,
}) async {
  final VmService service;
  try {
    service = await connect(vmService);
  } on Object catch (error) {
    return (json: null, refused: 'could not reach $vmService: $error');
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
        return (
          json: response.json ?? const <String, Object?>{},
          refused: null,
        );
      } on RPCError catch (error) {
        return (json: null, refused: error.details ?? error.message);
      }
    }
    return (
      json: null,
      refused: 'the running game answers no $method: it never registered it',
    );
  } finally {
    await service.dispose();
  }
}
