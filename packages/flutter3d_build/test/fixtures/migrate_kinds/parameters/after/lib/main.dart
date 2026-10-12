import 'package:flutter3d_kinds/flutter3d_kinds.dart';

const Gauge plain = Gauge(2.0);
const Gauge scaled = Gauge(2.0, scale: 0.5);
final Sieve both = Sieve(coarse: 8, fine: 2);
final Sieve one = Sieve(coarse: 8);
final Sieve none = Sieve();
final Sieve named = Sieve(fine: 3);
// TODO(flutter3d-1.0): `scale:` of `Gauge` is a named argument in 1.0.0-rc.1, not a positional one. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Gauge-named
final Gauge twice = Gauge(2.0, 0.5, scale: 1);
const Tap tap = Tap(center: 2);
