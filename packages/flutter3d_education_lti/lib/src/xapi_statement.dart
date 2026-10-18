import 'xapi_uuid.dart';

/// Who did it — xAPI's `Agent`, identified the way an LTI launch already
/// identifies a student: an opaque platform-issued `sub`, scoped to the
/// platform that issued it. xAPI calls this an "account" identifier
/// (`homePage` + `name`) rather than `mbox`, because a platform's `sub` is
/// not, and is not required to look like, an email address.
final class XapiActor {
  /// The agent [name], known by [accountName] on the platform at
  /// [homePage].
  const XapiActor({
    required this.name,
    required this.homePage,
    required this.accountName,
  });

  /// Built straight from a verified launch: `homePage: claims.raw['iss']`  (or
  /// the `LtiPlatformSettings.issuer` that verified it), `accountName:
  /// claims.subject` — this constructor does not read `LtiLaunchClaims`
  /// itself so this package's two clients (`AgsClient`, `XapiClient`) do not
  /// have to agree on which one runs first.
  factory XapiActor.fromLtiSubject({
    required String name,
    required String platformIssuer,
    required String subject,
  }) => XapiActor(name: name, homePage: platformIssuer, accountName: subject);

  /// The student's display name, which a report shows and nothing matches
  /// on.
  final String name;

  /// The account's `homePage`: the issuer of the platform that knows the
  /// student, which scopes [accountName].
  final String homePage;

  /// The account's `name`: the platform's opaque `sub` for the student,
  /// what records are matched on.
  final String accountName;

  /// The actor as an xAPI `Agent` with an `account`.
  Map<String, dynamic> toJson() => {
    'objectType': 'Agent',
    'name': name,
    'account': {'homePage': homePage, 'name': accountName},
  };
}

/// What was done — xAPI's `Verb`. The handful this package's callers need;
/// nothing stops a caller building its own `XapiVerb` for one this list does
/// not name.
final class XapiVerb {
  /// The verb [id], shown as [display].
  const XapiVerb({required this.id, required this.display});

  /// ADL's `answered`: the student gave an answer to a question, right or
  /// wrong.
  static const answered = XapiVerb(
    id: 'http://adlnet.gov/expapi/verbs/answered',
    display: 'answered',
  );

  /// ADL's `completed`: the student finished the activity.
  static const completed = XapiVerb(
    id: 'http://adlnet.gov/expapi/verbs/completed',
    display: 'completed',
  );

  /// The verb's IRI, what an LRS matches verbs on.
  final String id;

  /// English display text. xAPI's `display` is a language map
  /// (`{"en": "answered"}`); this package has one lesson language today
  /// (`doc/lesson-scenarios-plan.md` §8: "первый проход на одном языке"),
  /// so a full `Map<String, String>` would be a second thing to keep in
  /// sync with content that does not exist yet.
  final String display;

  /// The verb as xAPI writes it, [display] under `en`.
  Map<String, dynamic> toJson() => {
    'id': id,
    'display': {'en': display},
  };
}

/// What it was done to — xAPI's `Activity`. `id` is a URI identifying the
/// thing, not necessarily one that resolves; a lesson's `check` naturally
/// gets one built from the tool's own launch URL plus the step name.
final class XapiActivity {
  /// The activity [id], named [name].
  const XapiActivity({required this.id, required this.name});

  /// The activity's IRI, what an LRS matches activities on.
  final String id;

  /// The English name a report shows for it.
  final String name;

  /// The activity as xAPI writes it, [name] under `definition.name.en`.
  Map<String, dynamic> toJson() => {
    'id': id,
    'objectType': 'Activity',
    'definition': {
      'name': {'en': name},
    },
  };
}

/// The outcome — xAPI's `Result`. Every field is optional in the spec;
/// `check`'s own shape (`doc/edu-00-interactive-format.md` §10: a question,
/// accepted answers, a number of attempts) maps onto `success`/`response`
/// directly and `score` only when the caller has one to give.
final class XapiResult {
  /// A result with whichever of the three the caller has; a null one is
  /// left out.
  const XapiResult({this.success, this.response, this.scoreScaled});

  /// Whether the answer was accepted; null when the outcome says nothing
  /// of it.
  final bool? success;

  /// What the student answered, as they wrote it; null when not given.
  final String? response;

  /// xAPI's `score.scaled`, `-1.0`–`1.0`. `check` has no partial credit
  /// (`doc/edu-00-interactive-format.md` §10 names no such thing), so a
  /// caller reporting a pass/fail question passes `1.0`/`0.0`, not a
  /// separate raw/min/max the format does not have. A unitless ratio of the
  /// full score.
  final double? scoreScaled;

  /// The result as xAPI writes it, without the fields that are null.
  Map<String, dynamic> toJson() => {
    if (success != null) 'success': success,
    if (response != null) 'response': response,
    if (scoreScaled != null) 'score': {'scaled': scoreScaled},
  };
}

/// One xAPI statement, ready to PUT to an LRS.
final class XapiStatement {
  /// [actor] [verb] [object], with [result] when there is one. A null `id`
  /// is a fresh random UUID and a null `timestamp` now, in UTC.
  XapiStatement({
    String? id,
    required this.actor,
    required this.verb,
    required this.object,
    this.result,
    DateTime? timestamp,
  }) : id = id ?? generateUuidV4(),
       timestamp = timestamp ?? DateTime.now().toUtc();

  /// The statement's UUID, which `XapiClient.send` PUTs it under, so a
  /// resend of the same statement lands on the same record.
  final String id;

  /// Who did it.
  final XapiActor actor;

  /// What was done.
  final XapiVerb verb;

  /// What it was done to.
  final XapiActivity object;

  /// How it went; null for a statement with no outcome, which then
  /// carries no `result`.
  final XapiResult? result;

  /// When it happened, in UTC unless given otherwise.
  final DateTime timestamp;

  /// The statement as an LRS takes it, [timestamp] in ISO 8601.
  Map<String, dynamic> toJson() => {
    'id': id,
    'actor': actor.toJson(),
    'verb': verb.toJson(),
    'object': object.toJson(),
    if (result != null) 'result': result!.toJson(),
    'timestamp': timestamp.toIso8601String(),
  };
}
