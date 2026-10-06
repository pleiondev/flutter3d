/// The core's numbers, as `csrc/include/f3d_physics.h` defines them — P9.
///
/// Plain Dart, the same natively and in the browser; `bindings_test.dart`
/// holds every one against the header.
library;

/// `F3D_ABI_VERSION` this file was written against.
const int abiVersion = 28;

/// `F3D_TRANSFORM_FLOATS`.
const int transformFloats = 7;

/// `F3D_FIRE_FLOATS`.
const int fireFloats = 4;

/// `F3D_CONTACT_FLOATS`.
const int contactFloats = 7;

/// `F3D_HIT_FLOATS`.
const int hitFloats = 7;

/// `F3D_CHARACTER_*`.
abstract final class CharacterFlags {
  static const int grounded = 1;
  static const int wall = 2;
  static const int ceiling = 4;
  static const int stepped = 8;

  /// `F3D_CHARACTER_MAY_STEP`, an option rather than a result.
  static const int mayStep = 1;
}

/// `F3D_EVENT_CAPACITY`.
const int eventCapacity = 65536;

/// `F3dBodyType`.
abstract final class BodyType {
  static const int dynamic = 0;
  static const int fixed = 1;
}

/// `F3dShapeKind`.
abstract final class ShapeKind {
  static const int point = 0;
  static const int sphere = 1;
  static const int box = 2;
  static const int capsule = 3;
  static const int cylinder = 4;
  static const int cone = 5;
  static const int hull = 6;
  static const int mesh = 7;
  static const int compound = 8;
}

/// `F3D_COMPOUND_PART_FLOATS`.
const int compoundPartFloats = 11;

/// `F3D_COMPOUND_MOST_PARTS`.
const int compoundMostParts = 64;

/// `F3D_VEHICLE_MOST_WHEELS`, `F3D_WHEEL_FLOATS` and
/// `F3D_WHEEL_STATE_FLOATS`.
const int vehicleMostWheels = 8;
const int wheelFloats = 8;
const int wheelStateFloats = 14;

/// `F3D_MULTIBODY_MOST_LINKS` and `F3D_MULTIBODY_MOST_DOFS`.
const int multibodyMostLinks = 32;
const int multibodyMostDofs = 64;

/// `F3dJointType`.
abstract final class JointType {
  static const int fixed = 0;
  static const int spherical = 1;
  static const int revolute = 2;
  static const int prismatic = 3;
  static const int distance = 4;
}

/// `F3dMaterialKind`.
abstract final class MaterialKind {
  static const int inert = 0;
  static const int wood = 1;
  static const int paper = 2;
  static const int rubber = 3;
  static const int steel = 4;
  static const int stone = 5;
}

/// `F3dEventKind`.
abstract final class EventKind {
  static const int slept = 0;
  static const int woke = 1;
  static const int ignited = 2;
  static const int extinguished = 3;
  static const int burntOut = 4;
  static const int contactBegan = 5;
  static const int contactEnded = 6;
  static const int jointBroken = 7;
}

/// `F3D_PARTICLE_FLOATS`.
const int particleFloats = 4;

/// `F3D_DEBRIS_INPUT_FLOATS`, `F3D_DEBRIS_FLOATS`, `F3D_DEBRIS_STATIC_FLOATS`
/// and `F3D_DEBRIS_MAX_STATICS`.
const int debrisInputFloats = 8;

const int debrisFloats = 8;

const int debrisStaticFloats = 8;

const int debrisMaxStatics = 64;

/// `F3D_CLOTH_FLOATS` and `F3D_CLOTH_MAX_BALLS`.
const int clothFloats = 4;

const int clothMaxBalls = 16;

/// `F3D_CLOTH_STATE_FLOATS`.
const int clothStateFloats = 7;

/// `F3D_CLOTH_BALL` and the rest: what each record of
/// `f3d_cloth_set_obstacles` starts with.
abstract final class ClothObstacleKind {
  static const int ball = 0;
  static const int capsule = 1;
  static const int convex = 2;
  static const int ground = 3;
}

/// `F3D_FLUID_INPUT_FLOATS` and `F3D_FLUID_FLOATS`.
const int fluidInputFloats = 6;

const int fluidFloats = 4;

/// `F3D_LIQUID_PARTICLE_FLOATS`, `F3D_LIQUID_PARCEL_FLOATS` and
/// `F3D_LIQUID_MODE_FLOATS`.
const int liquidParticleFloats = 6;

const int liquidParcelFloats = 17;

const int liquidModeFloats = 6;

/// `F3D_LIQUID_PIPE_FLOATS`, `F3D_LIQUID_BODY_FLOATS` and
/// `F3D_LIQUID_PUSH_FLOATS`.
const int liquidPipeFloats = 11;

const int liquidBodyFloats = 4;

const int liquidPushFloats = 8;

/// `F3D_LIQUID_SPHERE` and the rest: the shape a push of
/// `f3d_liquid_floats` names.
abstract final class LiquidFloatShape {
  static const int sphere = 0;
  static const int box = 1;
  static const int capsule = 2;
  static const int other = 3;
}

/// `F3D_LIQUID_PLANE` and the rest: what each wall record of
/// `f3d_liquid_particles` and `f3d_liquid_parcels` starts with.
abstract final class LiquidWallKind {
  static const int plane = 0;
  static const int inside = 1;
  static const int outside = 2;
}
