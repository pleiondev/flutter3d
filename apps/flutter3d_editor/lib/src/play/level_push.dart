/// `HR3`'s editor half: a saved level, sent to the game running it.
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// The parameters `ext.flutter3d.level.apply` takes for [document]: the text
/// as saved, and the digest of the level it parses to.
///
/// The digest is taken from the parsed level, not from the text, because the
/// game computes it the same way from what it receives: two documents that
/// differ only in whitespace are the same level and digest the same.
Map<String, String> levelApplyArguments(String document) => <String, String>{
  'document': document,
  'hash': Level.fromJson(
    jsonDecode(document) as Map<String, Object?>,
  ).digestHex,
};

/// What the game said it did with a level, in a line for the status strip.
String describeLevelApplied(Map<String, Object?> answer) {
  final diff = answer['diff'] as Map<String, Object?>? ?? const {};
  final simulation = (diff['simulation'] as List<Object?>? ?? const [])
      .cast<String>();
  return switch (answer) {
    {'swappedAt': final int step} =>
      'the game replayed from step $step with the new '
          '${simulation.join(', ')}',
    {'rebuiltInPlace': true} =>
      'the game rebuilt ${simulation.join(', ')} in place '
          '(it has no timeline to replay)',
    _ when simulation.isEmpty && diff.values.every(_unchanged) =>
      'the game already had this level',
    _ => 'the game took the new look',
  };
}

bool _unchanged(Object? value) => switch (value) {
  false => true,
  final List<Object?> list => list.isEmpty,
  _ => false,
};

/// Sends [document] to the game whose VM service is at [vmService], to the
/// isolate that answers `ext.flutter3d.level.apply`.
///
/// Throws when no isolate there has registered it: a game that never called
/// `registerLevelExtension` cannot take a level, and saying so is better
/// than a silence the person reads as "sent".
Future<Map<String, Object?>> pushLevel(
  String vmService,
  String document,
) async {
  const method = 'ext.flutter3d.level.apply';
  final service = await vmServiceConnectUri(vmService);
  try {
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      if (!(isolate.extensionRPCs ?? const <String>[]).contains(method)) {
        continue;
      }
      final response = await service.callServiceExtension(
        method,
        isolateId: ref.id,
        args: levelApplyArguments(document),
      );
      return response.json ?? const <String, Object?>{};
    }
    throw StateError(
      'the running game does not take levels: nothing registered $method',
    );
  } finally {
    await service.dispose();
  }
}
