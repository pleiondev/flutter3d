/// The engine's data tables, uploaded once per device — `G1`.
///
/// A table is uploaded the first time something asks for it and kept for as
/// long as the device lives, so an effect that is switched off never costs
/// its table, and two renderers on one device share one copy.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'engine_table.dart';
import 'tables/aces2_display.dart' as tables;
import 'tables/blue_noise.dart' as tables;

export 'engine_table.dart';

final class EngineTables {
  EngineTables._(this._device);

  static final Expando<EngineTables> _byDevice = Expando<EngineTables>(
    'engine tables',
  );

  /// The tables of [device], created on first use.
  static EngineTables of(GraphicsDevice device) =>
      _byDevice[device] ??= EngineTables._(device);

  /// Every table the engine ships, for tests and tools that walk them.
  static const List<EngineTable> all = <EngineTable>[
    tables.blueNoise,
    tables.aces2Display,
  ];

  /// Entries per axis of [aces2Display] — `L2`.
  static const int aces2DisplaySize = 33;

  final GraphicsDevice _device;
  final Map<EngineTable, TextureHandle> _uploaded =
      <EngineTable, TextureHandle>{};

  /// How many tables this device has been given, for tests.
  int get uploads => _uploaded.length;

  /// See `tables/blue_noise.dart`.
  TextureHandle get blueNoise => this[tables.blueNoise];

  /// See `tables/aces2_display.dart`.
  TextureHandle get aces2Display => this[tables.aces2Display];

  /// [table] on this device, uploaded now if it was not already.
  TextureHandle operator [](EngineTable table) => _uploaded[table] ??=
      _device.createTextureFromPixels(
        width: table.width,
        height: table.height,
        format: table.format,
        pixels: ByteData.sublistView(table.bytes),
      ) ??
      (throw StateError(
        '${table.name}: the device refused a ${table.width}×'
        '${table.height} ${table.format.name} table',
      ));
}
