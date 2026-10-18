/// Where the student is in the activity — LTI-AGS's `activityProgress`
/// (IMS Assignment and Grade Services §A.2.1). Wire names are the spec's own
/// `PascalCase`, not Dart's `camelCase`.
///
/// **Closed for good**: the five values of IMS Assignment and Grade Services
/// 2.0: the specification carries its own version, and another value is another
/// version of it. No member can be added without changing what the type means,
/// so it stays an enum and a `switch` over it may name every case.
enum AgsActivityProgress {
  /// Tells the gradebook the student has not begun: `Initialized`.
  initialized('Initialized'),

  /// Tells the gradebook the student has begun the activity: `Started`.
  started('Started'),

  /// Tells the gradebook the student is part way through and may still
  /// submit: `InProgress`.
  inProgress('InProgress'),

  /// Tells the gradebook the student has handed in work that may still be
  /// resubmitted: `Submitted`.
  submitted('Submitted'),

  /// Tells the gradebook the student has finished the activity, the
  /// default of [AgsScore]: `Completed`.
  completed('Completed');

  const AgsActivityProgress(this.wireName);

  /// The value as the spec spells it in a score's `activityProgress`.
  final String wireName;
}

/// Where grading is — LTI-AGS's `gradingProgress`. A score with
/// [AgsGradingProgress.pending] tells the platform's gradebook a number is
/// coming but not final, which `check`'s own three-attempt design (`doc/
/// edu-00-interactive-format.md` §10) never needs — every submission this
/// package sends is already the student's finished attempt.
///
/// **Closed for good**: the five values of IMS Assignment and Grade Services
/// 2.0: the specification carries its own version, and another value is another
/// version of it. No member can be added without changing what the type means,
/// so it stays an enum and a `switch` over it may name every case.
enum AgsGradingProgress {
  /// Has the gradebook take the score as final, the default of
  /// [AgsScore]: `FullyGraded`.
  fullyGraded('FullyGraded'),

  /// Has the gradebook show the score as one that will still change
  /// without a person: `Pending`.
  pending('Pending'),

  /// Has the gradebook wait for a teacher to grade by hand:
  /// `PendingManual`.
  pendingManual('PendingManual'),

  /// Tells the gradebook grading went wrong and the score is not to be
  /// trusted: `Failed`.
  failed('Failed'),

  /// Tells the gradebook there is nothing to grade yet: `NotReady`.
  notReady('NotReady');

  const AgsGradingProgress(this.wireName);

  /// The value as the spec spells it in a score's `gradingProgress`.
  final String wireName;
}

/// One score, ready to POST to a line item's `/scores` endpoint.
final class AgsScore {
  /// A finished, fully graded score for [userId] unless told otherwise,
  /// stamped [timestamp], or now in UTC when null.
  AgsScore({
    required this.userId,
    required this.scoreGiven,
    required this.scoreMaximum,
    this.activityProgress = AgsActivityProgress.completed,
    this.gradingProgress = AgsGradingProgress.fullyGraded,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// The platform's `sub` for the student — `LtiLaunchClaims.subject` from
  /// the launch this score answers.
  final String userId;

  /// The points the student earned, in the same points as [scoreMaximum].
  final num scoreGiven;

  /// The points a full score is worth; the gradebook shows [scoreGiven]
  /// against it.
  final num scoreMaximum;

  /// Where the student is in the activity.
  final AgsActivityProgress activityProgress;

  /// Whether the score is final, and if not, what it waits for.
  final AgsGradingProgress gradingProgress;

  /// When the score was made, in UTC unless given otherwise. The platform
  /// keeps the latest by this and drops an older one.
  final DateTime timestamp;

  /// The score as the `/scores` endpoint takes it, the progress values by
  /// their wire names and [timestamp] in ISO 8601.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'scoreGiven': scoreGiven,
    'scoreMaximum': scoreMaximum,
    'activityProgress': activityProgress.wireName,
    'gradingProgress': gradingProgress.wireName,
    'timestamp': timestamp.toIso8601String(),
  };
}
