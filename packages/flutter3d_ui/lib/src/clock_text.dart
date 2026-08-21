/// Minutes and seconds, which is how a time is read rather than how it is
/// counted.
///
/// **Two games had written this**, and between them they had every part of it:
/// the platformer's `clock` floors to the second, because a run's total is read
/// at a glance and a flickering third decimal is noise; the racing game's
/// `formatLapTime` keeps thousandths, because that is the margin a lap is won
/// by, and prints `--:--.---` when there is no time yet rather than a
/// convincing `0:00.000`.
///
/// Both are right for their game, which is why the shape is a parameter rather
/// than a choice made here. What is shared is the part nobody should write
/// twice: the minute, the padding, and what to do with a negative.
///
/// [thousandths] adds the fraction. [none] is what a time that has not happened
/// yet reads as — a nought is a lie, and a lap nobody has driven is not a lap
/// driven in no time.
String clockText(
  double? seconds, {
  bool thousandths = false,
  String? none,
}) {
  if (seconds == null || seconds <= 0.0 || !seconds.isFinite) {
    return none ?? (thousandths ? '--:--.---' : '-:--');
  }
  if (!thousandths) {
    // Floored: a clock counting up should not read 1:00 while the second hand
    // is still on 59.
    final whole = seconds.floor();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
  }
  // **Rounded to the millisecond first, then split.** Splitting first and
  // rounding the fraction is what the racing game did, and it has two faults
  // that pull opposite ways: 9.007 seconds is 9.006999… in binary, so the
  // fraction floors to `006` and the display is a thousandth fast; and 59.9996
  // rounds to `1000`, which prints as `0:59.1000` — a time nobody drove, in a
  // field meant to be four characters wide. Carrying the millisecond into the
  // second is the only version that has neither.
  final total = (seconds * 1000).round();
  final minutes = total ~/ 60000;
  final rest = total % 60000;
  return '$minutes:${(rest ~/ 1000).toString().padLeft(2, '0')}'
      '.${(rest % 1000).toString().padLeft(3, '0')}';
}
