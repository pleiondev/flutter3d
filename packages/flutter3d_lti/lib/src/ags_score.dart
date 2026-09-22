/// Where the student is in the activity — LTI-AGS's `activityProgress`
/// (IMS Assignment and Grade Services §A.2.1). Wire names are the spec's own
/// `PascalCase`, not Dart's `camelCase`.
enum AgsActivityProgress {
  initialized('Initialized'),
  started('Started'),
  inProgress('InProgress'),
  submitted('Submitted'),
  completed('Completed');

  const AgsActivityProgress(this.wireName);
  final String wireName;
}

/// Where grading is — LTI-AGS's `gradingProgress`. A score with
/// [AgsGradingProgress.pending] tells the platform's gradebook a number is
/// coming but not final, which `check`'s own three-attempt design (`doc/
/// edu-00-interactive-format.md` §10) never needs — every submission this
/// package sends is already the student's finished attempt.
enum AgsGradingProgress {
  fullyGraded('FullyGraded'),
  pending('Pending'),
  pendingManual('PendingManual'),
  failed('Failed'),
  notReady('NotReady');

  const AgsGradingProgress(this.wireName);
  final String wireName;
}

/// One score, ready to POST to a line item's `/scores` endpoint.
final class AgsScore {
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

  final num scoreGiven;
  final num scoreMaximum;
  final AgsActivityProgress activityProgress;
  final AgsGradingProgress gradingProgress;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'scoreGiven': scoreGiven,
    'scoreMaximum': scoreMaximum,
    'activityProgress': activityProgress.wireName,
    'gradingProgress': gradingProgress.wireName,
    'timestamp': timestamp.toIso8601String(),
  };
}
