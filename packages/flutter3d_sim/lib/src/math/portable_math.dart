/// [Portable] lives in `flutter3d_physics` now, the lowest package a fixed
/// step runs through, so that collision, cloth and liquids answer the same
/// questions the same way as everything above them. Re-exported here so the
/// simulation's own imports and its public API stay as they were.
library;

export 'package:flutter3d_physics/flutter3d_physics.dart' show Portable;
