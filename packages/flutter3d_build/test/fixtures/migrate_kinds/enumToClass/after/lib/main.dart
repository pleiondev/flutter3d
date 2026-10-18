import 'package:flutter3d_kinds/flutter3d_kinds.dart';

String describe(Weather w) => switch (w) {
  Weather.sun => 'bright',
  Weather.rain => 'wet',
  // TODO(flutter3d-1.0): `Weather` is not an enum or a sealed type in 1.0.0-rc.1: a `switch` over it needs a case for the values added later. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Weather-open
  _ => throw UnimplementedError(),
};

void report(Weather w) {
  switch (w) {
    case Weather.sun:
      print('sun');
    case Weather.rain:
      print('rain');
    // TODO(flutter3d-1.0): `Weather` is not an enum or a sealed type in 1.0.0-rc.1: a `switch` over it needs a case for the values added later. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Weather-open
    default:
      throw UnimplementedError();
  }
}

String safe(Weather w) => switch (w) {
  Weather.sun => 'bright',
  _ => 'other',
};
