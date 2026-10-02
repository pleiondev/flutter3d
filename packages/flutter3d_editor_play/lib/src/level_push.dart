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

/// The parameters `ext.flutter3d.level.patch` takes to turn [base], the level
/// the game is believed to have, into [document]; null when the patch would
/// be no shorter than the document, or [base] is not a level at all.
///
/// **A guess, checked at the other end.** The editor cannot see which
/// version the game is playing — it may have been started from an older
/// file, or have refused the last save — so [base] is what the editor last
/// wrote, and the patch names its digest. A wrong guess costs one refusal and
/// the whole document after it.
Map<String, String>? levelPatchArguments(String base, String document) {
  final Level before;
  try {
    before = Level.fromJson(jsonDecode(base) as Map<String, Object?>);
  } on Object {
    return null;
  }
  final after = Level.fromJson(jsonDecode(document) as Map<String, Object?>);
  final patch = jsonEncode(LevelPatch.between(before, after));
  return patch.length < document.length
      ? <String, String>{'patch': patch}
      : null;
}

/// What the game said it did with a level, in a line for the status strip.
///
/// A level that went whole after its patch was refused says why at the end:
/// it is the one sign that the editor and the game disagreed about which
/// version was running.
String describeLevelApplied(Map<String, Object?> answer) {
  final line = _describeApplied(answer);
  return switch (answer['fellBack']) {
    final String reason => '$line (sent whole: $reason)',
    _ => line,
  };
}

String _describeApplied(Map<String, Object?> answer) {
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
/// With a [base] — the level the game is believed to be playing — what goes
/// first is the patch from it to [document] (`ext.flutter3d.level.patch`),
/// and the whole document only when the game answers that the patch is
/// stale, when it predates patches, or when the patch would be no shorter.
/// The answer then carries `fellBack`, the game's reason.
///
/// Throws when no isolate there has registered it: a game that never called
/// `registerLevelExtension` cannot take a level, and saying so is better
/// than a silence the person reads as "sent".
Future<Map<String, Object?>> pushLevel(
  String vmService,
  String document, {
  String? base,
}) async {
  const method = 'ext.flutter3d.level.apply';
  const patchMethod = 'ext.flutter3d.level.patch';
  final service = await vmServiceConnectUri(vmService);
  try {
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      final rpcs = isolate.extensionRPCs ?? const <String>[];
      if (!rpcs.contains(method)) continue;
      final patch = base == null || !rpcs.contains(patchMethod)
          ? null
          : levelPatchArguments(base, document);
      final String? fellBack;
      if (patch != null) {
        try {
          final response = await service.callServiceExtension(
            patchMethod,
            isolateId: ref.id,
            args: patch,
          );
          return response.json ?? const <String, Object?>{};
        } on RPCError catch (error) {
          if (error.code != LevelPatch.staleCode) rethrow;
          fellBack = error.details ?? error.message;
        }
      } else {
        fellBack = null;
      }
      final response = await service.callServiceExtension(
        method,
        isolateId: ref.id,
        args: levelApplyArguments(document),
      );
      return <String, Object?>{...?response.json, 'fellBack': ?fellBack};
    }
    throw StateError(
      'the running game does not take levels: nothing registered $method',
    );
  } finally {
    await service.dispose();
  }
}
