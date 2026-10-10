/// What an encoder's feature-gated member does when its backend has not
/// overridden it. Not exported: the three encoder files share it.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;

import 'capabilities.dart';

/// The refusal a default body throws: the [feature] the member is gated by,
/// named against [encoder]'s runtime type, since an encoder does not know the
/// name its device gives itself.
///
/// **Why a default refuses rather than doing nothing.** A backend that leaves
/// a member to its default does not list the feature, so the refusal is what
/// the contract promises it says; a silent no-op would be a draw that never
/// happened with nothing anywhere saying so.
Never refuseByDefault(Object encoder, DeviceFeature feature) =>
    throw UnsupportedCapabilityException(
      feature,
      backend: '${encoder.runtimeType}',
      reason: 'its encoder leaves this to the default',
    );
