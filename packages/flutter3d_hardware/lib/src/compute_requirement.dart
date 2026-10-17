/// What a piece of compute needs of where it runs, as a requirement rather
/// than a placement; the portable kernel profile; and what is exact and
/// what carries a tolerance — since 1.0.0-rc.1.
///
/// **A requirement, never a placement.** A workload or a step says what it
/// cannot do without ([ComputeRequirement]): the same bytes on every
/// machine, say, for a game that replays a match or rolls a frame back.
/// The hardware layer then picks, by its own rule, an executor that meets
/// it, and says which it passed over and why. Nothing above the layer
/// still names a placement, so the rule stays the layer's.
///
/// **Exact, and within a tolerance.** Every placement computes the
/// integers and the f32 `+`, `-` and `*` to the same bits: the WGSL
/// translation rounds each operation where it stands, so no compiler fuses
/// a multiply-add or reorders a sum, and the Dart translation rounds to f32
/// after each. Division, `sqrt`, `sin`, `cos` and `pow` are a GPU's own to
/// within the tolerance [kernelTolerances] declares, which conformance
/// holds every device to against the Dart translation of the same kernel.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'graphics_device.dart';

/// What a piece of compute requires of the executor it runs on.
///
/// **An open set**, as `ComputePlacement` is: a requirement a later minor
/// adds does not break a `switch` written against these.
@immutable
final class ComputeRequirement {
  const ComputeRequirement._(this.name);

  /// The same bytes on every machine, for a game that replays a match, rolls
  /// a frame back or checks one peer's world against another's.
  ///
  /// Met everywhere by work whose kernels keep to what every placement
  /// computes exactly (integers, `+`, `-`, `*`, comparisons, the RGBA8
  /// conversions). Work that divides or calls `sqrt`, `sin`, `cos` or `pow`
  /// is placed only where those are computed the one way every machine
  /// computes them: the work's own host code, or a device that runs the
  /// kernels translated to Dart (`GraphicsDevice.isSoftware`). A GPU is
  /// passed over for it, with that reason.
  static const ComputeRequirement bitExact = ComputeRequirement._('bitExact');

  /// More than the portable profile ([PortableComputeProfile]): a bigger
  /// workgroup or more storage buffers a stage, held to each device's own
  /// [DeviceLimits] instead. A device whose limits fall short is passed
  /// over, with the limit named; without this requirement, work past the
  /// profile is refused on every device, because it would run on some
  /// machines and not on others.
  static const ComputeRequirement beyondPortableProfile = ComputeRequirement._(
    'beyondPortableProfile',
  );

  /// Every requirement this version names. A later version appends.
  static const List<ComputeRequirement> values = <ComputeRequirement>[
    bitExact,
    beyondPortableProfile,
  ];

  /// The requirement called [name], or null for one this version does not
  /// know.
  static ComputeRequirement? byName(String name) {
    for (final requirement in values) {
      if (requirement.name == name) return requirement;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'ComputeRequirement.$name';
}

/// What the hardware layer weighs about one piece of compute when it places
/// it: what the work requires, how large its kernels are, and which of its
/// operations carry a tolerance.
///
/// **Facts about the work, never a placement.** The engine reads them from
/// the work's kernels (`kernelNeeds` in `flutter3d_core`) and hands them to
/// `FrameCompute`, whose rule passes over a device that does not meet them,
/// saying why ([unmetOn]).
@immutable
final class ComputeNeeds {
  /// Work that requires [requirements], whose largest kernel runs
  /// [invocationsPerWorkgroup] invocations a workgroup and binds
  /// [storageBuffersPerStage] storage buffers, and whose kernels use the
  /// [inexactOperations] (keys of [kernelTolerances]).
  const ComputeNeeds({
    this.requirements = const <ComputeRequirement>{},
    this.invocationsPerWorkgroup = 1,
    this.storageBuffersPerStage = 0,
    this.inexactOperations = const <String>{},
  });

  /// Nothing required, and nothing past the portable profile.
  static const ComputeNeeds none = ComputeNeeds();

  /// What the work cannot do without.
  final Set<ComputeRequirement> requirements;

  /// The most invocations a workgroup of one of its kernels runs.
  final int invocationsPerWorkgroup;

  /// The most storage buffers one of its kernels binds.
  final int storageBuffersPerStage;

  /// The operations its kernels use that a GPU computes only to within a
  /// tolerance: `/`, `sqrt`, `sin`, `cos`, `pow`.
  final Set<String> inexactOperations;

  /// Why [device] cannot run this work, or null when it can: the portable
  /// profile or its own limits ([PortableComputeProfile.refusalFor]), and
  /// [ComputeRequirement.bitExact] for work with [inexactOperations] on a
  /// device that is not the Dart translation (`GraphicsDevice.isSoftware`).
  String? unmetOn(GraphicsDevice device) {
    final limit = PortableComputeProfile.refusalFor(
      invocations: invocationsPerWorkgroup,
      storageBuffers: storageBuffersPerStage,
      limits: device.limits,
      requirements: requirements,
    );
    if (limit != null) return limit;
    if (requirements.contains(ComputeRequirement.bitExact) &&
        inexactOperations.isNotEmpty &&
        !device.isSoftware) {
      final ops = (inexactOperations.toList()..sort()).join(', ');
      return 'the work requires the same bytes on every machine, and its '
          '$ops a GPU computes only to within a tolerance';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ComputeNeeds &&
      _sameSet(other.requirements, requirements) &&
      other.invocationsPerWorkgroup == invocationsPerWorkgroup &&
      other.storageBuffersPerStage == storageBuffersPerStage &&
      _sameSet(other.inexactOperations, inexactOperations);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(requirements),
    invocationsPerWorkgroup,
    storageBuffersPerStage,
    Object.hashAllUnordered(inexactOperations),
  );

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  String toString() =>
      'ComputeNeeds(${requirements.map((r) => r.name).join(', ')}'
      '${requirements.isEmpty ? '' : '; '}'
      '$invocationsPerWorkgroup invocations, '
      '$storageBuffersPerStage storage buffers'
      '${inexactOperations.isEmpty ? '' : '; ${inexactOperations.join(', ')}'})';
}

/// What a kernel may use and run on every device that computes, with no
/// requirement declared: the guarantees of Vulkan and OpenGL ES 3.1, which
/// are below WebGPU's defaults.
abstract final class PortableComputeProfile {
  /// Invocations in one workgroup, x × y × z.
  static const int maxInvocationsPerWorkgroup = 128;

  /// Storage buffers one kernel binds.
  static const int maxStorageBuffersPerStage = 8;

  /// Why a kernel of [invocations] a workgroup and [storageBuffers] storage
  /// bindings may not run on [limits], or null when it may. Within the
  /// profile it is asked of every device; past it, only with
  /// [ComputeRequirement.beyondPortableProfile] in [requirements], and then
  /// of each device's own [limits].
  static String? refusalFor({
    required int invocations,
    required int storageBuffers,
    required DeviceLimits limits,
    Set<ComputeRequirement> requirements = const <ComputeRequirement>{},
  }) {
    final beyond = requirements.contains(
      ComputeRequirement.beyondPortableProfile,
    );
    if (!beyond) {
      if (invocations > maxInvocationsPerWorkgroup) {
        return 'its workgroup of $invocations invocations is past the '
            'portable $maxInvocationsPerWorkgroup; declare '
            'ComputeRequirement.beyondPortableProfile to be held to each '
            "device's limits instead";
      }
      if (storageBuffers > maxStorageBuffersPerStage) {
        return 'its $storageBuffers storage buffers are past the portable '
            '$maxStorageBuffersPerStage; declare '
            'ComputeRequirement.beyondPortableProfile to be held to each '
            "device's limits instead";
      }
    }
    if (invocations > limits.maxComputeInvocationsPerWorkgroup) {
      return 'its workgroup of $invocations invocations is past this '
          "device's ${limits.maxComputeInvocationsPerWorkgroup}";
    }
    if (storageBuffers > limits.maxStorageBuffersPerShaderStage) {
      return 'its $storageBuffers storage buffers are past this device\'s '
          '${limits.maxStorageBuffersPerShaderStage}';
    }
    return null;
  }
}

/// How far a GPU's result of one operation of the kernel language may be
/// from the Dart translation's: within [ulp] units in the last place of an
/// f32, or within [absolute], whichever admits more.
@immutable
final class KernelTolerance {
  /// A tolerance of [ulp] units in the last place, or [absolute].
  const KernelTolerance({this.ulp = 0, this.absolute = 0, required this.over});

  /// Units in the last place of the f32 result.
  final int ulp;

  /// An absolute difference, in the result's own units.
  final double absolute;

  /// The inputs the tolerance is declared over, as WGSL declares its own.
  final String over;

  /// Whether [actual] is within this of [expected], both f32 values. Two
  /// NaNs agree; a NaN and a number do not.
  bool admits(double expected, double actual) {
    if (expected.isNaN || actual.isNaN) return expected.isNaN && actual.isNaN;
    if (expected == actual) return true;
    if ((expected - actual).abs() <= absolute) return true;
    return ulpsBetween(expected, actual) <= ulp;
  }

  @override
  bool operator ==(Object other) =>
      other is KernelTolerance &&
      other.ulp == ulp &&
      other.absolute == absolute &&
      other.over == over;

  @override
  int get hashCode => Object.hash(ulp, absolute, over);

  @override
  String toString() =>
      'KernelTolerance(${ulp == 0 ? '' : '$ulp ulp'}'
      '${ulp != 0 && absolute != 0 ? ' or ' : ''}'
      '${absolute == 0 ? '' : '$absolute absolute'}, over $over)';
}

/// The operations of the kernel language that are not exact on every
/// placement, each with the tolerance a device is held to: WGSL's own
/// accuracy for f32, rounded up to whole units.
///
/// Every other operation is exact: the integers, `+`, `-`, `*`, the
/// comparisons, `min`, `max`, `clamp`, `abs`, `floor`, `ceil`, `round`,
/// `trunc`, `select` and the conversions.
const Map<String, KernelTolerance> kernelTolerances = <String, KernelTolerance>{
  '/': KernelTolerance(ulp: 3, over: 'a divisor of magnitude 2^-126 to 2^126'),
  'sqrt': KernelTolerance(ulp: 5, over: 'every non-negative input'),
  'sin': KernelTolerance(absolute: 1 / 2048, over: 'inputs from -pi to pi'),
  'cos': KernelTolerance(absolute: 1 / 2048, over: 'inputs from -pi to pi'),
  'pow': KernelTolerance(
    ulp: 16,
    over: 'a positive base, with |exponent × log2(base)| at most 6',
  ),
};

/// How many f32 values lie between [a] and [b], each read as the nearest
/// f32: zero for the same value, one for neighbours.
int ulpsBetween(double a, double b) {
  int ordered(double x) {
    final bits = _bitsOf(x);
    // Sign and magnitude to one line of integers, negatives below zero.
    return bits & 0x80000000 != 0 ? -(bits & 0x7FFFFFFF) : bits;
  }

  return (ordered(a) - ordered(b)).abs();
}

int _bitsOf(double x) => (ByteData(4)..setFloat32(0, x)).getUint32(0);
