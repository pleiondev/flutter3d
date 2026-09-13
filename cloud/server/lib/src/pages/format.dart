/// Numbers and dates as a person reads them on a card.
library;

/// `1234567` as `1,234,567`.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final grouped = [
    for (var i = 0; i < digits.length; i++) ...[
      if (i > 0 && (digits.length - i) % 3 == 0) ',',
      digits[i],
    ],
  ].join();
  return value < 0 ? '-$grouped' : grouped;
}

/// `2026-09-11`, in UTC, because the server does not know the reader's zone and
/// a date that silently shifts by one depending on who looks is worse than one
/// that says which zone it is in.
String isoDate(DateTime moment) {
  final utc = moment.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
}

String plural(int count, String one, [String? many]) =>
    '${groupDigits(count)} ${count == 1 ? one : (many ?? '${one}s')}';
