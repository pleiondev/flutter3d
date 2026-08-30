/// Minutes and seconds.
///
///     flutter test test/clock_text_test.dart
///
/// Two games had written this, and between them they had every part of it.
library;

import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a time is minutes and padded seconds', () {
    expect(clockText(0.4), '0:00');
    expect(clockText(9.0), '0:09');
    expect(clockText(61.5), '1:01');
    expect(clockText(3599.0), '59:59');
    expect(clockText(3600.0), '60:00', reason: 'an hour is not a third field');
  });

  test('and the thousandths are the margin a lap is won by', () {
    expect(clockText(61.5, thousandths: true), '1:01.500');
    expect(clockText(9.007, thousandths: true), '0:09.007');
  });

  test('and a millisecond carries into the second rather than overflowing', () {
    // **The one that bites, and it has two halves that pull opposite ways.**
    // 9.007 is 9.006999… in binary, so a fraction taken after the split floors
    // to `006` and the clock reads a thousandth fast. And 59.9996 rounds to
    // `1000` thousandths, which prints as `0:59.1000` — a time nobody drove, in
    // a field meant to be four characters wide. The racing game had the second
    // of those.
    expect(clockText(59.9996, thousandths: true), '1:00.000');
    expect(clockText(59.9996, thousandths: true).length, 8);
    expect(clockText(119.9999, thousandths: true), '2:00.000');
  });

  test('a time that has not happened is not a time of nought', () {
    // A lap nobody has driven is not a lap driven in no time, and a `0:00.000`
    // on the board is a record somebody has to beat.
    expect(clockText(null, thousandths: true), '--:--.---');
    expect(clockText(0.0, thousandths: true), '--:--.---');
    expect(clockText(-1.0), '-:--');
    expect(clockText(double.nan), '-:--', reason: 'a not-a-number printed');
    expect(clockText(double.infinity), '-:--');
  });

  test('and a caller can say what nothing looks like', () {
    // The platformer shows a run's clock from its first frame, where nought
    // seconds is the truth rather than the absence of an answer.
    expect(clockText(0.0, none: '0:00'), '0:00');
  });
}
