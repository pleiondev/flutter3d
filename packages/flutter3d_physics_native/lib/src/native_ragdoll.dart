/// A ragdoll in the core — N1: a capsule a bone, a joint where each bone
/// meets its parent, built from bones in world space and knowing nothing of
/// a scene.
///
/// ## Built at rest, put where the pose is
///
/// A joint's limits are taken from how its bodies stand when it is made: a
/// cone about the axis they had then, a twist from the turn they had then,
/// and a [RagdollSwing]'s range from the anatomical position, read against
/// the skeleton's forward and up as they stand at rest. Made where an
/// animation happened to leave a body — a monster struck mid-stride, its
/// knee bent — the limits would be centred on that stride. So the bodies
/// are made in the skeleton's rest pose, joined there, and only then moved
/// to where the animation has them, with the velocities it gave them: the
/// limits are a body's, the starting pose and momentum the moment's.
///
/// ## Tissue, not friction
///
/// What brings a limp body to rest is its joints' tissue ([JointTissue]):
/// viscous damping, a torque in proportion to how fast a joint turns, and
/// soft limits, which give a little past the end of a joint's range rather
/// than stopping it dead, stiffening the further they give, as measured
/// tissue does, from a stiffness at the limit for each group of joints
/// ([JointGroup]). A fixed friction torque held a limb wherever it
/// was slow enough, and a body that came down on its arms stayed propped on
/// them.
///
/// ## Tone, fading
///
/// What holds a body as the blow lands is its muscles ([MuscleTone]): at
/// each joint a drive pulls it towards the posture it had when it went
/// limp, as stiff as a muscle's tone and never stronger than the muscle,
/// and fades over a few tenths of a second to what a corpse keeps. With
/// tissue alone a relaxed spine struck hard bent a third of a radian past
/// its range, and a runner struck low in the back sat propped on its
/// elbows; with tone the body takes the blow as one and then goes limp.
///
/// A bone's frame and its capsule differ — a capsule lies along y from the
/// bone's head to its tail, the bone's own axes are whatever the rig chose —
/// so each bone keeps the offset between the two, taken at rest, and is read
/// back as its body times that offset.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Portable, RigidPose;
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show Confidence, ConstantLaw, InelasticProperties;
import 'package:vector_math/vector_math.dart';

import 'native_dynamics.dart';
import 'native_world.dart';

/// Which part of a body a joint is: what a [JointTissue] reads the
/// stiffness at the end of its range by.
///
/// **Open.** These are the groups `JointTissue.human` has a stiffness for;
/// a rig with a tail or wings names its own, `const JointGroup('tail')`,
/// and gives its tissue a [JointGroupStiffness] for it. Two groups of one
/// [name] are one group.
final class JointGroup {
  /// A group called [name]; two of one name are equal.
  const JointGroup(this.name);

  /// What the group is called, and what makes two groups one.
  final String name;

  /// The thoracolumbar spine, between the pelvis and the chest.
  static const JointGroup spine = JointGroup('spine');

  /// The cervical spine, between the chest and the head.
  static const JointGroup neck = JointGroup('neck');

  /// The glenohumeral joint, between the chest and the upper arm.
  static const JointGroup shoulder = JointGroup('shoulder');

  /// The elbow, between the upper arm and the forearm.
  static const JointGroup elbow = JointGroup('elbow');

  /// The hip, between the pelvis and the thigh.
  static const JointGroup hip = JointGroup('hip');

  /// The knee, between the thigh and the shin.
  static const JointGroup knee = JointGroup('knee');

  @override
  bool operator ==(Object other) => other is JointGroup && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'JointGroup($name)';
}

/// How a bone is held to its parent, and which [group] of joints it is —
/// null for one a [JointTissue] has no stiffness of its own for.
abstract final class RagdollJoint {
  /// A joint of [group], or of none.
  const RagdollJoint({this.group});

  /// The group a [JointTissue] and a [MuscleTone] read this joint's
  /// stiffness and tone by; null for one of no group, which takes their
  /// defaults.
  final JointGroup? group;
}

/// A ball: its swing within [cone] radians of the bone's direction at rest,
/// its twist about it within [twistLower]..[twistUpper]. A hip, a shoulder,
/// the spine, the neck.
final class RagdollBall extends RagdollJoint {
  /// A ball of the given [cone] and twist range, all in radians.
  const RagdollBall({
    required this.cone,
    required this.twistLower,
    required this.twistUpper,
    super.group,
  });

  /// The most the bone swings from its direction at rest, and the least and
  /// most it twists about it, in radians.
  final double cone, twistLower, twistUpper;
}

/// A ball held to a joint's range of motion: from the anatomical position,
/// the bone swings forward ([flexion]) and back ([extension]) along the
/// skeleton's forward, out from the body's midline ([lateral]) and in
/// towards it ([medial]), with an ellipse through the four between them, and
/// twists by at most [twist] either way from how it stood at rest. Radians,
/// each above nought and below 3: the core measures a swing short of a half
/// turn. The spine, the neck, a shoulder, a hip.
///
/// **Measured from the anatomical position, not the rest pose.** A bone that
/// [hangs] — an arm, a leg — swings from the skeleton's down; one that does
/// not — the spine, the neck — from its up. A rig bound in a T-pose has its
/// arms out at a right angle to that, a quarter of the way through their
/// abduction, and they are limited as an arm, not as a T. A bone on the
/// midline, the spine and the neck, bends the same way to either side, and
/// takes [lateral] for both.
///
/// Forward means the bone's far end moves ahead: a thigh lifted, an arm
/// raised in front, a spine bent over. A knee bends the other way, and is a
/// [RagdollBend].
final class RagdollSwing extends RagdollJoint {
  /// A swing of the given range, in radians; [medial] takes [lateral] when
  /// null, as a bone on the midline does.
  const RagdollSwing({
    required this.flexion,
    required this.extension,
    required this.lateral,
    double? medial,
    required this.twist,
    this.hangs = false,
    super.group,
  }) : medial = medial ?? lateral;

  /// The most the bone swings forward, back, out and in, and twists either
  /// way, in radians, each above nought and below 3.
  final double flexion, extension, lateral, medial, twist;

  /// Whether the bone hangs from its joint in the anatomical position, as a
  /// limb does, rather than standing on it, as the spine does.
  final bool hangs;
}

/// How stiff one [group]'s tissue is at the end of each side of its range,
/// N·m/rad: the k0 a [JointTissue] stiffens from past the limit.
///
/// A [RagdollSwing] takes [flexion] and [extension] at its limits forward
/// and back, [lateral] and [medial] at its limits out and in, and [twist]
/// at both of its twist's; a [RagdollHinge] [flexion] where it stops
/// bending and [extension] where it stops straightening; a [RagdollBall]
/// [flexion] at its cone and [twist] at its twist's.
final class JointGroupStiffness {
  /// [group]'s stiffness at each side of its range, N·m/rad; [medial]
  /// takes [lateral] when null.
  const JointGroupStiffness(
    this.group, {
    required this.flexion,
    required this.extension,
    required this.lateral,
    double? medial,
    required this.twist,
  }) : medial = medial ?? lateral;

  /// The same [stiffness] at every limit.
  const JointGroupStiffness.uniform(this.group, double stiffness)
    : flexion = stiffness,
      extension = stiffness,
      lateral = stiffness,
      medial = stiffness,
      twist = stiffness;

  /// The group of joints this stiffness is for.
  final JointGroup group;

  /// N·m/rad, each above nought.
  final double flexion, extension, lateral, medial, twist;
}

/// What a ragdoll's joints are made of: what damps their turning and what
/// holds them at the end of their range — in place of a friction torque.
///
/// - [damping]: viscous, N·m·s/rad, the passive damping of a relaxed joint;
/// - [limitStiffness]: N·m/rad, how stiff a joint is at the end of its
///   range, for a joint of a group [groups] does not name; nought for
///   limits as hard as the core holds a joint, every group's included;
/// - [limitGrowth]: per radian, how the tissue stiffens past the limit:
///   δ past it, it holds back (k0 / b)(e^(bδ) − 1) N·m and is k0 e^(bδ)
///   stiff, k0 the stiffness at the limit and b the growth; nought for a
///   linear spring, k0 δ;
/// - [groups]: the stiffness at the limit of each group of joints, side by
///   side ([JointGroupStiffness]), where it is not [limitStiffness];
/// - [inelastic]: the tissue's inelastic group, whose loss factor η makes
///   the damping ratio of that give, η/2.
final class JointTissue {
  /// Tissue of the given [damping], [limitStiffness] and [inelastic]
  /// group; linear past the limit and with no group of its own unless
  /// [limitGrowth] and [groups] say otherwise.
  const JointTissue({
    required this.damping,
    required this.limitStiffness,
    this.limitGrowth = 0.0,
    this.groups = const <JointGroupStiffness>[],
    required this.inelastic,
  });

  /// N·m·s/rad.
  final double damping;

  /// N·m/rad.
  final double limitStiffness;

  /// Per radian.
  final double limitGrowth;

  /// The stiffness at the limit of each group it names; a group it does
  /// not name takes [limitStiffness].
  final List<JointGroupStiffness> groups;

  /// Where [limitRatio] comes from.
  final InelasticProperties inelastic;

  /// The damping ratio of a joint's give past its range: half the tissue's
  /// loss factor, nought where it has none. The damping grows with the
  /// stiffness past the limit, at this ratio to it.
  double get limitRatio => (inelastic.lossFactor?.value ?? 0.0) * 0.5;

  /// [group]'s stiffness at the end of its range; null for a group [groups]
  /// does not name, which takes [limitStiffness] at every limit.
  JointGroupStiffness? stiffnessOf(JointGroup? group) {
    for (final stiffness in groups) {
      if (stiffness.group == group) return stiffness;
    }
    return null;
  }

  /// A relaxed adult's joints.
  ///
  /// - **Damping 1.0 N·m·s/rad**: the passive damping of the knee in
  ///   flexion from pendulum drops, b ≈ 1.0 N·m·s/rad (Riener and Fuhr,
  ///   "Patient-driven control of FES-supported standing up: a simulation
  ///   study", IEEE Trans. Rehabil. Eng. 6, 1998, as quoted in US patent
  ///   8,108,190; not read in the paper). Every joint takes the knee's: an
  ///   estimate for the others.
  /// - **Growth 8.6 /rad** past the limit: the knee's capsule and
  ///   ligaments resisting hyperextension, the term exp(2.220 − 0.150 φ),
  ///   φ in degrees, of Riener and Edrich's passive knee moment
  ///   ("Identification of passive elastic joint moments in the lower
  ///   extremities", J. Biomech. 32, 1999; its coefficients read in US
  ///   patent 8,108,190, not in the paper): 0.150 a degree, the stiffness
  ///   doubling every 4.6°. Every joint takes the knee's. Measured passive
  ///   moments stiffen this way past the end of a range; a linear spring
  ///   at the stiffness measured there is too soft a few degrees on.
  /// - **Stiffness at the limit**, k0, by group, N·m/rad: in vivo, relaxed,
  ///   in the last part of the range where measured.
  ///   - Spine: flexion 150, lateral 300 and twist 80 from the 4th quartile
  ///     of the range in Watt, Callaway and Williams' meta-analysis ("In
  ///     vivo through-range passive stiffness of the lumbar spine", Med.
  ///     Biol. Eng. Comput. 60, 2022, p. 2133: 2.36, 5.03 and 1.33 N·m/deg);
  ///     extension 60 from McGill, Seguin and Bennett (Spine 19, 1994) as
  ///     the same meta-analysis tabulates it, 0.86 N·m/deg at 22°.
  ///   - Neck 60: between the Hybrid III dummy's neck corridors (49 CFR
  ///     572.33, secants of 41 in extension and 79 in flexion) and the
  ///     failure secants of the male O–C2 segment (Nightingale et al., J.
  ///     Biomech. 40, 2007: 38 and 67). A relaxed neck measures 4 to 8 in
  ///     vivo, too soft to hold a head without its muscles.
  ///   - Hip 100: Amankwah, Triolo and Kirsch's passive hip moment
  ///     (J. Rehabil. Res. Dev. 41, 2004, p. 15), 66 to 127 between 90° and
  ///     120° of flexion.
  ///   - Shoulder 100: **an estimate**, no measurement past the end of the
  ///     range found; the hip's.
  ///   - Knee: extension 180, Riener and Edrich's moment 5° past straight;
  ///     flexion 90, the same at 150° of flexion; its sides and twist, which
  ///     a hinge does not have, the extension's.
  ///   - Elbow: **an estimate**, no source found; the knee's.
  ///   - A joint of no group: 100, the hip's, an estimate.
  ///
  ///   These replace one stiffness of 3000 N·m/rad, linear, at every joint:
  ///   an estimate without a source, chosen so the trunk's 90 N·m on the
  ///   hip carried it three hundredths of a radian past its limit. Measured
  ///   tissue is 10 to 50 times softer at the limit; on this curve 3000 is
  ///   the spine's stiffness in flexion 0.35 rad past it.
  /// - **Loss factor 0.011**: tendon, which loses about 7 % of the work
  ///   done on it in a cycle (Ker, "Dynamic tensile properties of the
  ///   plantaris tendon of sheep", J. Exp. Biol. 93, 1981); η = ψ / 2π.
  ///   The catalog has no tissue to take it from.
  static const JointTissue human = JointTissue(
    damping: 1.0,
    limitStiffness: 100.0,
    limitGrowth: 8.6,
    groups: <JointGroupStiffness>[
      JointGroupStiffness(
        JointGroup.spine,
        flexion: 150.0,
        extension: 60.0,
        lateral: 300.0,
        twist: 80.0,
      ),
      JointGroupStiffness.uniform(JointGroup.neck, 60.0),
      JointGroupStiffness.uniform(JointGroup.hip, 100.0),
      JointGroupStiffness.uniform(JointGroup.shoulder, 100.0),
      JointGroupStiffness(
        JointGroup.knee,
        flexion: 90.0,
        extension: 180.0,
        lateral: 180.0,
        twist: 180.0,
      ),
      JointGroupStiffness(
        JointGroup.elbow,
        flexion: 90.0,
        extension: 180.0,
        lateral: 180.0,
        twist: 180.0,
      ),
    ],
    inelastic: InelasticProperties(
      lossFactor: ConstantLaw(
        0.011,
        confidence: Confidence.handbook,
        source:
            'Ker, Dynamic tensile properties of the plantaris tendon of '
            'sheep, J. Exp. Biol. 93 (1981): about 7 % of the work lost a '
            'cycle; eta = psi / (2 pi)',
      ),
      source: 'Ker (1981), tendon; no tissue in the catalog (flutter3d_matter)',
    ),
  );
}

/// How strongly one [group]'s muscles hold it while their tone is up: a
/// drive's [stiffness], N·m/rad, [damping], N·m·s/rad, and the most torque
/// they put out, [maxTorque], N·m.
final class JointGroupTone {
  /// [group]'s tone: a drive of [stiffness] and [damping], at most
  /// [maxTorque].
  const JointGroupTone(
    this.group, {
    required this.stiffness,
    required this.damping,
    required this.maxTorque,
  });

  /// The group of joints this tone is for.
  final JointGroup group;

  /// N·m/rad, nought or more.
  final double stiffness;

  /// N·m·s/rad, nought or more.
  final double damping;

  /// N·m, nought or more.
  final double maxTorque;
}

/// A ragdoll's muscle tone: an active torque at each joint that pulls it
/// towards the posture the body had when it went limp — a stiffness and a
/// damping, never more than a most torque — and fades, from all of it to
/// [floor] of it as e^(−t / [fade]), so a body knocked out goes limp, but
/// not at once.
///
/// What holds a living body against a blow is not stiffer tissue but its
/// muscles' tone and co-contraction: a relaxed spine struck hard gives a
/// third of a radian past its range on its tissue alone, where a body with
/// its tone up gives little. A joint of a group [groups] does not name
/// takes [stiffness], [damping] and [maxTorque].
final class MuscleTone {
  /// Tone of the given strength for a joint of no named group; it keeps
  /// [floor] of itself, nought unless given, after a fade of time constant
  /// [fade] seconds, nought (no fade) unless given.
  const MuscleTone({
    required this.stiffness,
    required this.damping,
    required this.maxTorque,
    this.groups = const <JointGroupTone>[],
    this.floor = 0.0,
    this.fade = 0.0,
  });

  /// N·m/rad, for a joint of no group [groups] names.
  final double stiffness;

  /// N·m·s/rad, for a joint of no group [groups] names.
  final double damping;

  /// N·m, for a joint of no group [groups] names.
  final double maxTorque;

  /// The tone of each group it names; a group it does not name takes
  /// [stiffness], [damping] and [maxTorque].
  final List<JointGroupTone> groups;

  /// What share of its tone the body keeps once faded, nought or more.
  final double floor;

  /// The time constant of the fade, seconds; nought keeps the tone up.
  final double fade;

  /// [group]'s tone: its own where [groups] names it, else this one's.
  JointGroupTone toneOf(JointGroup? group) {
    for (final tone in groups) {
      if (tone.group == group) return tone;
    }
    return JointGroupTone(
      group ?? const JointGroup('other'),
      stiffness: stiffness,
      damping: damping,
      maxTorque: maxTorque,
    );
  }

  /// An adult killed or knocked out: tone up at the blow, gone within a
  /// second.
  ///
  /// - **Stiffness**, N·m/rad, of muscles at a low level of effort:
  ///   - Spine 300: between the trunk's intrinsic stiffness in flexion,
  ///     109 on average (Brown and McGill, "The intrinsic stiffness of the
  ///     in vivo lumbar spine in response to quick releases", J.
  ///     Electromyogr. Kinesiol. 19, 2009, p. 727), and 143 to 573 at 20 to
  ///     40 % of the greatest effort (Gardner-Morse and Stokes, "Trunk
  ///     stiffness increases with steady-state effort", J. Biomech. 34,
  ///     2001, p. 457, 14.5 and 19.8 N/mm over a lever of 0.1 to 0.2 m, as
  ///     they convert it); reflexes included it is about 1200 (Cholewicki,
  ///     Simons and Radebold, J. Biomech. 33, 2000, p. 1377). The number in
  ///     that range is **an estimate**.
  ///   - Neck 50: the low end of 46 to 199 measured at 30 and 50 % of the
  ///     greatest effort in flexion (Portero et al., PLoS One 10, 2015,
  ///     e0139333), where stiffness grows as 4.1 times the torque.
  ///   - Elbow 25: during slow movement (Xu and Hollerbach, IEEE Trans.
  ///     Biomed. Eng. 46, 1999, p. 409).
  ///   - Shoulder 30, hip 100, knee 50 and any other joint 50: **estimates**,
  ///     no measurement found.
  /// - **Damping**, N·m·s/rad: the spine's 11, one trial of Brown and
  ///   McGill's (the fit was nought in most); the elbow's 0.8 from a
  ///   damping ratio of 0.3 (Xu and Hollerbach) over a forearm and hand of
  ///   about 0.08 kg·m², an inference; the rest **estimates** of the same
  ///   order.
  /// - **Most torque**, N·m: the greatest voluntary isometric torque of
  ///   adult men, the weaker way of each joint: the neck's 30 in flexion
  ///   (Vasavada, Li and Delp, Spine 26, 2001, p. 1904); the shoulder's 74
  ///   in abduction and the elbow's 60 in extension (Holzbaur et al., J.
  ///   Biomech. 40, 2007, p. 2442); the hip's 141 in flexion and the knee's
  ///   109 in flexion (Anderson, Madigan and Nussbaum, J. Biomech. 40, 2007,
  ///   p. 3105, their peak normalised by body weight and height, taken at
  ///   72.8 kg and 1.748 m). The spine's 200 and any other joint's 60 are
  ///   **estimates**: no table of the trunk's was found.
  /// - **Fade 0.2 s to 5 %**: **estimates**. Muscle relaxes within tens of
  ///   milliseconds of its drive stopping; what a body does over the second
  ///   after is gravity's, not the fade's. What is left, 5 %, is about the
  ///   trunk's passive stiffness, 7 to 18 N·m/rad (McGill, Seguin and
  ///   Bennett, Spine 19, 1994, as Gardner-Morse and Stokes quote it), over
  ///   its active.
  static const MuscleTone human = MuscleTone(
    stiffness: 50.0,
    damping: 1.0,
    maxTorque: 60.0,
    floor: 0.05,
    fade: 0.2,
    groups: <JointGroupTone>[
      JointGroupTone(
        JointGroup.spine,
        stiffness: 300.0,
        damping: 11.0,
        maxTorque: 200.0,
      ),
      JointGroupTone(
        JointGroup.neck,
        stiffness: 50.0,
        damping: 1.0,
        maxTorque: 30.0,
      ),
      JointGroupTone(
        JointGroup.shoulder,
        stiffness: 30.0,
        damping: 1.0,
        maxTorque: 74.0,
      ),
      JointGroupTone(
        JointGroup.elbow,
        stiffness: 25.0,
        damping: 0.8,
        maxTorque: 60.0,
      ),
      JointGroupTone(
        JointGroup.hip,
        stiffness: 100.0,
        damping: 2.0,
        maxTorque: 141.0,
      ),
      JointGroupTone(
        JointGroup.knee,
        stiffness: 50.0,
        damping: 1.0,
        maxTorque: 109.0,
      ),
    ],
  );
}

/// A hinge about [axis], in the bone's own frame, from [lower] to [upper]
/// radians from rest. A knee, an elbow.
///
/// Of the two limits, the one further from rest is taken as where the
/// joint stops bending, its flexion, and the nearer as where it stops
/// straightening, its extension: a knee bends 2.4 rad one way and next to
/// nothing the other, whichever way its axis points.
final class RagdollHinge extends RagdollJoint {
  /// A hinge about [axis] from [lower] to [upper] radians.
  const RagdollHinge({
    required this.axis,
    required this.lower,
    required this.upper,
    super.group,
  });

  /// The axis it turns about, in the bone's own frame.
  final Vector3 axis;

  /// The least and most it turns from rest, in radians.
  final double lower, upper;
}

/// A hinge whose axis the rest pose shows: a knee or an elbow a rig binds a
/// little bent, as most do for their IK, bends about the axis across its
/// bone and its parent's, the way it is already bent — from straight to
/// [most] radians of bend. Bound straighter than [least] radians, the rest
/// pose does not say which way, and it is held as [otherwise]. Either is
/// of the bend's [group] unless [otherwise] names its own.
final class RagdollBend extends RagdollJoint {
  /// A bend of at most [most] radians, 2.4 unless given, read from a rest
  /// pose bent at least [least] radians, 0.05 unless given, and held as
  /// [otherwise] where it is not.
  const RagdollBend({
    this.most = 2.4,
    this.least = 0.05,
    required this.otherwise,
    super.group,
  });

  /// The most it bends from straight, and the least bend in the rest pose
  /// that says which way it bends, in radians.
  final double most, least;

  /// How the bone is held when its rest pose is straighter than [least].
  final RagdollJoint otherwise;
}

/// One bone, in world space: where it starts ([head], the joint with its
/// parent) and ends ([tail], where its capsule stops), its frame, how thick
/// and heavy it is, and how it is held. [parent] is an index into the list
/// the ragdoll is built from, earlier than this one, or -1 for the root.
final class RagdollBone {
  /// A bone as given; [joint] null for the root.
  const RagdollBone({
    required this.name,
    required this.parent,
    required this.head,
    required this.tail,
    required this.orientation,
    required this.radius,
    required this.mass,
    this.joint,
  });

  /// The bone's name in the rig.
  final String name;

  /// The index of its parent in the bone list, earlier than this one; -1
  /// for the root.
  final int parent;

  /// Where the bone starts, at the joint with its parent, and where its
  /// capsule ends, in world space.
  final Vector3 head, tail;

  /// The bone's own frame in world space, as the rig has it.
  final Quaternion orientation;

  /// The capsule's radius, in metres, and the bone's mass, in kilograms.
  final double radius, mass;

  /// How it is held to its parent; null for the root, which has none.
  final RagdollJoint? joint;
}

/// A ragdoll in a [NativeWorld]: a capsule body for each [RagdollBone],
/// joined to its parent as its [RagdollJoint] says.
final class NativeRagdoll {
  /// Made in [world] from [rest], the bones at rest, then moved to [pose],
  /// one pose a bone, moving as [velocity] and [spin] say when they are
  /// given. Every joint is made of [tissue]: it damps the joint's turning
  /// and softens its limits, or the ragdoll never comes to rest. [tone] is
  /// how its muscles hold it at the posture of [pose], or of [rest] without
  /// one, fading from the moment it is made; null for a body limp from the
  /// start, which steps as one made before tone did.
  ///
  /// [forward] and [up] are the skeleton's, in the world, as it stands at
  /// rest — which way its chest faces and which way its head is from its
  /// feet; a [RagdollSwing] is measured against them. Unless given, the
  /// figure faces +z and stands up +y, as glTF's do. When the world is a
  /// [NativeDynamics]', [dynamics] keeps these bodies through its restores.
  ///
  /// [layer] and [mask] are its bodies' collision filter. A ragdoll in the
  /// core a game's characters move and its rays are cast in is met by them
  /// as a body nobody's collider stands for, unless it is on a layer their
  /// masks leave out — or in a core of its own, as the dungeon's corpses
  /// are.
  NativeRagdoll(
    this.world,
    List<RagdollBone> rest, {
    List<RigidPose>? pose,
    List<Vector3>? velocity,
    List<Vector3>? spin,
    JointTissue tissue = JointTissue.human,
    MuscleTone? tone = MuscleTone.human,
    Vector3? forward,
    Vector3? up,
    NativeDynamics? dynamics,
    int layer = 1,
    int mask = 0xffffffff,
  }) : bones = List<RagdollBone>.unmodifiable(rest),
       _dynamics = dynamics {
    for (var i = 0; i < rest.length; i++) {
      final bone = rest[i];
      if (bone.parent >= i) {
        throw ArgumentError.value(
          bone.parent,
          'rest[$i].parent',
          'not an earlier bone',
        );
      }
      final along = bone.tail - bone.head;
      final length = along.length;
      final turn = _alongY(along);
      final center = (bone.head + bone.tail) * 0.5;
      final body = world.addBody(position: center, mass: bone.mass);
      world
        ..setShape(
          body,
          NativeShape.capsule(
            bone.radius,
            (length * 0.5 - bone.radius).clamp(0.01, double.infinity),
          ),
        )
        ..setOrientation(body, turn)
        ..setCollisionFilter(body, layer: layer, mask: mask);
      _bodies.add(body);
      // The bone's frame from the body's: inverse(body) · bone.
      final inverse = turn.conjugated();
      _offsetTurn.add(inverse * bone.orientation);
      _offsetAt.add(turnBy(inverse, bone.head - center));
      dynamics?.keep(body);
    }
    final ahead = (forward ?? Vector3(0.0, 0.0, 1.0)).normalized();
    final above = (up ?? Vector3(0.0, 1.0, 0.0)).normalized();
    for (var i = 0; i < rest.length; i++) {
      final bone = rest[i];
      if (bone.parent < 0) continue;
      final a = _bodies[bone.parent], b = _bodies[i];
      final direction = (bone.tail - bone.head).normalized();
      final NativeJoint joint;
      final held = _resolved(bone, rest[bone.parent]);
      _held[i] = held;
      switch (held) {
        case RagdollHinge(:final axis, :final lower, :final upper):
          joint = world.createJoint(
            NativeJointType.revolute,
            a,
            b,
            anchor: bone.head,
            axis: turnBy(bone.orientation, axis),
          );
          world.setJointLimits(joint, (lower: lower, upper: upper));
        case RagdollBall(:final cone, :final twistLower, :final twistUpper):
          joint = world.createJoint(
            NativeJointType.spherical,
            a,
            b,
            anchor: bone.head,
            axis: direction,
          );
          world
            ..setJointCone(joint, cone)
            ..setJointLimits(joint, (lower: twistLower, upper: twistUpper));
        case RagdollSwing():
          joint = world.createJoint(
            NativeJointType.spherical,
            a,
            b,
            anchor: bone.head,
            axis: direction,
          );
          world
            ..setJointSwing(
              joint,
              _swingOf(held, bone, rest.first, ahead, above),
            )
            ..setJointLimits(joint, (lower: -held.twist, upper: held.twist));
        case null:
          joint = world.createJoint(
            NativeJointType.fixed,
            a,
            b,
            anchor: bone.head,
          );
        case RagdollBend():
          throw StateError('a bend is resolved against the rest pose first');
        default:
          throw UnsupportedError('the native core has no joint for $held');
      }
      if (held != null) {
        world.setJointDamping(joint, tissue.damping);
        _soften(world, joint, tissue, held, bone, rest.first, ahead, above);
      }
      _joints.add(joint);
      _jointOf[i] = joint;
    }
    if (pose != null) place(pose, velocity: velocity, spin: spin);
    if (tone != null) _toneUp(tone);
  }

  /// Every jointed bone's drive, of [tone]'s group's strength, pulling it
  /// towards the posture the bodies have now, fading at once.
  void _toneUp(MuscleTone tone) {
    for (final MapEntry(key: i, value: joint) in _jointOf.entries) {
      final held = _held[i];
      if (held == null) continue;
      final strength = tone.toneOf(held.group ?? bones[i].joint?.group);
      if (!(strength.maxTorque > 0.0) ||
          !(strength.stiffness > 0.0 || strength.damping > 0.0)) {
        continue;
      }
      final a = world.orientationOf(_bodies[bones[i].parent]);
      final b = world.orientationOf(_bodies[i]);
      world
        ..setJointDrive(
          joint,
          JointDrive(
            target: a.conjugated() * b,
            stiffness: strength.stiffness,
            damping: strength.damping,
            maxTorque: strength.maxTorque,
          ),
        )
        ..setJointDriveFade(joint, floor: tone.floor, seconds: tone.fade);
    }
  }

  /// How much of its tone the ragdoll still has, a fraction from 1 down to
  /// [MuscleTone.floor]: the level of its joints' drives, the first jointed
  /// bone's; nought for a ragdoll made without tone.
  double get toneLevel {
    for (final joint in _jointOf.values) {
      final level = world.jointDriveLevel(joint);
      if (level > 0.0) return level;
    }
    return 0.0;
  }

  /// The world the ragdoll's bodies and joints are in.
  final NativeWorld world;

  /// The bones it was built from, in the order its bodies are.
  final List<RagdollBone> bones;
  final NativeDynamics? _dynamics;
  final List<NativeBody> _bodies = <NativeBody>[];
  final List<NativeJoint> _joints = <NativeJoint>[];
  final Map<int, NativeJoint> _jointOf = <int, NativeJoint>{};
  final Map<int, RagdollJoint?> _held = <int, RagdollJoint?>{};
  final List<Quaternion> _offsetTurn = <Quaternion>[];
  final List<Vector3> _offsetAt = <Vector3>[];

  /// How bone [index] came to be held: a [RagdollBend] as the hinge or the
  /// fallback its rest pose made it; null for the root and a fixed joint.
  RagdollJoint? heldAs(int index) => _held[index];

  /// The joint holding bone [index] to its parent; null for the root. To
  /// read how far a knee has bent, or set a motor on it.
  NativeJoint? jointOf(int index) => _jointOf[index];

  /// The core's body for bone [index]: to strike it, or to read its contacts.
  NativeBody bodyOf(int index) => _bodies[index];

  /// Puts every bone at [pose] — a pose a bone, in world space — moving at
  /// [velocity] and turning at [spin] where they are given, nought where not.
  void place(
    List<RigidPose> pose, {
    List<Vector3>? velocity,
    List<Vector3>? spin,
  }) {
    for (var i = 0; i < _bodies.length; i++) {
      // body = bone · inverse(offset).
      final turn = pose[i].orientation * _offsetTurn[i].conjugated();
      final at = pose[i].position - turnBy(turn, _offsetAt[i]);
      world
        ..setOrientation(_bodies[i], turn)
        ..setPosition(_bodies[i], at)
        ..setVelocity(_bodies[i], velocity?[i] ?? Vector3.zero())
        ..setAngularVelocity(_bodies[i], spin?[i] ?? Vector3.zero());
    }
  }

  /// Where bone [index] is now, as its body has it.
  RigidPose poseOf(int index) {
    final turn = world.orientationOf(_bodies[index]);
    return RigidPose(
      position:
          world.localPositionOf(_bodies[index]) +
          turnBy(turn, _offsetAt[index]),
      orientation: turn * _offsetTurn[index],
    );
  }

  /// Whether every bone has come to rest.
  bool get isAsleep => _bodies.every(world.isAsleep);

  /// Takes the ragdoll out of the world.
  void dispose() {
    for (final joint in _joints) {
      world.removeJoint(joint);
    }
    for (final body in _bodies) {
      world.removeBody(body);
      _dynamics?.release(body);
    }
    _joints.clear();
    _bodies.clear();
  }
}

/// [bone]'s joint, a [RagdollBend] made the hinge or the fallback the rest
/// pose says.
RagdollJoint? _resolved(RagdollBone bone, RagdollBone parent) {
  final held = bone.joint;
  if (held is! RagdollBend) return held;
  final up = (parent.tail - parent.head).normalized();
  final down = (bone.tail - bone.head).normalized();
  final across = up.cross(down);
  final bent = Portable.atan2(across.length, up.dot(down));
  if (bent < held.least) return held.otherwise;
  // Turning the bone about up × down by a positive angle bends it further:
  // from straight (minus the rest bend) to the most it bends.
  return RagdollHinge(
    axis: turnBy(bone.orientation.conjugated(), across.normalized()),
    lower: -bent,
    upper: held.most - bent,
    group: held.group,
  );
}

/// [joint], holding [bone] as [held] says, made of [tissue]: its limits soft
/// at the stiffness of [held]'s group at each, stiffening past them at the
/// tissue's growth; hard where the tissue's limit stiffness is nought.
void _soften(
  NativeWorld world,
  NativeJoint joint,
  JointTissue tissue,
  RagdollJoint held,
  RagdollBone bone,
  RagdollBone root,
  Vector3 ahead,
  Vector3 up,
) {
  if (!(tissue.limitStiffness > 0.0)) {
    world.setJointLimitSoftness(joint, null);
    return;
  }
  final group = tissue.stiffnessOf(held.group ?? bone.joint?.group);
  // The joint's own stiffness, where it has no stiffness at a limit: a
  // cone's.
  world.setJointLimitSoftness(joint, (
    stiffness: group?.flexion ?? tissue.limitStiffness,
    ratio: tissue.limitRatio,
  ));
  if (group == null) {
    world.setJointLimitStiffness(
      joint,
      tissue.limitGrowth > 0.0
          ? JointLimitStiffness(growth: tissue.limitGrowth)
          : null,
    );
    return;
  }
  final (toSide, fromSide) = held is RagdollSwing
      ? _sidesOf(bone, root, ahead, up, held.hangs)
      : (true, true);
  world.setJointLimitStiffness(joint, switch (held) {
    // The limit further from rest is where it stops bending.
    RagdollHinge(:final lower, :final upper) => JointLimitStiffness(
      growth: tissue.limitGrowth,
      lower: lower.abs() > upper.abs() ? group.flexion : group.extension,
      upper: lower.abs() > upper.abs() ? group.extension : group.flexion,
    ),
    RagdollSwing() => JointLimitStiffness(
      growth: tissue.limitGrowth,
      lower: group.twist,
      upper: group.twist,
      forward: group.flexion,
      back: group.extension,
      toSide: toSide ? group.lateral : group.medial,
      fromSide: fromSide ? group.lateral : group.medial,
    ),
    _ => JointLimitStiffness(
      growth: tissue.limitGrowth,
      lower: group.twist,
      upper: group.twist,
    ),
  });
}

/// Whether the core's side, neutral × [ahead], and the side away from it
/// take a swing's lateral limit for [bone], rather than its medial one —
/// both for a bone on the midline. See [_swingOf].
(bool, bool) _sidesOf(
  RagdollBone bone,
  RagdollBone root,
  Vector3 ahead,
  Vector3 up,
  bool hangs,
) {
  final neutral = hangs ? -up : up.clone();
  final side = neutral.cross(ahead);
  final across = (bone.head - root.head).dot(ahead.cross(up));
  final midline = across.abs() <= 0.1 * bone.head.distanceTo(bone.tail);
  final outward = side.dot(ahead.cross(up)) * across > 0.0;
  return (midline || outward, midline || !outward);
}

/// [swing]'s limits for [bone] as the core takes them: measured from the
/// skeleton's up, or its down for a bone that hangs, with forward along
/// [ahead]. The core's side is neutral × ahead; for a bone off the midline —
/// its head further from [root]'s across the body than a tenth of its
/// length — that side is lateral where it points away from the midline and
/// medial where it points towards it.
JointSwing _swingOf(
  RagdollSwing swing,
  RagdollBone bone,
  RagdollBone root,
  Vector3 ahead,
  Vector3 up,
) {
  final (toSide, fromSide) = _sidesOf(bone, root, ahead, up, swing.hangs);
  return JointSwing(
    neutral: swing.hangs ? -up : up.clone(),
    ahead: ahead,
    forward: swing.flexion,
    back: swing.extension,
    toSide: toSide ? swing.lateral : swing.medial,
    fromSide: fromSide ? swing.lateral : swing.medial,
  );
}

/// cos(π/2) of the double nearest π/2, as every correctly rounded libm gives
/// it: the w of the half turns below, so they keep the bits
/// `Quaternion.axisAngle` gave them.
const double _cosHalfPi = 6.123233995736766e-17;

/// The turn that takes the y axis to [along].
///
/// What `Quaternion.fromTwoVectors` makes, snapping within 0.0005 of
/// vertical and all, without its `math.acos`, `math.sin` and `math.cos`:
/// the platform's answers, which differ in the last bit between the VM and
/// a browser. The half angle's sine and cosine come from the angle's cosine
/// c instead, as √((1 − c)/2) and √((1 + c)/2): a square root is rounded
/// alike everywhere.
Quaternion _alongY(Vector3 along) {
  final to = along.normalized();
  final up = Vector3(0.0, 1.0, 0.0);
  final dot = up.dot(to);
  if (dot > 1.0 - 1e-9) {
    return Quaternion.identity();
  }
  if (dot < -1.0 + 1e-9) {
    // Half a turn about x.
    return Quaternion(1.0, 0.0, 0.0, _cosHalfPi);
  }
  final c = up.dot(to.normalized());
  if ((1.0 + c).abs() < 0.0005) {
    // Half a turn about up × x, as fromTwoVectors picks for a y axis.
    return Quaternion(0.0, 0.0, -1.0, _cosHalfPi);
  }
  if ((1.0 - c).abs() < 0.0005) return Quaternion.identity();
  final axis = up.cross(to.normalized()).normalized();
  final halfSin = math.sqrt((1.0 - c) * 0.5) / axis.length;
  return Quaternion(
    axis.x * halfSin,
    axis.y * halfSin,
    axis.z * halfSin,
    math.sqrt((1.0 + c) * 0.5),
  );
}

/// [v] turned by [q], as the core turns a body by its orientation.
///
/// Not `Quaternion.rotated`, which in vector_math turns by the inverse —
/// the opposite of `asRotationMatrix`, which is what the core and
/// flutter3d_physics both mean by an orientation. A ragdoll placed with it
/// had every body turned one way and moved the other, and flew apart on
/// its first step.
Vector3 turnBy(Quaternion q, Vector3 v) =>
    q.asRotationMatrix().transform(v.clone());
