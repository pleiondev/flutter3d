/// A field on a device: the storage a frame holds one in, and the node that
/// puts a host field there — 1.0.
///
/// **A field is a frame-graph resource under its own id.** A node that
/// makes one declares the id among its writes and hands the storage in with
/// `FrameResources.provideField`; a node that reads one declares the id
/// among its reads and takes it with `FrameResources.field`. The graph
/// orders the two as it orders a texture's writer and readers, and culls a
/// reader whose field nothing made.
///
/// **Where it is held is the field's declaration's.** A
/// `FieldResidence.buffer` field lives in a storage buffer on a compute
/// device the hardware layer chooses as it chooses a compute step's
/// (`FrameCompute.placeStorage`), so a compute step that steps the field
/// there binds it as it is. A
/// `FieldResidence.texture3D` field lives in a 3D texture on the device that
/// draws, which a stage samples and filters; a device without
/// `DeviceFeature.texture3D` refuses it, by name, before anything is
/// allocated.
library;

import 'dart:typed_data';

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;

import 'frame_graph.dart';
import 'render_node.dart';

/// A field held in a storage buffer on a compute device, its cells in the
/// order a `HostField` keeps them, one float each value.
final class BufferField extends FieldStorage {
  BufferField(this.declaration, this.buffer, this.site);

  @override
  final FieldDeclaration declaration;

  @override
  FieldResidence get residence => FieldResidence.buffer;

  /// The buffer, `FieldGrid.valueCount` floats long.
  final StorageBuffer buffer;

  /// Where it lives: where a compute step that steps it runs. Since
  /// 1.0.0-rc.1, in place of the executor.
  final ComputeSite site;

  @override
  String toString() =>
      'BufferField(${declaration.id} on ${site.device.backendName})';
}

/// A field held in a 3D texture on the device that draws: one texel a
/// cell, in a float format of as many channels as a cell has values.
final class Texture3DField extends FieldStorage {
  Texture3DField(this.declaration, this.texture);

  @override
  final FieldDeclaration declaration;

  @override
  FieldResidence get residence => FieldResidence.texture3D;

  /// The texture: `TextureDimension.d3`, the grid's width, height and
  /// depth.
  final TextureHandle texture;

  @override
  String toString() => 'Texture3DField(${declaration.id})';
}

/// The node that puts a host field on a device every frame, in [residence]:
/// a buffer on a compute device, or a 3D texture on the device that draws.
///
/// **The simulation's field, the frame's copy.** A field a subsystem steps
/// is declared in host memory, and the frame draws a volume from a copy of
/// it on the device, under the same id: [residence] says where that copy is
/// held, the 3D texture a stage samples unless the caller says otherwise.
///
/// **Placed before the frame, as a compute step is.** [place] decides where
/// the field is held and whether it can be; a field that cannot is not
/// supported ([isSupported] false), the frame reports the node as
/// `PassSkip.unsupported` with [refusal] saying why, and whatever only read
/// the field is culled with it rather than the frame throwing.
///
/// **What it writes is the field's id**, and nothing else: a reader names
/// the same id and takes the storage with `FrameResources.field`.
final class FieldUpload extends RenderNode {
  /// The node that puts [source] on a device, held in [residence]. [source]
  /// is read every frame: the simulation's published copy
  /// (`FieldRegistry.published`) is what a frame hands.
  FieldUpload(this.source, {this.residence = FieldResidence.texture3D}) {
    if (!residence.onDevice) {
      throw ArgumentError.value(
        residence.name,
        'residence',
        'is not on a device; field "${source.declaration.id}" is put on one '
            'as a buffer or a 3D texture',
      );
    }
  }

  /// The host values put on the device every frame.
  final HostField source;

  /// Where the frame's copy is held.
  final FieldResidence residence;

  /// The field.
  FieldDeclaration get declaration => source.declaration;

  /// The field's id, under which a frame carries it.
  ResourceId get id => ResourceId(declaration.id);

  @override
  String get name => '${declaration.id} upload';

  @override
  List<ResourceId> get writes => <ResourceId>[id];

  /// Before the opaque scene, which is what draws a volume from a field
  /// most often.
  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforeOpaque;

  ComputeSite? _site;
  FieldResidenceException? _refusal = const FieldResidenceException(
    field: '',
    residence: FieldResidence.host,
    reason: FieldRefusal.notPlaced,
  );
  FieldStorage? _storage;

  /// Where the last [place] put the field, or null. Since 1.0.0-rc.1, in
  /// place of `executor`.
  ComputeSite? get site => _site;

  /// Why the field is not placed: the refusal of the last [place], or that
  /// it was never placed. Null once placed.
  FieldResidenceException? get refusal => switch (_refusal) {
    final r? when r.field.isEmpty => FieldResidenceException(
      field: declaration.id,
      residence: residence,
      reason: r.reason,
    ),
    final r => r,
  };

  /// Placed, and so in the frame.
  @override
  bool get isSupported => _site != null;

  /// False while a [place] is working out where the field goes: the frame
  /// reports the upload as `PassSkip.pending` until it answers.
  @override
  bool get isReady => _placing == 0;
  int _placing = 0;

  /// Once a frame: the field has no view.
  @override
  ViewRuns get viewRuns => ViewRuns.once;

  /// Decides where the field is held for frames drawn on [device], and
  /// whether it can be. A [FieldResidence.texture3D] field is held on
  /// [device], which needs `DeviceFeature.texture3D` and
  /// `DeviceFeature.textureWrites`, and a format of the cell's width; a
  /// [FieldResidence.buffer] field on the first of the frame's compute
  /// devices that has `DeviceFeature.buffers`, as the hardware layer orders
  /// them.
  ///
  /// Answers the refusal when nothing fits, which [refusal] also holds;
  /// null when placed. Placing again lets go of what the last placement
  /// made. Until it answers the upload is not [isReady].
  ///
  /// **Breaking in 1.0.0-rc.1:** given the device, not executors, and
  /// asynchronous, as a compute step's placement is.
  Future<FieldResidenceException?> place(GraphicsDevice device) {
    _placing++;
    return _place(device).whenComplete(() => _placing--);
  }

  Future<FieldResidenceException?> _place(GraphicsDevice device) async {
    dispose();
    return _refusal = switch (residence) {
      FieldResidence.texture3D => _placeTexture(device),
      FieldResidence.buffer => await _placeBuffer(device),
      // A residence a later version names has no device in this one.
      final other => _refused(FieldRefusal.noPlacement, other: other),
    };
  }

  FieldResidenceException? _placeTexture(GraphicsDevice device) {
    final missing = <DeviceFeature>[
      DeviceFeature.texture3D,
      DeviceFeature.textureWrites,
    ].where((f) => !device.features.has(f)).firstOrNull;
    if (missing != null) {
      return _refused(
        FieldRefusal.missingFeature,
        capability: missing,
        backend: device.backendName,
      );
    }
    if (_texelFormat == null) {
      return _refused(
        FieldRefusal.missingFeature,
        backend: device.backendName,
        cause: ArgumentError(
          'a 3D texture holds 1, 2 or 4 floats a texel, not '
          '${declaration.grid.components}',
        ),
      );
    }
    _site = FrameCompute.of(device).frame;
    return null;
  }

  Future<FieldResidenceException?> _placeBuffer(GraphicsDevice device) async {
    try {
      _site = await FrameCompute.of(device).placeStorage(
        name,
        (GraphicsDevice on) => on.features.has(DeviceFeature.buffers),
      );
      return null;
    } on ComputePlacementException catch (placement) {
      return _refused(
        FieldRefusal.noPlacement,
        capability: DeviceFeature.buffers,
        cause: placement,
      );
    }
  }

  FieldResidenceException _refused(
    FieldRefusal reason, {
    FieldResidence? other,
    DeviceFeature? capability,
    String? backend,
    Object? cause,
  }) => FieldResidenceException(
    field: declaration.id,
    residence: other ?? residence,
    reason: reason,
    capability: capability,
    backend: backend,
    cause: cause,
  );

  TextureFormat? get _texelFormat => switch (declaration.grid.components) {
    1 => TextureFormat.r32Float,
    2 => TextureFormat.r32g32Float,
    4 => TextureFormat.r32g32b32a32Float,
    _ => null,
  };

  /// Puts this frame's values on the device and hands the storage in under
  /// the field's id. Called only for a node the frame kept, which a node
  /// that is not placed never is.
  @override
  void execute(RenderFrame frame) {
    final site = _site;
    if (site == null) {
      throw StateError('"$name" ran without a placement: ${refusal?.message}');
    }
    final bytes = ByteData.sublistView(source.values);
    final storage = _storage ??= _make(site, bytes);
    switch (storage) {
      case final BufferField field:
        site.device.writeBuffer(field.buffer, 0, bytes);
      case final Texture3DField field:
        site.device.writeTexture(field.texture, bytes);
    }
    frame.resources.provideField(id, storage);
  }

  FieldStorage _make(ComputeSite site, ByteData bytes) {
    final grid = declaration.grid;
    final device = site.device;
    return residence == FieldResidence.texture3D
        ? Texture3DField(
            declaration,
            device.createTexture(
              TextureDescriptor(
                width: grid.width,
                height: grid.height,
                depthOrArrayLayers: grid.depth,
                dimension: TextureDimension.d3,
                format: _texelFormat!,
                usage: TextureUsage.sampled | TextureUsage.copyDestination,
                label: declaration.id,
              ),
            ),
          )
        : BufferField(
            declaration,
            device.createBuffer(
              BufferDescriptor(
                lengthInBytes: bytes.lengthInBytes,
                usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
                label: declaration.id,
              ),
            ),
            site,
          );
  }

  /// Lets go of what the last placement made on its device: what a renderer
  /// calls when the registration that added the upload is cancelled. A
  /// later [place] makes it again. Since 1.0.0-rc.1, `release`.
  @override
  void dispose() {
    switch (_storage) {
      case final BufferField field:
        field.site.device.releaseStorageBuffer(field.buffer);
      case final Texture3DField field:
        _site?.device.releaseTexture(field.texture);
    }
    _storage = null;
    _site = null;
  }
}
