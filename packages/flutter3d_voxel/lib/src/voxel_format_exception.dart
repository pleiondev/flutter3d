import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// A saved voxel world that is not one, was saved over other terrain or
/// another size, or is newer than this build reads.
final class VoxelFormatException extends Flutter3dFormatException {
  const VoxelFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'VoxelFormatException: $message';
}
