/// Why a field cannot be held where its declaration asks: [FieldRefusal]
/// and [FieldResidenceException].
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'field.dart';

/// Why a field was refused a residence.
///
/// **An open set** (S0), as `ComputeRefusalReason` is.
final class FieldRefusal {
  const FieldRefusal._(this.name);

  /// The device lacks a feature the residence needs: 3D textures for
  /// [FieldResidence.texture3D], buffers for [FieldResidence.buffer].
  static const FieldRefusal missingFeature = FieldRefusal._('missingFeature');

  /// No executor of the frame can hold it: the compute placement the field
  /// is written at has no device, or none with what it needs.
  static const FieldRefusal noPlacement = FieldRefusal._('noPlacement');

  /// Nothing has placed it yet: a field on a device is placed before the
  /// frame, as a compute step is.
  static const FieldRefusal notPlaced = FieldRefusal._('notPlaced');

  /// Every reason this version names. A later version appends.
  static const List<FieldRefusal> values = <FieldRefusal>[
    missingFeature,
    noPlacement,
    notPlaced,
  ];

  /// The reason called [name], or null for one this version does not know.
  static FieldRefusal? byName(String name) {
    for (final reason in values) {
      if (reason.name == name) return reason;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'FieldRefusal.$name';
}

/// The typed refusal of a field that cannot be held where it asks: which
/// field, which residence, why, and the capability that was missing.
///
/// A [CapabilityException]: the machine decides it, not the program. The
/// frame reports the step that would have made the field as unsupported
/// and goes on, and whatever only read the field is culled with it; a
/// caller that placed the field itself catches this.
final class FieldResidenceException extends CapabilityException {
  /// The refusal of [field] in [residence] for [reason], with the missing
  /// [capability], the refusing [backend] and the device's [cause] where
  /// known.
  const FieldResidenceException({
    required this.field,
    required this.residence,
    required this.reason,
    this.capability,
    this.backend,
    this.cause,
  });

  /// The field, by its id.
  final String field;

  /// Where it asked to be held.
  final FieldResidence residence;

  /// Why it cannot be.
  final FieldRefusal reason;

  /// The capability that was missing (`DeviceFeature.texture3D` for a 3D
  /// texture), when one was.
  final Capability? capability;

  /// The device that refused, as a person would name its backend.
  final String? backend;

  /// What the device threw, when it threw.
  @override
  final Object? cause;

  @override
  String get message {
    final where = backend == null ? '' : ' on $backend';
    final why = switch (reason) {
      FieldRefusal.missingFeature => switch (capability) {
        final missing? => 'the device has no ${missing.name}',
        null => 'the device lacks what it needs',
      },
      FieldRefusal.noPlacement => 'no executor of this frame can hold it',
      FieldRefusal.notPlaced => 'nothing has placed it yet',
      _ => reason.name,
    };
    return 'field "$field" cannot be held in ${residence.name}$where: $why';
  }

  @override
  String toString() => 'FieldResidenceException: $message';
}
