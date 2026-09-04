/// A number that says whether two runs of the same simulation are the same run.
///
/// ## Why a digest and not a comparison
///
/// Two machines cannot compare their worlds by sending each other their worlds.
/// A snapshot of the crypt is tens of kilobytes and a run is thousands of
/// steps; what travels is a number per checkpoint, and the worlds are equal
/// when the numbers are. That is the shape a verifying server needs — a run is
/// submitted as its inputs, replayed, and the replay either agrees with the
/// checkpoints the client sent or it says at which step it stopped agreeing.
///
/// ## Why not `Object.hashAll` or `jsonEncode`
///
/// Neither is the same number twice. `Object.hash` is seeded per isolate by
/// design, so it differs between two runs of the same program on the same
/// machine. `jsonEncode` is stable within a platform and not across one: a
/// `double` that is a whole number prints `1.0` on the VM and the web disagrees
/// with the VM about whether `1` was ever an `int` at all, because on the web
/// it is a `double` and `1 is int` is true.
///
/// So this hashes **bits, not text**. Every number goes in as the eight bytes
/// of its IEEE-754 double, which makes `1`, `1.0` and the web's single flavour
/// of both into the same eight bytes everywhere. Nothing here can print a
/// number.
///
/// ## Why the arithmetic looks like this
///
/// FNV-1a, whose mixing step is a multiply by a 32-bit prime — and a 32-by-32
/// multiply is the one operation the web gets silently wrong, for the reason
/// [GameRandom] already carries: an `int` there is a `double`, so a product
/// wanting 64 bits keeps 53 and drops the rest without saying so. The same trap
/// cost this repository three defects that only a browser could see, all named
/// in `tool/ci.sh`.
///
/// The multiply is therefore done in halves — the low sixteen bits of the hash
/// times the prime, and the high sixteen times the prime shifted back in — and
/// every intermediate stays under 2^53, where both platforms are exact. It is
/// FNV-1a's number, arrived at by a route a browser can walk.
///
/// ## What it is not
///
/// Not cryptographic and not claimed to be. A player who wants to forge a
/// digest can, and forging it buys nothing: the server does not trust the
/// digest, it recomputes the run. The digest is what tells the honest client's
/// bug report *where* the two runs parted company.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'game_random.dart' show GameRandom;
import 'snapshot.dart' show Snapshot;

/// Folds JSON-shaped values into one 32-bit number.
///
/// The values it accepts are exactly the values a [Snapshot] may hold — `null`,
/// `bool`, `num`, `String`, `List` and `Map<String, Object?>` — because the
/// whole point is to hash what a save file holds. Anything else throws rather
/// than being skipped: a `Vector3` handed to this by mistake would otherwise
/// hash to nothing at all and two different worlds would agree.
final class StateDigest {
  StateDigest();

  /// The digest of one value, for the common case of asking once.
  static int of(Object? value) => (StateDigest()..add(value)).value;

  static const int _offsetBasis = 0x811C9DC5;
  static const int _prime = 16777619;
  static const int _wrap = 4294967296;

  int _hash = _offsetBasis;

  /// The digest so far, as an unsigned 32-bit number.
  int get value => _hash;

  /// The digest as eight hexadecimal digits, which is how it is written down.
  ///
  /// Fixed width and lower case, so a column of them in a test file lines up
  /// and a diff of two traces is read by eye.
  ///
  /// Which is who it is for: whoever is holding two traces of a run that
  /// diverged. The checks in this repository compare [value], because a number
  /// is what an assertion wants; this is the form a person reads.
  String get hex => _hash.toRadixString(16).padLeft(8, '0');

  /// Folds one value in, whatever shape it is.
  void add(Object? value) => _value(value);

  void _value(Object? value) {
    if (value == null) {
      _byte(_tagNull);
    } else if (value is bool) {
      _byte(value ? _tagTrue : _tagFalse);
    } else if (value is num) {
      _number(value);
    } else if (value is String) {
      _text(value);
    } else if (value is List) {
      // Order is meaning in a list — the third monster is the third monster —
      // so it goes in as it lies.
      _byte(_tagList);
      _length(value.length);
      for (final item in value) {
        _value(item);
      }
    } else if (value is Map) {
      _map(value);
    } else {
      throw ArgumentError.value(
        value,
        'value',
        'a digest is taken of what a snapshot may hold; '
            '${value.runtimeType} is not one of those',
      );
    }
  }

  /// **Keys sorted, because a map has no order and two runs must not depend on
  /// one.**
  ///
  /// A `Map` in Dart iterates in insertion order, and insertion order is a
  /// property of the code that built the map rather than of the state it holds.
  /// A restore that writes the same fields in a different order would otherwise
  /// read as a divergence, which is a false alarm on the one instrument whose
  /// alarms have to be believed.
  ///
  /// `String.compareTo` orders by UTF-16 code unit and does so identically on
  /// every platform, which is the property being leaned on here.
  void _map(Map<Object?, Object?> value) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw ArgumentError.value(
          key,
          'key',
          'a snapshot is a JSON document, so its keys are strings',
        );
      }
      keys.add(key);
    }
    keys.sort();
    _byte(_tagMap);
    _length(keys.length);
    for (final key in keys) {
      _text(key);
      _value(value[key]);
    }
  }

  void _text(String value) {
    _byte(_tagText);
    final bytes = utf8.encode(value);
    _length(bytes.length);
    for (final byte in bytes) {
      _byte(byte);
    }
  }

  /// A number as the eight bytes of its double, whatever kind of number it was.
  ///
  /// **The one place `int` and `double` are deliberately not told apart.** On
  /// the web they cannot be — `3` and `3.0` are one value there — so a digest
  /// that distinguished them would be a digest the web could never match, and
  /// the instrument would report a divergence on every browser for ever.
  ///
  /// NaN is written as one fixed pattern rather than as it arrived. A NaN in a
  /// simulation is already a defect, but the several bit patterns that are all
  /// NaN are not reproduced identically by two platforms' arithmetic, and a
  /// digest that varied with which NaN turned up would blame the platform for
  /// a bug in the game.
  ///
  /// **Negative zero is folded into zero, and that was measured rather than
  /// assumed.** `-0.0` written as a literal is negative on both platforms, and
  /// arithmetic that produces one produces it on both — but a `-0.0` inside a
  /// `const` structure comes out of dart2js as a plain zero, because
  /// canonicalising constants there goes through a representation with no
  /// signed zero in it. A digest that told the two apart would therefore report
  /// a divergence between the VM and a browser that no simulation had caused,
  /// on an instrument whose entire value is that its alarms can be believed.
  ///
  /// The cost, stated rather than discovered: two worlds differing only in the
  /// sign of a zero hash the same. Every IEEE operation agrees about them
  /// except division, whose result differs in sign of infinity — and every
  /// division in this repository is already gated on `Tolerance.divisor`, which
  /// refuses both zeroes alike.
  void _number(num value) {
    _byte(_tagNumber);
    final number = value == 0 ? 0.0 : value.toDouble();
    if (number.isNaN) {
      // Quiet NaN, big-endian.
      _byte(0x7F);
      _byte(0xF8);
      for (var i = 0; i < 6; i++) {
        _byte(0);
      }
      return;
    }
    _scratch.setFloat64(0, number);
    for (var i = 0; i < 8; i++) {
      _byte(_scratch.getUint8(i));
    }
  }

  /// A count, as four big-endian bytes.
  ///
  /// Written even for an empty list, so that `[]` and `[[]]` are different
  /// numbers: without a length the two flatten into the same stream of tags.
  void _length(int count) {
    _byte(count ~/ 16777216);
    _byte((count ~/ 65536) % 256);
    _byte((count ~/ 256) % 256);
    _byte(count % 256);
  }

  void _byte(int byte) {
    // Both operands under 2^32, which is the range a browser's bitwise `^` is
    // exact over.
    _hash = _multiply(_hash ^ (byte % 256));
  }

  /// `hash * prime` modulo 2^32, computed so that the web gets the same answer.
  ///
  /// The identity being used: with `h = hi * 2^16 + lo`,
  ///
  ///     h * p  mod 2^32  ==  ((hi * p mod 2^16) * 2^16 + lo * p) mod 2^32
  ///
  /// and both `hi * p` and `lo * p` are under 2^50, where a `double` still
  /// holds every integer exactly. Division and remainder are used rather than
  /// shifts and masks because the intermediates are past bit 32, which is where
  /// the browser's bitwise operators stop being the same operators.
  static int _multiply(int hash) {
    final low = hash % 65536;
    final high = (hash ~/ 65536) % 65536;
    return ((low * _prime) % _wrap + ((high * _prime) % 65536) * 65536) % _wrap;
  }

  static const int _tagNull = 0x00;
  static const int _tagFalse = 0x01;
  static const int _tagTrue = 0x02;
  static const int _tagNumber = 0x03;
  static const int _tagText = 0x04;
  static const int _tagList = 0x05;
  static const int _tagMap = 0x06;

  static final ByteData _scratch = ByteData(8);
}

/// Where two runs of the same tape parted company.
final class Divergence {
  const Divergence({
    required this.step,
    required this.expected,
    required this.found,
  });

  /// The step number of the checkpoint that disagreed.
  ///
  /// Not the step the defect is on — it is somewhere in the interval since the
  /// checkpoint before — which is the whole reason [DigestTrace.every] is a
  /// dial: a run that diverges is re-run with a finer one.
  final int step;

  /// The digest the trace was compared against, or null when the run had a
  /// checkpoint the expectation did not.
  final int? expected;

  /// The digest this run produced, or null when the run stopped early.
  final int? found;

  static String _show(int? digest) =>
      digest == null ? 'nothing' : digest.toRadixString(16).padLeft(8, '0');

  @override
  String toString() =>
      'step $step: expected ${_show(expected)}, found ${_show(found)}';
}

/// The digest of a running simulation, taken every so many steps.
///
/// **This is the instrument the whole cloud service rests on**, and the reason
/// it is written before the service: a run submitted to a server is verified by
/// replaying it, and a replay is only evidence if the same tape produces the
/// same run on the server's machine as on the player's. Whether it does is a
/// measurement, not an assumption — `dart:math`'s `sin` is a platform's libm on
/// the VM and the browser's own routine on the web, and neither IEEE 754 nor
/// the Dart specification says the two agree on the last bit.
///
/// A trace turns that from one bit of news into a location. Two traces of the
/// same tape either match, or they name the first checkpoint at which they
/// stopped matching, and the defect is between that checkpoint and the one
/// before.
final class DigestTrace {
  DigestTrace({this.every = 25})
    : assert(every > 0, 'a checkpoint every no steps is no checkpoints');

  /// How many steps pass between checkpoints.
  ///
  /// Every step would be exact and is not the default: a thousand steps of a
  /// crypt is a thousand snapshots taken, and the cost of taking one is the
  /// cost of `save()` on every body in the world. Twenty-five is fine enough
  /// that a divergence is bracketed to under half a second of play.
  final int every;

  final List<int> _steps = <int>[];
  final List<int> _digests = <int>[];

  /// The step numbers checkpointed, in order.
  List<int> get steps => List<int>.unmodifiable(_steps);

  /// The digest at each of [steps].
  List<int> get digests => List<int>.unmodifiable(_digests);

  /// The digests as eight-digit hexadecimal, which is how a trace is committed.
  List<String> get hexDigests => <String>[
    for (final digest in _digests) digest.toRadixString(16).padLeft(8, '0'),
  ];

  /// Takes a checkpoint if [step] is one, and does nothing if it is not.
  ///
  /// Called with the state **after** the step has run, so that checkpoint zero
  /// is the world one step in rather than the world as it was handed over. A
  /// trace that began before the first step would begin with a number that says
  /// only that the level loaded.
  void observe(int step, Object? state) {
    if (step % every != 0) return;
    _steps.add(step);
    _digests.add(StateDigest.of(state));
  }

  /// The first checkpoint at which this trace and [expected] disagree.
  ///
  /// Null when they agree the whole way, which is the answer the parity test
  /// wants. A trace that is shorter or longer than what it is compared against
  /// diverges at the first checkpoint one of them does not have: a run that
  /// stopped early is a divergence, not a shorter agreement.
  Divergence? divergenceFrom(List<int> expected) {
    final shared = _digests.length < expected.length
        ? _digests.length
        : expected.length;
    for (var i = 0; i < shared; i++) {
      if (_digests[i] != expected[i]) {
        return Divergence(
          step: _steps[i],
          expected: expected[i],
          found: _digests[i],
        );
      }
    }
    if (_digests.length == expected.length) return null;
    final i = shared;
    return Divergence(
      // The step the missing checkpoint would have been, which the trace
      // cannot look up because it never reached it.
      step: (i + 1) * every,
      expected: i < expected.length ? expected[i] : null,
      found: i < _digests.length ? _digests[i] : null,
    );
  }

  /// The same question against a trace written as hexadecimal.
  Divergence? divergenceFromHex(List<String> expected) => divergenceFrom(<int>[
    for (final digest in expected) int.parse(digest, radix: 16),
  ]);
}
