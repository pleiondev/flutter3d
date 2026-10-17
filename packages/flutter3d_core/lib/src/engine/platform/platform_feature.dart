import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// Something a platform the core runs on may lack, as a device may lack a
/// `DeviceFeature`: refused with the foundation's [UnsupportedCapabilityException],
/// so a caller catches it as a [CapabilityException] whichever layer said
/// no.
///
/// An open class with constants, so a later release can name more.
final class PlatformFeature extends Capability {
  const PlatformFeature._(this.name);

  /// The stable identifier, used in reports and refusals.
  @override
  final String name;

  /// Files read by path: native platforms have them, the browser does not,
  /// and there an asset comes through an `AssetSource` instead.
  static const PlatformFeature fileSystem = PlatformFeature._('fileSystem');

  @override
  String toString() => 'PlatformFeature.$name';
}
