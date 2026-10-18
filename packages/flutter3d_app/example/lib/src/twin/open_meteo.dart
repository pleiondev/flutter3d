/// The twin's one real source: Open-Meteo's current weather, which needs no
/// key, read as one [ExternalStateInput] of the air's temperature.
///
/// **A source is a function of an answer.** [readOpenMeteo] is all the twin
/// knows of this service; a plant's historian, a building's BMS or a broker
/// bridged to HTTP is another function of the same shape handed to the
/// `RestPoller`, and nothing past it changes.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'site_twin.dart';

/// Where Open-Meteo says the current temperature two metres above the ground
/// at [latitude], [longitude], in degrees Celsius.
Uri openMeteoUri({required double latitude, required double longitude}) =>
    Uri.https('api.open-meteo.com', '/v1/forecast', <String, String>{
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m',
    });

/// The air's temperature in Open-Meteo's answer [json], as a measured
/// reading, or null when the answer holds none.
///
/// [receivedTime] is when it arrived, seconds on this machine's clock; the
/// source's own time is its `current.time`, which it writes in UTC without
/// saying so, turned into seconds since the epoch.
ExternalStateInput? readOpenMeteo(
  Object? json, {
  required double receivedTime,
}) {
  if (json case {
    'current': {'time': final String time, 'temperature_2m': final num celsius},
  }) {
    final taken = DateTime.tryParse('${time}Z');
    return ExternalStateInput.quantity(
      SiteTwin.airSource,
      Quantity(celsius.toDouble(), Unit.celsius),
      sourceSeconds: taken == null ? null : taken.millisecondsSinceEpoch / 1000,
      receivedSeconds: receivedTime,
      quality: ReadingQuality.good,
      kind: ReadingKind.measured,
      tag: 'open-meteo',
    );
  }
  return null;
}
