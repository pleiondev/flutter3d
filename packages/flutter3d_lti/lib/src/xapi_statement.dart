import 'xapi_uuid.dart';

/// Who did it — xAPI's `Agent`, identified the way an LTI launch already
/// identifies a student: an opaque platform-issued `sub`, scoped to the
/// platform that issued it. xAPI calls this an "account" identifier
/// (`homePage` + `name`) rather than `mbox`, because a platform's `sub` is
/// not, and is not required to look like, an email address.
final class XapiActor {
  const XapiActor({
    required this.name,
    required this.homePage,
    required this.accountName,
  });

  /// Built straight from a verified launch: `homePage: claims.raw['iss']`  (or
  /// the `LtiPlatformConfig.issuer` that verified it), `accountName:
  /// claims.subject` — this constructor does not read `LtiLaunchClaims`
  /// itself so this package's two clients (`AgsClient`, `XapiClient`) do not
  /// have to agree on which one runs first.
  factory XapiActor.fromLtiSubject({
    required String name,
    required String platformIssuer,
    required String subject,
  }) => XapiActor(name: name, homePage: platformIssuer, accountName: subject);

  final String name;
  final String homePage;
  final String accountName;

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
  const XapiVerb({required this.id, required this.display});

  static const answered = XapiVerb(
    id: 'http://adlnet.gov/expapi/verbs/answered',
    display: 'answered',
  );

  static const completed = XapiVerb(
    id: 'http://adlnet.gov/expapi/verbs/completed',
    display: 'completed',
  );

  final String id;

  /// English display text. xAPI's `display` is a language map
  /// (`{"en": "answered"}`); this package has one lesson language today
  /// (`doc/lesson-scenarios-plan.md` §8: "первый проход на одном языке"),
  /// so a full `Map<String, String>` would be a second thing to keep in
  /// sync with content that does not exist yet.
  final String display;

  Map<String, dynamic> toJson() => {
    'id': id,
    'display': {'en': display},
  };
}

/// What it was done to — xAPI's `Activity`. `id` is a URI identifying the
/// thing, not necessarily one that resolves; a lesson's `check` naturally
/// gets one built from the tool's own launch URL plus the step name.
final class XapiActivity {
  const XapiActivity({required this.id, required this.name});

  final String id;
  final String name;

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
  const XapiResult({this.success, this.response, this.scoreScaled});

  final bool? success;
  final String? response;

  /// xAPI's `score.scaled`, `-1.0`–`1.0`. `check` has no partial credit
  /// (`doc/edu-00-interactive-format.md` §10 names no such thing), so a
  /// caller reporting a pass/fail question passes `1.0`/`0.0`, not a
  /// separate raw/min/max the format does not have.
  final double? scoreScaled;

  Map<String, dynamic> toJson() => {
    if (success != null) 'success': success,
    if (response != null) 'response': response,
    if (scoreScaled != null) 'score': {'scaled': scoreScaled},
  };
}

/// One xAPI statement, ready to PUT to an LRS.
final class XapiStatement {
  XapiStatement({
    String? id,
    required this.actor,
    required this.verb,
    required this.object,
    this.result,
    DateTime? timestamp,
  }) : id = id ?? generateUuidV4(),
       timestamp = timestamp ?? DateTime.now().toUtc();

  final String id;
  final XapiActor actor;
  final XapiVerb verb;
  final XapiActivity object;
  final XapiResult? result;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'id': id,
    'actor': actor.toJson(),
    'verb': verb.toJson(),
    'object': object.toJson(),
    if (result != null) 'result': result!.toJson(),
    'timestamp': timestamp.toIso8601String(),
  };
}
