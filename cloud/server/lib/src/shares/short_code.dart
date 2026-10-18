/// N10: codes a person types or reads aloud, taken from a bundle's address.
library;

/// Crockford's base 32: no I, L, O or U, so nothing reads as a digit it is
/// not, and nothing spells much by accident.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// The shortest code handed out. Seven characters are 35 bits: with a
/// million bundles filed, a new one lands on a taken code about once in
/// thirty-four thousand, and when it does it takes an eighth character rather
/// than the other bundle's code.
const int shortestCode = 7;

/// As long as a SHA-256 goes: 256 bits are 51 whole characters of five.
const int longestCode = 256 ~/ 5;

/// The first [length] characters of [address] (hex SHA-256) in base 32.
///
/// **Derived, not drawn.** The same bundle shared twice gets the same code
/// without a lookup, and a code says nothing a stranger could not already
/// compute from the bytes.
String codeOf(String address, int length) {
  final bits = <String>[
    for (final digit in address.split(''))
      int.parse(digit, radix: 16).toRadixString(2).padLeft(4, '0'),
  ].join();
  return <String>[
    for (var i = 0; i < length; i++)
      _alphabet[int.parse(bits.substring(i * 5, i * 5 + 5), radix: 2)],
  ].join();
}

/// Every code [address] may be filed under, shortest first: the next one is
/// tried only when a different bundle already holds the one before.
Iterable<String> codesOf(String address) => Iterable<String>.generate(
  longestCode - shortestCode + 1,
  (int extra) => codeOf(address, shortestCode + extra),
);

/// [typed] as a code is stored: upper case, with the letters Crockford
/// reads as digits read as those digits, and dashes and spaces dropped, since
/// people group codes when they copy them. Null when it cannot be a code.
String? normaliseCode(String typed) {
  final upper = typed
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (upper.length < shortestCode || upper.length > longestCode) return null;
  return upper.split('').every(_alphabet.contains) ? upper : null;
}
