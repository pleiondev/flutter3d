/// A field on a device: the 3D texture a volume is drawn from and the
/// buffer a compute step steps, each made from a host field's values or
/// refused by the feature that is missing — 1.0.
///
/// What `FieldUpload` in the renderer's core stands on, asked of the
/// backend: that a `TextureDimension.d3` texture of a float format is made
/// and written in the order a `HostField` keeps its cells, or refused with
/// `DeviceFeature.texture3D` named before anything is allocated; and that a
/// storage buffer holds a field's floats bit for bit.
library;

import 'dart:typed_data';

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Unit, UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../flutter3d_conformance.dart';

/// A small field whose every value differs: four cells by three by two.
HostField _field(FieldResidence residence) {
  final field = HostField(
    FieldDeclaration(
      id: 'conformance.field',
      quantity: 'f3d.temperature',
      unit: Unit.kelvin,
      grid: const FieldGrid(4, 3, 2),
      residence: residence,
      writer: const FieldAccess.frame('conformance.upload'),
    ),
  );
  for (var i = 0; i < field.values.length; i++) {
    field.values[i] = 273.15 + i * 0.5;
  }
  return field;
}

/// A device with 3D textures makes one of the field's shape and takes its
/// values; one without refuses it, naming the feature, rather than making
/// a 2D texture or throwing something else.
Future<void> checkFieldTexture3D(GraphicsDevice device) async {
  final field = _field(FieldResidence.texture3D);
  final grid = field.declaration.grid;
  final descriptor = TextureDescriptor(
    width: grid.width,
    height: grid.height,
    depthOrArrayLayers: grid.depth,
    dimension: TextureDimension.d3,
    format: TextureFormat.r32Float,
    usage: TextureUsage.sampled | TextureUsage.copyDestination,
    label: field.declaration.id,
  );
  final has =
      device.features.has(DeviceFeature.texture3D) &&
      device.features.has(DeviceFeature.textureWrites);
  if (!has) {
    final missing = device.features.has(DeviceFeature.textureWrites)
        ? DeviceFeature.texture3D
        : DeviceFeature.textureWrites;
    try {
      device.createTexture(descriptor);
    } on UnsupportedCapabilityException catch (refused) {
      require(
        refused.feature == missing,
        'a 3D texture on a device without ${missing.name} was refused for '
        '${refused.feature.name}',
      );
      return;
    }
    require(
      false,
      'a device without ${missing.name} made a 3D texture instead of '
      'refusing it',
    );
  }
  if (!device.textureFormatSupport(TextureFormat.r32Float).sampled) {
    decline(device, 'cannot sample r32Float, the format a field is held in');
  }
  final texture = device.createTexture(descriptor);
  try {
    require(
      texture.width == grid.width && texture.height == grid.height,
      'a 3D texture of ${grid.width}x${grid.height}x${grid.depth} came back '
      '${texture.width}x${texture.height}',
    );
    device.writeTexture(texture, ByteData.sublistView(field.values));
  } finally {
    device.releaseTexture(texture);
  }
}

/// A field in a storage buffer reads back as the floats it was made with,
/// and as the ones written over them: the bytes a compute step and the host
/// agree on.
Future<void> checkFieldBufferRoundTrip(GraphicsDevice device) async {
  if (!device.features.has(DeviceFeature.compute) ||
      !device.features.has(DeviceFeature.buffers)) {
    decline(device, 'has no compute, where a buffer field is held');
  }
  final field = _field(FieldResidence.buffer);
  final bytes = ByteData.sublistView(field.values);
  final buffer = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: bytes.lengthInBytes,
      usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
      label: field.declaration.id,
    ),
    contents: bytes,
  );
  try {
    Future<void> holds(Float32List expected, String when) async {
      final got = Float32List.sublistView(await device.readBuffer(buffer));
      for (var i = 0; i < expected.length; i++) {
        require(
          got[i] == expected[i],
          'cell value $i read back ${got[i]} $when, where ${expected[i]} '
          'was written',
        );
      }
    }

    await holds(field.values, 'after it was made');
    field.fill(-40);
    device.writeBuffer(buffer, 0, bytes);
    await holds(field.values, 'after it was written over');
  } finally {
    device.releaseStorageBuffer(buffer);
  }
}

/// The field checks, in the order they are run.
List<ConformanceCheck> get fieldResidenceChecks => <ConformanceCheck>[
  (
    name: 'a field is held in a 3D texture, or refused by the feature',
    run: checkFieldTexture3D,
  ),
  (
    name: 'a field in a storage buffer reads back bit for bit',
    run: checkFieldBufferRoundTrip,
  ),
];
