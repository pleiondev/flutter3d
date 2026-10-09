import 'dart:math' as math;

final math.Random _secureRandom = math.Random.secure();

/// A random RFC 4122 version-4 UUID, formatted the way an xAPI `Statement`'s
/// `id` (and an LRS's `statementId` query parameter) must be.
///
/// No `uuid` dependency, the same reasoning `random_token.dart` gives: this
/// is the version and variant bits set on sixteen random bytes, not an
/// algorithm worth a package for.
String generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xxxxxx
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
