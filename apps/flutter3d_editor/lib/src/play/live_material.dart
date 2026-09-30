/// `HR4`'s editor half: a material dragged in the panel, shown in the game
/// that is running before anything is saved.
library;

import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Passes on what the panel sends at most [interval] apart, merging what
/// arrives in between, and always sends the last of it.
///
/// **A drag is sixty values a second and the game wants the last one.** Each
/// is a round trip over the VM service, and a phone on the far end of a
/// cable falls behind at that rate: the colour then trails the thumb and
/// keeps changing after the hand has stopped. So the first value goes at
/// once, what comes during the next [interval] is merged by material and
/// field, and whatever is left when it ends goes then. The last value is
/// never dropped, which is the one somebody let go of the slider on.
final class ThrottledMaterials {
  ThrottledMaterials({
    required this.send,
    this.interval = const Duration(milliseconds: 33),
  });

  /// Sends one material's fields to the game.
  final Future<void> Function(String material, Map<String, Object?> fields)
  send;

  /// Thirty a second by default.
  final Duration interval;

  final Map<String, Map<String, Object?>> _pending =
      <String, Map<String, Object?>>{};
  Timer? _quiet;

  void push(String material, Map<String, Object?> fields) {
    (_pending[material] ??= <String, Object?>{}).addAll(fields);
    if (_quiet == null) _flush();
  }

  void _flush() {
    if (_pending.isEmpty) {
      _quiet = null;
      return;
    }
    final sending = Map<String, Map<String, Object?>>.of(_pending);
    _pending.clear();
    for (final MapEntry(key: material, value: fields) in sending.entries) {
      unawaited(send(material, fields));
    }
    _quiet = Timer(interval, _flush);
  }

  /// Drops what has not been sent yet.
  void dispose() {
    _quiet?.cancel();
    _quiet = null;
    _pending.clear();
  }
}

/// One VM service connection to a running game, kept for as long as the
/// panel sends to it, to call `ext.flutter3d.material.set`.
///
/// **Connected once, not per value.** `pushLevel` connects for each save,
/// which is fine for one call a save; thirty a second would spend most of
/// each on a handshake.
final class GameMaterials {
  GameMaterials(this.vmService, {this.onError});

  final String vmService;

  /// Told when a send fails, once per connection: the game has gone, or
  /// does not draw through a `SceneSurface`. Every later send in the same
  /// drag would say the same thing.
  final void Function(Object error)? onError;

  static const String method = 'ext.flutter3d.material.set';

  Future<({VmService service, String isolate})>? _link;
  bool _told = false;

  Future<void> set(String material, Map<String, Object?> fields) async {
    try {
      final (:service, :isolate) = await (_link ??= _connect());
      await service.callServiceExtension(
        method,
        isolateId: isolate,
        args: <String, String>{'name': material, 'fields': jsonEncode(fields)},
      );
    } on Object catch (error) {
      final link = _link;
      _link = null;
      unawaited(link?.then((it) => it.service.dispose()).catchError((_) {}));
      if (!_told) onError?.call(error);
      _told = true;
    }
  }

  Future<({VmService service, String isolate})> _connect() async {
    final service = await vmServiceConnectUri(vmService);
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      if ((isolate.extensionRPCs ?? const <String>[]).contains(method)) {
        return (service: service, isolate: ref.id!);
      }
    }
    await service.dispose();
    throw StateError(
      'the running game takes no live materials: nothing registered $method',
    );
  }

  Future<void> dispose() async {
    final link = _link;
    _link = null;
    if (link != null) await (await link).service.dispose();
  }
}
