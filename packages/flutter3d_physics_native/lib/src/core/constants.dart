/// The core's numbers, as `csrc/include/f3d_physics.h` defines them — P9.
///
/// Plain Dart, the same natively and in the browser; `bindings_test.dart`
/// holds every one against the header.
library;

/// `F3D_ABI_VERSION` this file was written against.
const int abiVersion = 42;

/// `F3D_SNAPSHOT_MAJOR` in `csrc/src/f3d_snapshot.c`: the major a world's
/// snapshot is written at and the only one a restore reads. Its minor grows
/// as sections are added, and every 1.x core reads every snapshot of this
/// major; `test/fixtures/v1/world.f32.snapshot` and `world.f64.snapshot`
/// are the 1.0 bytes `test/snapshot_fixture_test.dart` holds it to.
const int snapshotFormatVersion = 1;

/// `F3D_TRANSFORM_FLOATS`: reals one body takes in
/// `f3d_world_read_transforms`, its position xyz then its orientation
/// quaternion xyzw.
const int transformFloats = 7;

/// `F3D_FIRE_FLOATS`: reals one fire takes in `f3d_world_read_fires`, from
/// its position and power to its flame's axis, width, soot and radiant
/// share, as the header lists them.
const int fireFloats = 13;

/// `F3D_CONTACT_FLOATS`: reals one contact point takes in
/// `f3d_world_read_contacts`, the normal xyz out of the second body into
/// the first, the point xyz halfway between the surfaces, and the depth in
/// metres, positive inside.
const int contactFloats = 7;

/// `F3D_REPORT_FLOATS`: reals one report takes in
/// `f3d_world_read_contact_reports`, the normal xyz, the manifold's middle
/// point xyz, the normal impulse over the step in newton seconds, and the
/// first body's velocity relative to the second's xyz in metres per second.
const int reportFloats = 10;

/// `F3dContactPhase`: what a contact report says happened to a manifold
/// since the step before.
abstract final class ContactPhases {
  /// In contact now and not in the step before.
  static const int began = 0;

  /// In contact in the step before and still now.
  static const int persisted = 1;

  /// In contact in the step before and not now; the report keeps where it
  /// last touched, with no impulse and no velocity.
  static const int ended = 2;
}

/// `F3D_HIT_FLOATS`: reals one ray or shape-cast hit takes, the point xyz
/// and the normal xyz out of what was hit, relative to the origin, then the
/// distance along the ray in metres or the fraction of the cast.
const int hitFloats = 7;

/// `F3D_CHARACTER_*`: the bits `f3d_world_move_character` returns, and the
/// option bit it takes.
abstract final class CharacterFlags {
  /// The move ended standing on ground: a surface whose normal's height is
  /// at least the maximum slope's cosine.
  static const int grounded = 1;

  /// The move met a wall, a surface too steep to stand on, and slid along
  /// it.
  static const int wall = 2;

  /// The move met something overhead.
  static const int ceiling = 4;

  /// The move climbed a step, keeping the step-up because it got further
  /// than sliding did.
  static const int stepped = 8;

  /// `F3D_CHARACTER_MAY_STEP`, an option rather than a result: the
  /// character stood on ground before this move and may climb a step.
  static const int mayStep = 1;
}

/// `F3D_EVENT_CAPACITY`: the count of events held unread; past it the
/// newest are dropped and counted.
const int eventCapacity = 65536;

/// `F3dBodyType`: how a body is moved.
abstract final class BodyType {
  /// Moved by gravity, forces, wind and contacts.
  static const int dynamic = 0;

  /// Never moves and has infinite mass; it still heats, cools and burns.
  static const int fixed = 1;

  /// Moves at the velocity and spin it is given and nothing else, with
  /// infinite mass, so it pushes what it meets.
  static const int kinematic = 2;
}

/// `F3dShapeKind`: what a body collides as, and what its sizes a, b and c
/// mean.
abstract final class ShapeKind {
  /// No extent: does not turn, has no surface and feels no wind.
  static const int point = 0;

  /// A sphere, a its radius in metres.
  static const int sphere = 1;

  /// A box, a, b and c its half extents along the body's axes in metres.
  static const int box = 2;

  /// A capsule along y, a its radius and b half the length of its straight
  /// part, in metres.
  static const int capsule = 3;

  /// A cylinder along y, a its radius and b half its height, in metres.
  static const int cylinder = 4;

  /// A cone along y, apex up, a its base's radius and b its height in
  /// metres; its origin at its centre of mass, a quarter of the height
  /// above the base.
  static const int cone = 5;

  /// A convex hull the world holds, set with `f3d_body_set_hull`.
  static const int hull = 6;

  /// A triangle mesh the world holds, for fixed bodies, set with
  /// `f3d_body_set_mesh`.
  static const int mesh = 7;

  /// Several of the shapes above placed in the body's frame, set with
  /// `f3d_body_set_compound`.
  static const int compound = 8;
}

/// `F3D_COMPOUND_PART_FLOATS`: reals one part of a compound takes in
/// `f3d_world_create_compound`, its sizes a, b, c, its rounding, its place
/// xyz and its turn as a quaternion xyzw.
const int compoundPartFloats = 11;

/// `F3D_COMPOUND_MOST_PARTS`: the count of parts one compound holds at
/// most.
const int compoundMostParts = 64;

/// `F3D_VEHICLE_MOST_WHEELS`: the count of wheels a vehicle has at most.
const int vehicleMostWheels = 8;

/// `F3D_WHEEL_FLOATS`: reals one wheel takes in `f3d_vehicle_add_wheel`,
/// its mount xyz, rest length, radius, stiffness, damping and grip.
const int wheelFloats = 8;

/// `F3D_WHEEL_FLOATS_ALL`: every real a wheel can be given in
/// `f3d_vehicle_add_wheel_with`, [wheelFloats] then the tyre's width and
/// its rolling resistance coefficient.
const int wheelFloatsAll = 10;

/// `F3D_WHEEL_STATE_FLOATS`: reals one wheel takes in
/// `f3d_vehicle_read_wheels`.
const int wheelStateFloats = 14;

/// `F3D_MULTIBODY_MOST_LINKS`: the count of links a multibody has at most,
/// its root among them.
const int multibodyMostLinks = 32;

/// `F3D_MULTIBODY_MOST_DOFS`: the count of degrees of freedom a multibody
/// has at most, a floating root's six and its joints'.
const int multibodyMostDofs = 64;

/// `F3D_SHALLOW_MOST_SOURCES`: the count of springs a water has at most.
const int shallowMostSources = 16;

/// `F3D_SHALLOW_MOST_SPRAY`: the count of pieces of falling water in flight
/// in a world at most.
const int shallowMostSpray = 16384;

/// `F3D_SPRAY_FLOATS`: reals one piece of falling water takes in
/// `f3d_world_read_spray`.
const int sprayFloats = 11;

/// `F3D_SHALLOW_MOST_OUTLETS`: the count of outlets a water has at most.
const int shallowMostOutlets = 8;

/// `F3D_SHALLOW_INFO_FLOATS`: reals `f3d_shallow_info` gives, the substeps
/// of the last step, the steps that wanted more than
/// [shallowMostSubsteps], one while it rests, and the most energy any cell
/// held in joules per square metre.
const int shallowInfoFloats = 4;

/// `F3D_SHALLOW_MOST_SUBSTEPS`: the count of substeps a water's step is cut
/// into at most.
const int shallowMostSubsteps = 64;

/// `F3D_SHALLOW_EXTERNAL_PARAMS`: reals `f3d_shallow_take_external` writes
/// for a water stepped elsewhere, its grid, fluid, wind, edges and the
/// time to step.
const int shallowExternalParams = 24;

/// `F3D_LIP_FLOATS`: reals a lip's face takes in `f3d_shallow_throw_lips`,
/// the water that went over it, its push x and z, and the cell it left.
const int lipFloats = 4;

/// `F3D_EXTERNAL_ON`, `F3D_EXTERNAL_CHANGED`, `F3D_EXTERNAL_RESET` and
/// `F3D_EXTERNAL_FILLED`: what `f3d_shallow_take_external` answers.
abstract final class ExternalBits {
  /// The water is stepped elsewhere.
  static const int on = 1;

  /// Its changes hold something to send.
  static const int changed = 2;

  /// It was set outright, and its whole state is to be sent.
  static const int reset = 4;

  /// What bodies fill of its columns is to be sent.
  static const int filled = 8;
}

/// `F3D_EDGE_WALL`, `F3D_EDGE_OPEN`, `F3D_EDGE_FLOW` and `F3D_EDGE_LEVEL`:
/// what an edge of a water's grid is, `f3d_shallow_set_edge`.
abstract final class EdgeKind {
  /// Nothing crosses the edge.
  static const int wall = 0;

  /// What reaches the edge runs off, and nothing comes in.
  static const int open = 1;

  /// A discharge in cubic metres per second over the whole edge: in where
  /// positive, out where negative.
  static const int flow = 2;

  /// Water outside stands at a height above the grid's origin, and flows
  /// in or out as the surface inside is below or above it.
  static const int level = 3;
}

/// `F3D_SHALLOW_MOST_BUBBLES`: the count of clouds of bubbles in a world at
/// most.
const int shallowMostBubbles = 16384;

/// `F3D_BUBBLE_FLOATS`: reals one cloud of bubbles takes in
/// `f3d_world_read_bubbles`, its place xyz, the bubbles' radius in metres
/// and the air it holds in cubic metres.
const int bubbleFloats = 5;

/// `F3D_SPRAY_SHEET`: a piece of falling water that is a stretch of the
/// sheet that left a lip in one step.
const int spraySheet = 0;

/// `F3D_SPRAY_DROPS`: a piece of falling water that is drops, what a sheet
/// broke into or a splash threw up.
const int sprayDrops = 1;

/// `F3dJointType`: what a joint holds between its two bodies.
abstract final class JointType {
  /// Holds B where it was against A, place and turn.
  static const int fixed = 0;

  /// Holds a point of each together; they turn freely about it.
  static const int spherical = 1;

  /// A hinge: a point together, turning only about the axis.
  static const int revolute = 2;

  /// A slider: no turning, moving only along the axis.
  static const int prismatic = 3;

  /// Two points held a length apart: a rod, a spring or a rope.
  static const int distance = 4;
}

/// `F3dMaterialKind`: the built-in materials a body can be made of.
abstract final class MaterialKind {
  /// Heats and cools at a generic specific heat, and never burns: a new
  /// body's material.
  static const int inert = 0;

  /// A generic wood.
  static const int wood = 1;

  /// A sheet of paper; [paperStack] is a pile.
  static const int paper = 2;

  /// Rubber, which catches fire at about 673 kelvin.
  static const int rubber = 3;

  /// Steel, which does not burn.
  static const int steel = 4;

  /// Stone, which does not burn.
  static const int stone = 5;

  /// Red oak, as boards or beams.
  static const int oak = 6;

  /// Southern pine, as boards.
  static const int pine = 7;

  /// Corrugated board, as boxes are made of.
  static const int cardboard = 8;

  /// A porous bed of dry straw: a thatched roof, a stack, a bale.
  static const int thatch = 9;

  /// Wood charcoal, which glows rather than flames.
  static const int charcoal = 10;

  /// Paraffin wax: a candle's, as a burner's fuel.
  static const int paraffin = 11;

  /// A stack of paper sheets with air between them.
  static const int paperStack = 12;
}

/// `F3dEventKind`: what a step can say happened to a body.
abstract final class EventKind {
  /// The body fell asleep.
  static const int slept = 0;

  /// The body woke.
  static const int woke = 1;

  /// The body caught fire.
  static const int ignited = 2;

  /// The body's fire went out.
  static const int extinguished = 3;

  /// The body's fuel is spent.
  static const int burntOut = 4;

  /// Two bodies came within five millimetres; the second is the other.
  static const int contactBegan = 5;

  /// Two bodies stopped touching; the second is the other.
  static const int contactEnded = 6;

  /// A joint held past its break limits and let go; the event names its two
  /// bodies and the joint is gone.
  static const int jointBroken = 7;

  /// The body came into a liquid.
  static const int wetted = 8;

  /// A burner's flame went out: its body went wholly under a liquid.
  static const int burnerOut = 9;
}

/// `F3D_PARTICLE_FLOATS`: reals one particle takes in `f3d_particles_read`,
/// its position xyz then the life it has left in seconds.
const int particleFloats = 4;

/// `F3D_DEBRIS_INPUT_FLOATS`: reals one body takes in `f3d_debris_add`,
/// position xyz, velocity xyz, radius and mass.
const int debrisInputFloats = 8;

/// `F3D_DEBRIS_FLOATS`: reals one body takes in `f3d_debris_read`, position
/// xyz, orientation xyzw and radius.
const int debrisFloats = 8;

/// `F3D_DEBRIS_STATIC_FLOATS`: reals one still shape, a plane or a box,
/// takes in `f3d_debris_set_statics`.
const int debrisStaticFloats = 8;

/// `F3D_DEBRIS_MAX_STATICS`: the count of still shapes debris holds at
/// most.
const int debrisMaxStatics = 64;

/// `F3D_CLOTH_FLOATS`: reals one cloth point takes, its position xyz and
/// inverse mass, nought for a pinned point.
const int clothFloats = 4;

/// `F3D_CLOTH_MAX_BALLS`: the count of balls `f3d_cloth_set_balls` takes at
/// most.
const int clothMaxBalls = 16;

/// `F3D_CLOTH_STATE_FLOATS`: reals one point takes in
/// `f3d_cloth_write_state` and `f3d_cloth_read_state`, position xyz,
/// velocity xyz and inverse mass.
const int clothStateFloats = 7;

/// `F3D_CLOTH_BALL` and the rest: what each record of
/// `f3d_cloth_set_obstacles` starts with.
abstract final class ClothObstacleKind {
  /// A ball: x, y, z and radius follow.
  static const int ball = 0;

  /// An upright capsule: x, y, z, radius and half height follow.
  static const int capsule = 1;

  /// A convex solid: a count, then that many planes nx, ny, nz, d.
  static const int convex = 2;

  /// A height grid: its origin, cell, columns, rows, depth, then the
  /// heights row by row.
  static const int ground = 3;
}

/// `F3D_FLUID_INPUT_FLOATS`: reals one particle takes in `f3d_fluid_add`,
/// position xyz and velocity xyz.
const int fluidInputFloats = 6;

/// `F3D_FLUID_FLOATS`: reals one particle takes in `f3d_fluid_read`, its
/// position xyz and its density over the density at rest.
const int fluidFloats = 4;

/// `F3D_LIQUID_PARTICLE_FLOATS`: reals one liquid particle takes, position
/// xyz and velocity xyz.
const int liquidParticleFloats = 6;

/// `F3D_LIQUID_PARCEL_FLOATS`: reals one stream parcel takes in
/// `f3d_liquid_parcels`.
const int liquidParcelFloats = 17;

/// `F3D_LIQUID_MODE_FLOATS`: reals one surface mode takes in
/// `f3d_liquid_modes`.
const int liquidModeFloats = 6;

/// `F3D_LIQUID_PIPE_FLOATS`: reals one pipe takes in `f3d_liquid_pipes`.
const int liquidPipeFloats = 11;

/// `F3D_LIQUID_BODY_FLOATS`: reals one floating body takes in
/// `f3d_liquid_floats`, velocity xyz and inverse mass.
const int liquidBodyFloats = 4;

/// `F3D_LIQUID_PUSH_FLOATS`: reals one push takes in `f3d_liquid_floats`,
/// the body, its shape, three sizes, the volume under the surface and the
/// liquid's density and viscosity.
const int liquidPushFloats = 8;

/// `F3D_LIQUID_SPHERE` and the rest: the shape a push of
/// `f3d_liquid_floats` names.
abstract final class LiquidFloatShape {
  /// A sphere; its first size is the radius.
  static const int sphere = 0;

  /// A box; its sizes are the half extents.
  static const int box = 1;

  /// An upright capsule; its sizes are the radius and the half height.
  static const int capsule = 2;

  /// Any other shape; its sizes are not read.
  static const int other = 3;
}

/// `F3D_LIQUID_PLANE` and the rest: what each wall record of
/// `f3d_liquid_particles` and `f3d_liquid_parcels` starts with.
abstract final class LiquidWallKind {
  /// A plane: nx, ny, nz and an offset, clear where n · p >= offset.
  static const int plane = 0;

  /// The inside of a vessel turned from a profile about its y axis.
  static const int inside = 1;

  /// The outside of such a vessel.
  static const int outside = 2;
}
