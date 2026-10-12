/// A twin fed by REST: a tank coloured by the air temperature a weather
/// service reports for its site, asked once a minute.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:http/http.dart' as http;

void main() => runApp(MaterialApp(home: TwinOverRest()));

/// Berlin's air now, from Open-Meteo, which needs no key.
final Uri site = Uri.parse(
  'https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.41&current=temperature_2m',
);

/// A reading now and one a minute, in °C. No answer, or not the one asked
/// for, and the last reading stands.
Stream<num?> readings() async* {
  for (num? last; ; await Future<void>.delayed(const Duration(minutes: 1))) {
    try {
      final answer = jsonDecode((await http.get(site)).body);
      if (answer case {'current': {'temperature_2m': final num t}}) last = t;
    } on Exception {
      // Kept: the last reading stands.
    }
    yield last;
  }
}

class TwinOverRest extends StatelessWidget {
  TwinOverRest({super.key});

  /// Made with the widget, so a rebuild listens to the same readings.
  final Stream<num?> air = readings();

  @override
  Widget build(BuildContext context) => StreamBuilder<num?>(
    stream: air,
    builder: (context, celsius) {
      // Blue at 0 °C, red at 30 °C.
      final warm = ((celsius.data ?? 15) / 30).clamp(0.0, 1.0);
      return Scene3D(
        children: <Widget>[
          const Light3D.sun(),
          Material3D(
            baseColor: LinearColor(0.1 + 0.7 * warm, 0.2, 0.8 - 0.7 * warm),
            children: const <Widget>[Mesh3D(shape: CylinderShape())],
          ),
        ],
      );
    },
  );
}
