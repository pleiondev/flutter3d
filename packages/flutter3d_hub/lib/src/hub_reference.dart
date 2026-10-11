import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

/// One version of one model on the hub: `<uuid>@<n>`, optionally followed
/// by `#sha256=<64 lowercase hex digits>` to check the bytes against.
///
/// ```text
/// 0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3
/// 0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3#sha256=e3b0c442…b855
/// ```
///
/// **Fixed for good.** A reference is written into other people's code, levels
/// and lesson files and stays there for years, so the format has no version of
/// its own and never gains one: a text this parser accepts today it accepts in
/// every later release, with the same meaning, and a text it refuses today
/// stays refused. A later need is met beside it, never by widening it.
///
/// - The UUID names the model and never changes. It is written in its
///   canonical form: 36 characters, lowercase hexadecimal, hyphens after the
///   8th, 12th, 16th and 20th digit. Uppercase is refused rather than
///   folded, so one model has one spelling and one cache key. Its version
///   nibble is not checked: the hub hands out whatever version it mints.
/// - The number after `@` is the model's version on the hub, from 1, in
///   decimal with no sign and no leading zero, at most 2147483647 (a 32-bit
///   signed integer, which every platform, the web included, holds
///   exactly). A version once published is immutable on the server, so a
///   reference without a checksum still names exactly one file.
/// - The checksum, when it is there, is the SHA-256 of the file as served,
///   and a client refuses bytes that do not match it with
///   `HubRefusal.hashMismatch`. It is how a reference keeps meaning one file
///   even against a mirror the author does not control.
///
/// No whitespace anywhere, no prefix (`hub:`), no braces. [parse] is the
/// one function that reads the format; everything that holds a reference as
/// text goes through it.
final class HubReference {
  /// A reference from its parts, held to the same rules as [parse].
  ///
  /// Throws a [HubReferenceFormatException] for a part [parse] would refuse.
  factory HubReference({
    required String uuid,
    required int version,
    String? sha256,
  }) {
    final text =
        '$uuid@$version${sha256 == null ? '' : '$_checksumMark$sha256'}';
    _checkUuid(uuid, text);
    if (version < 1) {
      throw HubReferenceFormatException(
        text,
        'its version is $version, and a version starts at 1',
      );
    }
    if (version > maxVersion) {
      throw HubReferenceFormatException(
        text,
        'its version is $version, and a version is at most $maxVersion',
      );
    }
    if (sha256 != null) _checkSha256(sha256, text);
    return HubReference._(uuid, version, sha256);
  }

  const HubReference._(this.uuid, this.version, this.sha256);

  /// Reads [text] as a reference.
  ///
  /// Throws a [HubReferenceFormatException] whose message says what is wrong
  /// with it, in a sentence, for anything that is not exactly a reference.
  static HubReference parse(String text) {
    if (text.isEmpty) {
      throw HubReferenceFormatException(text, 'it is empty');
    }
    if (text.contains(RegExp(r'\s'))) {
      throw HubReferenceFormatException(
        text,
        'it contains whitespace, which no reference has',
      );
    }
    final hash = text.indexOf('#');
    final body = hash < 0 ? text : text.substring(0, hash);
    String? sha256;
    if (hash >= 0) {
      final checksum = text.substring(hash);
      if (!checksum.startsWith(_checksumMark)) {
        throw HubReferenceFormatException(
          text,
          'a checksum is written #sha256= and 64 lowercase hexadecimal '
          'digits, and this one starts "$checksum"',
        );
      }
      sha256 = checksum.substring(_checksumMark.length);
      _checkSha256(sha256, text);
    }
    final at = body.indexOf('@');
    if (at < 0) {
      throw HubReferenceFormatException(
        text,
        'it has no version: a reference is <uuid>@<n>',
      );
    }
    final uuid = body.substring(0, at);
    final number = body.substring(at + 1);
    _checkUuid(uuid, text);
    if (number.isEmpty) {
      throw HubReferenceFormatException(
        text,
        'it has no version after "@": a reference is <uuid>@<n>',
      );
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(number)) {
      throw HubReferenceFormatException(
        text,
        'its version "$number" is not a decimal number from 1',
      );
    }
    if (number.length > 1 && number.startsWith('0')) {
      throw HubReferenceFormatException(
        text,
        'its version "$number" has a leading zero, so one version would '
        'have two spellings',
      );
    }
    // Compared as text first, so a number too long for an int on any
    // platform is refused rather than wrapped.
    if (number.length > _maxVersionText.length ||
        (number.length == _maxVersionText.length &&
            number.compareTo(_maxVersionText) > 0)) {
      throw HubReferenceFormatException(
        text,
        'its version $number is past the last one a reference can name: a '
        'version is at most $maxVersion',
      );
    }
    final version = int.parse(number);
    if (version == 0) {
      throw HubReferenceFormatException(
        text,
        'its version is 0, and a version starts at 1',
      );
    }
    return HubReference._(uuid, version, sha256);
  }

  /// [parse], with null instead of the exception.
  static HubReference? tryParse(String text) {
    try {
      return parse(text);
    } on HubReferenceFormatException {
      return null;
    }
  }

  /// The format in one line, as a refusal or a help text names it.
  static const String formatDescription =
      '<uuid>@<n>, optionally followed by #sha256=<64 lowercase hex digits>';

  /// The largest version a reference can name: 2³¹ − 1.
  static const int maxVersion = 2147483647;

  static const String _maxVersionText = '2147483647';
  static const String _checksumMark = '#sha256=';

  /// The model, as the hub named it when it was first published: a UUID in
  /// its canonical lowercase form.
  final String uuid;

  /// The model's version on the hub, from 1. Immutable on the server.
  final int version;

  /// The SHA-256 of the file as served, as 64 lowercase hexadecimal digits;
  /// null when the reference does not carry one.
  final String? sha256;

  /// The same model and version, with no checksum to check.
  HubReference get withoutChecksum =>
      sha256 == null ? this : HubReference._(uuid, version, null);

  @override
  bool operator ==(Object other) =>
      other is HubReference &&
      other.uuid == uuid &&
      other.version == version &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(uuid, version, sha256);

  /// The reference as text, exactly as [parse] reads it.
  @override
  String toString() =>
      '$uuid@$version${sha256 == null ? '' : '$_checksumMark$sha256'}';

  static final RegExp _uuidShape = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  static void _checkUuid(String uuid, String text) {
    if (!_uuidShape.hasMatch(uuid)) {
      throw HubReferenceFormatException(
        text,
        '"$uuid" is not a UUID in its canonical form '
        '(xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)',
      );
    }
    if (uuid != uuid.toLowerCase()) {
      throw HubReferenceFormatException(
        text,
        'its UUID is written in uppercase, and a reference spells it in '
        'lowercase so one model has one spelling',
      );
    }
    if (uuid == '00000000-0000-0000-0000-000000000000') {
      throw HubReferenceFormatException(
        text,
        'its UUID is the nil UUID, which names no model',
      );
    }
  }

  static void _checkSha256(String sha256, String text) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw HubReferenceFormatException(
        text,
        'its checksum is not 64 lowercase hexadecimal digits',
      );
    }
  }
}

/// A text that is not a hub reference — [HubReference.parse]'s refusal.
final class HubReferenceFormatException extends Flutter3dFormatException {
  /// [source] refused, and [reason] why, as a clause.
  const HubReferenceFormatException(this.source, this.reason);

  /// The text that was refused.
  @override
  final String source;

  /// What is wrong with it, as a clause the [message] completes.
  final String reason;

  @override
  String get message =>
      '"$source" is not a hub reference: $reason. A reference is '
      '${HubReference.formatDescription}.';

  @override
  String toString() => 'HubReferenceFormatException: $message';
}
