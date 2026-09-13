/// [formatByteSize] — a byte count as a person reads it, not as a computer
/// does.
///
/// **Rounded to the unit a texture slot's own row has room for.** `170.4 КБ`
/// and `170 КБ` name the same weight to anyone deciding whether an atlas is
/// too big, and the first of those is three characters a narrow panel does not
/// have. Every tier below rounds to the nearest whole number of its own unit
/// rather than carrying a decimal place, which is also why `1023` bytes and
/// `1024` bytes read as neighbours (`1023 Б`, `1 КБ`) instead of `1023 Б` and
/// `1.0 КБ`.
library;

/// [bytes] as `"170 КБ"`, `"3 МБ"` or similar — the largest unit whose whole
/// number is at least one, capped at gigabytes because nothing this repository
/// hands to a texture slot is bigger than that.
String formatByteSize(int bytes) {
  const int kb = 1024;
  const int mb = kb * 1024;
  const int gb = mb * 1024;
  if (bytes < kb) return '$bytes Б';
  if (bytes < mb) return '${(bytes / kb).round()} КБ';
  if (bytes < gb) return '${(bytes / mb).round()} МБ';
  return '${(bytes / gb).round()} ГБ';
}
