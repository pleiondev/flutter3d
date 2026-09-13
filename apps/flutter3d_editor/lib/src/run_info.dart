import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';

/// `rp-04`'s missing half: what actually happens once a `.f3drun` reaches
/// this application — by a double-click, a drag into the browser window, or
/// the ordinary open panel. `Demo.fromJson` on [text], wrapped so every
/// caller sees the same three outcomes instead of three different try/catch
/// blocks: a run, a `FormatException` for text that is not JSON at all, or
/// [Demo]'s own [DemoFormatException] for JSON that is not a run — a version
/// too new, a missing field, the same strictness the format has always had.
Demo parseRunFile(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, Object?>) {
    throw const DemoFormatException('a run is a JSON object, not this');
  }
  return Demo.fromJson(json);
}
