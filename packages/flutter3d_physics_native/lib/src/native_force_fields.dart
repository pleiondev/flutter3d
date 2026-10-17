/// The solver hook: forces and constraints computed in Dart, each step,
/// over a [NativeWorld].
///
/// **Why a hook in Dart, and not a joint type in C.** The core's joints —
/// [NativeJointType] — are a closed set, solved inside the core's step, and
/// they stay closed: a new joint in C is a new ABI. What a game or a plugin
/// needs most often is not a new row in the solver but a force it can
/// compute from where bodies are and how fast they go — a spring, a rope's
/// pull, a magnet, a current, a field that holds a hovercraft off the
/// ground. That is a [NativeForceField]: its [NativeForceField.apply] runs
/// once a step, before the core steps, reads the bodies through a
/// [NativeForceContext] and adds forces and torques the core then spends
/// over the step. The heavy laws, which a step cannot afford in Dart, go to
/// a Wasm module later.
///
/// **Deterministic, because the step is.** A field reads no clock and draws
/// no random number; the step's own count, [NativeForceContext.step], is its
/// time. Anything transcendental goes through `Portable` (from
/// `flutter3d_physics`), as everything a step reads does: `dart:math`'s
/// `sin` and `pow` differ between the VM and the browser. A square root is
/// exact everywhere and may be taken as it is. Fields apply in the order
/// they were added, so two worlds given the same fields in the same order
/// add the same forces.
///
/// **Snapshot-able.** A field that remembers something between steps — a
/// spring that has snapped — says so in [NativeForceField.saveState], as
/// JSON, and takes it back in [NativeForceField.restoreState]; the fields'
/// states go into a [NativeDynamics] save beside the core's bytes.
library;

import 'package:vector_math/vector_math.dart';

import 'native_world.dart';

/// One force law over a [NativeWorld], computed in Dart every step.
///
/// `base`, so a member added here later arrives with a default. Shared by
/// nothing: one field is in one [NativeForceFields].
abstract base class NativeForceField {
  const NativeForceField();

  /// What the field is called: unique among the fields of one world, and
  /// the key its state is saved under, so it must be the same in every run.
  String get name;

  /// Adds this step's forces through [context]. Runs once a step, before the
  /// core steps, and only on a step the core will take.
  void apply(NativeForceContext context);

  /// What this field remembers between steps, as JSON, or null when it
  /// remembers nothing — the default, and right for a field that is a pure
  /// function of the world.
  Object? saveState() => null;

  /// Back to what [saveState] wrote. Null when nothing was saved for it.
  void restoreState(Object? state) {}
}

/// What a [NativeForceField] may read and do in one step.
///
/// One per [NativeForceFields], reused every step: a field keeps nothing
/// of it between calls.
final class NativeForceContext {
  NativeForceContext._(this.world);

  /// The world being stepped. Read from it; change it only through
  /// [addForce] and [addTorque], or the step stops being one law applied
  /// in order.
  final NativeWorld world;

  double _dt = 0.0;
  int _step = 0;

  /// The step about to be taken, seconds.
  double get dt => _dt;

  /// How many steps the fields have applied before this one: the field's
  /// clock, saved with the fields.
  int get step => _step;

  /// Whether [body] is in the world — a body a field holds may have been
  /// taken out since it was given.
  bool contains(NativeBody body) => world.contains(body);

  /// [body]'s position relative to the world's origin, single precision:
  /// the frame a field's forces are worked out in.
  Vector3 localPositionOf(NativeBody body) => world.localPositionOf(body);

  /// [body]'s velocity, metres per second.
  Vector3 velocityOf(NativeBody body) => world.velocityOf(body);

  /// [body]'s spin, radians per second about the world's axes.
  Vector3 angularVelocityOf(NativeBody body) => world.angularVelocityOf(body);

  /// [body]'s mass, kilograms.
  double massOf(NativeBody body) => world.massOf(body);

  /// A force, N, through [body]'s centre, spent by this step.
  void addForce(NativeBody body, Vector3 force) => world.addForce(body, force);

  /// A torque, N m about the world's axes, spent by this step.
  void addTorque(NativeBody body, Vector3 torque) =>
      world.addTorque(body, torque);
}

/// The [NativeForceField]s of one world, applied in the order they were
/// added, every step.
///
/// [step] applies them and steps the world; a caller that steps the world
/// itself — [NativeDynamics], which mirrors its bodies in first — calls
/// [apply] just before. With no field it adds nothing and saves nothing, so
/// a world that never gains one steps and saves exactly as it did.
final class NativeForceFields {
  NativeForceFields(this.world) : _context = NativeForceContext._(world);

  final NativeWorld world;
  final NativeForceContext _context;
  final List<NativeForceField> _fields = <NativeForceField>[];

  /// The fields, in the order they apply.
  List<NativeForceField> get fields =>
      List<NativeForceField>.unmodifiable(_fields);

  bool get isEmpty => _fields.isEmpty;
  bool get isNotEmpty => _fields.isNotEmpty;

  /// How many steps the fields have been applied to.
  int get steps => _context._step;

  /// Adds [field], to apply after the ones already here. Throws an
  /// [ArgumentError] when a field of its name is here already: its state
  /// would be saved under a key two fields share.
  void add(NativeForceField field) {
    if (_fields.any((f) => f.name == field.name)) {
      throw ArgumentError.value(
        field.name,
        'field',
        'a force field of this name is already in this world',
      );
    }
    _fields.add(field);
  }

  /// Takes [field] out. Whether it was here.
  bool remove(NativeForceField field) => _fields.remove(field);

  /// Applies every field for a step of [dt], without stepping. Nothing for
  /// a [dt] the core would not step — not finite, or not positive.
  void apply(double dt) {
    if (!(dt > 0.0) || !dt.isFinite || _fields.isEmpty) return;
    _context._dt = dt;
    for (final field in _fields) {
      field.apply(_context);
    }
    _context._step++;
  }

  /// Applies every field, then steps the world by [dt].
  void step(double dt) {
    apply(dt);
    world.step(dt);
  }

  /// The fields' state: the step count and, by name, what each field that
  /// remembers anything said.
  Map<String, Object?> saveState() => <String, Object?>{
    'steps': _context._step,
    'fields': <String, Object?>{
      for (final field in _fields)
        if (field.saveState() case final Object state) field.name: state,
    },
  };

  /// Back to what [saveState] wrote. Every field here is handed what was
  /// saved under its name, or null.
  void restoreState(Object? saved) {
    final map = saved is Map ? saved : const <Object?, Object?>{};
    final steps = map['steps'];
    _context._step = steps is int ? steps : 0;
    final states = map['fields'];
    for (final field in _fields) {
      field.restoreState(states is Map ? states[field.name] : null);
    }
  }
}

/// A damped spring between two bodies: the hook's own example, and a
/// constraint the core's joints do not have.
///
/// Pulls [a] and [b] together, or pushes them apart, along the line between
/// their centres, with [stiffness] N/m times how far they are from
/// [restLength] plus [damping] N s/m times how fast that distance changes.
/// Equal and opposite, so the pair's momentum is kept.
///
/// Given a [breakingForce], it snaps the first step its pull passes it and
/// pulls nothing after — the state it saves, so a restored world's spring
/// is broken or whole as it was.
final class NativeSpring extends NativeForceField {
  NativeSpring({
    required this.name,
    required this.a,
    required this.b,
    required this.restLength,
    required this.stiffness,
    this.damping = 0.0,
    this.breakingForce,
  });

  @override
  final String name;

  final NativeBody a;
  final NativeBody b;

  /// The distance between the centres it pulls nothing at, in metres.
  final double restLength;

  /// In newtons per metre of stretch.
  final double stiffness;

  /// In newton-seconds per metre: newtons per metre per second of closing.
  final double damping;

  /// The pull it snaps at, in newtons; null for a spring that never does.
  final double? breakingForce;

  bool _broken = false;

  /// Whether it has snapped.
  bool get isBroken => _broken;

  @override
  void apply(NativeForceContext context) {
    if (_broken || !context.contains(a) || !context.contains(b)) return;
    final along = context.localPositionOf(b)..sub(context.localPositionOf(a));
    final length = along.length;
    // Two centres in one place have no line between them to pull along.
    if (length <= 1e-6) return;
    along.scale(1.0 / length);
    final closing = (context.velocityOf(
      b,
    )..sub(context.velocityOf(a))).dot(along);
    final pull = stiffness * (length - restLength) + damping * closing;
    if (breakingForce case final double limit when pull.abs() > limit) {
      _broken = true;
      return;
    }
    context
      ..addForce(a, along * pull)
      ..addForce(b, along * -pull);
  }

  @override
  Object? saveState() =>
      _broken ? const <String, Object?>{'broken': true} : null;

  @override
  void restoreState(Object? state) =>
      _broken = state is Map && state['broken'] == true;
}
