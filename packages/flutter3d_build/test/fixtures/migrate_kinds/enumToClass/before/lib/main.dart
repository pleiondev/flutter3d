import 'package:flutter3d_kinds/flutter3d_kinds.dart';

String describe(Weather w) => switch (w) {
  Weather.sun => 'bright',
  Weather.rain => 'wet',
};

void report(Weather w) {
  switch (w) {
    case Weather.sun:
      print('sun');
    case Weather.rain:
      print('rain');
  }
}

String safe(Weather w) => switch (w) {
  Weather.sun => 'bright',
  _ => 'other',
};
