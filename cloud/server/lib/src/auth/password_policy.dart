/// What a password has to be, decided in one place.
///
/// **Two ways to be strong enough, because people make passwords two ways.** A
/// short password has to mix kinds of character — at ten characters that mix is
/// what stands between it and a dictionary. A long one does not: four ordinary
/// words are harder to guess than `Password1!`, which satisfies every
/// composition rule ever written and is on every list an attacker starts with.
/// So under [passphraseLength] characters three kinds out of four are required,
/// and from it on length is enough.
///
/// On top of either, the passwords that are weak however they are counted: the
/// ones on common lists, keyboard runs, one character repeated, and the
/// person's own address or name.
///
/// The server is the only judge. `assets/password.js` shows the first three
/// rules while somebody types, and a browser without it still gets every rule
/// here, in a sentence.
library;

/// The shortest password accepted at all.
const minPasswordLength = 10;

/// From this length on, mixing kinds of character is not required.
const passphraseLength = 16;

/// Long enough for any passphrase, short enough that hashing it is not a way to
/// make the server work.
const maxPasswordLength = 1024;

/// The rules as one sentence, for the hint under a password field.
const passwordRules =
    'At least $minPasswordLength characters, mixing three of: lowercase, '
    'uppercase, digits, symbols. Or $passphraseLength characters or more with '
    'no mixing needed — a few words work well.';

const _mixSentence =
    'Mix at least three of lowercase, uppercase, digits and symbols — or make it '
    '$passphraseLength characters or longer.';

/// Everything wrong with [password], as sentences. Empty when it is acceptable.
///
/// [email] and [displayName] are the account's own, so that a password made of
/// them is refused: they are the first thing anybody who knows the person tries.
List<String> passwordProblems(
  String password, {
  String? email,
  String? displayName,
}) {
  final length = password.runes.length;
  if (length < minPasswordLength) {
    return ['Use at least $minPasswordLength characters.'];
  }
  if (length > maxPasswordLength) {
    return [
      'That password is too long; keep it under $maxPasswordLength characters.',
    ];
  }

  final lower = password.toLowerCase();
  final compact = lower.replaceAll(RegExp(r'\s+'), '');
  final letters = lower.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');

  final personal = [
    if (email != null) email.split('@').first.toLowerCase(),
    if (displayName != null) ...displayName.toLowerCase().split(RegExp(r'\s+')),
  ].where((part) => part.runes.length >= 4);

  return [
    if (length < passphraseLength && _kindsIn(password) < 3) _mixSentence,
    if (password.runes.toSet().length < 5)
      'Too repetitive: use more different characters.',
    if (_isRun(compact))
      'That is a keyboard or alphabet sequence, which is among the first things tried.',
    if (_common.contains(lower) ||
        _common.contains(compact) ||
        _commonStems.contains(letters))
      'That password is on lists of the most common ones.',
    if (personal.any(lower.contains))
      'Leave your address and your name out of the password.',
  ];
}

/// Lowercase letters, uppercase letters, digits, and everything else.
int _kindsIn(String password) => [
  RegExp(r'\p{Ll}', unicode: true),
  RegExp(r'\p{Lu}', unicode: true),
  RegExp(r'\p{Nd}', unicode: true),
  RegExp(r'[^\p{L}\p{Nd}]', unicode: true),
].where((kind) => kind.hasMatch(password)).length;

/// Whether [compact] is a run along a row of a keyboard or the alphabet, either
/// way round, or several such runs stuck together (`1234567890qwerty`).
bool _isRun(String compact) {
  const rows = [
    'abcdefghijklmnopqrstuvwxyz',
    '01234567890',
    'qwertyuiopasdfghjklzxcvbnm',
    '1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p',
    'йцукенгшщзхъфывапролджэячсмитьбю',
  ];
  final runs = [
    for (final row in rows) ...[row, row.split('').reversed.join()],
  ];
  var rest = compact;
  // Peel the longest run off the front until nothing is left or nothing fits.
  while (rest.isNotEmpty) {
    final taken = [
      for (final run in runs)
        for (var size = rest.length; size >= 3; size--)
          if (run.contains(rest.substring(0, size))) size,
    ].fold(0, (best, size) => size > best ? size : best);
    if (taken == 0) return false;
    rest = rest.substring(taken);
  }
  return true;
}

/// Passwords of ten characters or more that turn up at the top of every leaked
/// list. Short on purpose: the length and mixing rules already refuse the
/// shorter entries of those lists, and this is for the ones that slip past.
const _common = {
  'password123',
  'password1234',
  'password12345',
  'p@ssw0rd123',
  'passw0rd123',
  'password1!',
  'password123!',
  'qwerty12345',
  'qwerty123456',
  'qwertyuiop1',
  'iloveyou123',
  'princess123',
  'football123',
  'baseball123',
  'sunshine123',
  'superman123',
  'starwars123',
  'welcome123',
  'welcome1234',
  'letmein123',
  'admin12345',
  'administrator',
  'changeme123',
  'monkey12345',
  'dragon12345',
  'master12345',
  'trustno1234',
  '123456789a',
  'a123456789',
  'abc1234567',
  'zaq12wsxcde',
  'qazwsxedc123',
  'asdfghjkl1',
  '1q2w3e4r5t6y',
  'q1w2e3r4t5y6',
  'correct horse battery staple',
  'correcthorsebatterystaple',
  'flutter3dmodels',
};

/// The words those lists are built from. A password whose letters are only one
/// of these — `Password2024!`, `Qwerty!!1234` — is that word with decoration,
/// and the decoration is exactly what cracking rules add.
const _commonStems = {
  'password',
  'passw',
  'qwerty',
  'qwertyuiop',
  'letmein',
  'welcome',
  'admin',
  'iloveyou',
  'monkey',
  'dragon',
  'football',
  'baseball',
  'sunshine',
  'princess',
  'master',
  'shadow',
  'superman',
  'starwars',
  'trustno',
  'changeme',
  'abc',
  'pa',
  'pass',
  'passwd',
  'secret',
  'login',
  'hello',
  'freedom',
  'whatever',
};
