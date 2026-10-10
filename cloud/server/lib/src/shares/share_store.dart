/// Where shared levels are kept, as the service needs them.
///
/// **The bytes as this server wrote them, not as they were sent.** A bundle is
/// read, checked and written again by `ShareBundle.toJson`, and those bytes
/// are what is kept and what the address is the SHA-256 of — so the same
/// level shared twice with its keys in another order is one row, and what a
/// code opens is byte for byte what its address names.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show ShareStatus;

import 'short_code.dart';

/// One report against a shared level.
final class ShareReport {
  const ShareReport({required this.reason, required this.at});

  final String reason;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
    'reason': reason,
    'at': at.toUtc().toIso8601String(),
  };
}

/// What is known about a shared level without opening it.
final class ShareRecord {
  const ShareRecord({
    required this.code,
    required this.address,
    required this.game,
    required this.levelHash,
    required this.title,
    required this.hasRun,
    required this.createdAt,
    required this.status,
    this.note,
    this.reports = const <ShareReport>[],
  });

  /// The short code handed out, as [normaliseCode] writes it.
  final String code;

  /// The SHA-256 of the kept bytes, hex.
  final String address;

  final String game;
  final String levelHash;
  final String? title;
  final bool hasRun;
  final DateTime createdAt;
  final ShareStatus status;

  /// Why a moderator decided as they did; what a removed code answers with.
  final String? note;

  /// Reports not yet answered by a moderator publishing it again.
  final List<ShareReport> reports;

  ShareRecord copyWith({
    ShareStatus? status,
    String? note,
    List<ShareReport>? reports,
  }) => ShareRecord(
    code: code,
    address: address,
    game: game,
    levelHash: levelHash,
    title: title,
    hasRun: hasRun,
    createdAt: createdAt,
    status: status ?? this.status,
    note: note ?? this.note,
    reports: reports ?? this.reports,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'address': address,
    'game': game,
    'levelHash': levelHash,
    if (title != null) 'title': title,
    'hasRun': hasRun,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    if (note != null) 'note': note,
    'reports': <Object?>[for (final report in reports) report.toJson()],
  };
}

/// A level about to be filed: everything but its code, which the store picks.
final class NewShare {
  const NewShare({
    required this.address,
    required this.bundle,
    required this.game,
    required this.levelHash,
    required this.title,
    required this.hasRun,
    required this.status,
    required this.createdAt,
  });

  final String address;

  /// The bundle as this server wrote it — the text [address] is the hash of.
  final String bundle;

  final String game;
  final String levelHash;
  final String? title;
  final bool hasRun;
  final ShareStatus status;
  final DateTime createdAt;
}

abstract interface class ShareStore {
  /// Files [share] under the first of [codesOf] its address that no other
  /// bundle holds, and answers the record with whether it is new. A share
  /// whose address is filed already answers that record, untouched — its
  /// status included, so sharing a removed level again does not reopen it.
  Future<({ShareRecord record, bool created})> file(NewShare share);

  /// The record filed under [code], as [normaliseCode] wrote it.
  Future<ShareRecord?> byCode(String code);

  /// The kept bytes behind [code], as text.
  Future<String?> bundleText(String code);

  /// Adds [report] to [code] and, when that makes [reportsToHide] reports
  /// against a published level, sends it back to pending — in one step, so
  /// two reports at once cannot both miss the threshold.
  Future<ShareRecord?> report(
    String code,
    ShareReport report, {
    required int reportsToHide,
  });

  /// A moderator's decision. Publishing answers the reports that sent it to
  /// review, and they are dropped; leaving them would send it straight back
  /// at the next one.
  Future<ShareRecord?> decide(String code, ShareStatus status, String? note);

  /// What a moderator should look at — pending, or reported — oldest first.
  Future<List<ShareRecord>> queue({required int limit});
}

/// A store in memory: the tests', and a server's that keeps nothing past a
/// restart.
///
/// Every method finishes without yielding between its read and its write, so
/// in one isolate nothing interleaves inside one.
final class MemoryShareStore implements ShareStore {
  final Map<String, ShareRecord> records = <String, ShareRecord>{};
  final Map<String, String> bundles = <String, String>{};

  @override
  Future<({ShareRecord record, bool created})> file(NewShare share) async {
    final known = records.values
        .where((record) => record.address == share.address)
        .firstOrNull;
    if (known != null) return (record: known, created: false);
    final code = codesOf(
      share.address,
    ).firstWhere((code) => !records.containsKey(code));
    final record = ShareRecord(
      code: code,
      address: share.address,
      game: share.game,
      levelHash: share.levelHash,
      title: share.title,
      hasRun: share.hasRun,
      createdAt: share.createdAt,
      status: share.status,
    );
    records[code] = record;
    bundles[code] = share.bundle;
    return (record: record, created: true);
  }

  @override
  Future<ShareRecord?> byCode(String code) async => records[code];

  @override
  Future<String?> bundleText(String code) async => bundles[code];

  @override
  Future<ShareRecord?> report(
    String code,
    ShareReport report, {
    required int reportsToHide,
  }) async {
    final record = records[code];
    if (record == null) return null;
    final reports = <ShareReport>[...record.reports, report];
    final hidden =
        record.status == ShareStatus.published &&
        reports.length >= reportsToHide;
    return records[code] = record.copyWith(
      reports: reports,
      status: hidden ? ShareStatus.pending : null,
    );
  }

  @override
  Future<ShareRecord?> decide(
    String code,
    ShareStatus status,
    String? note,
  ) async {
    final record = records[code];
    if (record == null) return null;
    return records[code] = ShareRecord(
      code: record.code,
      address: record.address,
      game: record.game,
      levelHash: record.levelHash,
      title: record.title,
      hasRun: record.hasRun,
      createdAt: record.createdAt,
      status: status,
      note: note,
      reports: status == ShareStatus.published
          ? const <ShareReport>[]
          : record.reports,
    );
  }

  @override
  Future<List<ShareRecord>> queue({required int limit}) async => records.values
      .where(
        (record) =>
            record.status == ShareStatus.pending || record.reports.isNotEmpty,
      )
      .take(limit)
      .toList();
}
