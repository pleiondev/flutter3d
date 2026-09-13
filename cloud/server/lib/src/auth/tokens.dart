/// Secrets the service hands out and later recognises.
///
/// A session cookie, a link in a verification letter and a download link the
/// viewer is given are the same thing three times: something random enough that
/// it cannot be guessed, stored as its own hash so that reading the database
/// does not hand anybody a working one.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A fresh secret, 32 bytes from the platform's secure source, in the
/// URL-shaped alphabet a cookie and a link both accept.
String newToken([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = Uint8List.fromList([for (var i = 0; i < 32; i++) source.nextInt(256)]);
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// What goes in the database in place of [token].
///
/// SHA-256 without a salt on purpose: the input is 256 random bits, so there is
/// no dictionary to defend against and a per-row salt would only stop the
/// lookup this service needs to do.
List<int> tokenDigest(String token) => sha256.convert(utf8.encode(token)).bytes;

/// Compares two digests in time that does not depend on where they differ.
bool sameDigest(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  return a.indexed.fold(0, (acc, e) => acc | (e.$2 ^ b[e.$1])) == 0;
}
