/// The claim URIs LTI 1.3 (IMS Core spec §5) and its Assignment and Grade
/// Services extension define on top of a plain OIDC `id_token`. Kept as
/// constants rather than typed once into `LtiLaunchClaims` and forgotten,
/// because `lti-04` reads more of the AGS claim than `LtiLaunchClaims`
/// exposes today (the `lineitem` URL) and will want these names again.
abstract final class LtiClaim {
  /// The claim naming the kind of launch, `LtiResourceLinkRequest` for the
  /// one this tool handles.
  static const messageType =
      'https://purl.imsglobal.org/spec/lti/claim/message_type';

  /// The claim naming the platform's deployment of this tool, which the
  /// validator checks against `LtiPlatformSettings.deploymentId`.
  static const deploymentId =
      'https://purl.imsglobal.org/spec/lti/claim/deployment_id';

  /// The claim naming the URL the platform means the launch to open.
  static const targetLinkUri =
      'https://purl.imsglobal.org/spec/lti/claim/target_link_uri';

  /// The claim listing the user's role URIs in the context.
  static const roles = 'https://purl.imsglobal.org/spec/lti/claim/roles';

  /// The claim describing the link launched, an object whose `id` names it.
  static const resourceLink =
      'https://purl.imsglobal.org/spec/lti/claim/resource_link';

  /// The claim describing the course, an object whose `id` names it.
  static const context = 'https://purl.imsglobal.org/spec/lti/claim/context';

  /// The AGS claim: the line item URL under `lineitem` and the granted
  /// scopes under `scope`.
  static const agsEndpoint =
      'https://purl.imsglobal.org/spec/lti-ags/claim/endpoint';
}

/// The two message types this tool understands. LTI 1.3 defines others
/// (`LtiDeepLinkingRequest` among them — out of scope, see `doc/
/// edu-03-lti-plan.md` §6); an unrecognised value round-trips as
/// [LtiMessageType.other] rather than failing verification, because deciding
/// what to do with an unsupported message type is a route's job, not the
/// validator's.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class LtiMessageType {
  const LtiMessageType._(this.name);

  /// `LtiResourceLinkRequest`: a student or a teacher opening the tool from
  /// a link in the course.
  static const LtiMessageType resourceLinkRequest = LtiMessageType._(
    'resourceLinkRequest',
  );

  /// Any other message type, or none: verified all the same, and left to
  /// the route to turn away.
  static const LtiMessageType other = LtiMessageType._('other');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<LtiMessageType> values = <LtiMessageType>[
    resourceLinkRequest,
    other,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static LtiMessageType? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  /// Reads the [LtiClaim.messageType] claim's value: [resourceLinkRequest]
  /// for `LtiResourceLinkRequest`, [other] for anything else, null
  /// included.
  static LtiMessageType fromClaim(Object? value) => switch (value) {
    'LtiResourceLinkRequest' => LtiMessageType.resourceLinkRequest,
    _ => LtiMessageType.other,
  };

  @override
  String toString() => 'LtiMessageType.$name';
}

/// What this tool needs out of a verified launch — a subset of the
/// `id_token`'s payload, not a copy of it. `raw` carries the rest for a
/// caller that needs a claim this type does not name yet.
final class LtiLaunchClaims {
  /// Claims as given; [LtiLaunchClaims.fromPayload] reads them from a
  /// verified token.
  const LtiLaunchClaims({
    required this.subject,
    required this.deploymentId,
    required this.messageType,
    required this.targetLinkUri,
    required this.roles,
    required this.resourceLinkId,
    required this.contextId,
    required this.agsLineItemUrl,
    required this.agsScopes,
    required this.raw,
  });

  /// Reads the claims out of a verified `id_token` [payload], never
  /// refusing: a missing text claim reads as empty, a missing list as
  /// empty, and a missing link, context or AGS claim as null. A claim of
  /// the wrong type throws the cast's `TypeError`.
  factory LtiLaunchClaims.fromPayload(Map<String, dynamic> payload) {
    final resourceLink = payload[LtiClaim.resourceLink];
    final context = payload[LtiClaim.context];
    final ags = payload[LtiClaim.agsEndpoint];
    return LtiLaunchClaims(
      subject: payload['sub'] as String? ?? '',
      deploymentId: payload[LtiClaim.deploymentId] as String? ?? '',
      messageType: LtiMessageType.fromClaim(payload[LtiClaim.messageType]),
      targetLinkUri: payload[LtiClaim.targetLinkUri] as String? ?? '',
      roles: switch (payload[LtiClaim.roles]) {
        final List<dynamic> list => list.cast<String>(),
        _ => const <String>[],
      },
      resourceLinkId: switch (resourceLink) {
        final Map<String, dynamic> map => map['id'] as String?,
        _ => null,
      },
      contextId: switch (context) {
        final Map<String, dynamic> map => map['id'] as String?,
        _ => null,
      },
      agsLineItemUrl: switch (ags) {
        final Map<String, dynamic> map => map['lineitem'] as String?,
        _ => null,
      },
      agsScopes: switch (ags) {
        final Map<String, dynamic> map when map['scope'] is List =>
          (map['scope'] as List).cast<String>(),
        _ => const <String>[],
      },
      raw: payload,
    );
  }

  /// The platform's opaque, stable identifier for the student — `LTI`'s
  /// `sub`, carried through to both AGS score submissions and xAPI actor
  /// identification (`lti-01`/`lti-02`).
  final String subject;

  /// The platform's deployment of this tool the launch came through;
  /// empty when the claim is missing.
  final String deploymentId;

  /// The kind of launch; [LtiMessageType.other] for one this tool does not
  /// handle.
  final LtiMessageType messageType;

  /// The URL the platform means the launch to open; empty when the claim
  /// is missing.
  final String targetLinkUri;

  /// The user's role URIs in the course, as the platform sent them; empty
  /// when it sent none.
  final List<String> roles;

  /// The platform's id for the link launched; null without a resource link
  /// claim.
  final String? resourceLinkId;

  /// The platform's id for the course; null without a context claim.
  final String? contextId;

  /// Where `lti-01`'s AGS client posts a score, when the platform granted
  /// this launch a line item at all — a launch is a valid LTI launch with no
  /// AGS claim (the platform did not enable grading for this placement).
  final String? agsLineItemUrl;

  /// The AGS scopes (`.../scope/score`, `.../scope/lineitem`, ...) the
  /// platform actually granted this deployment — `lti-01` checks its scope
  /// against this before attempting a client-credentials grant that would
  /// only fail at the platform.
  final List<String> agsScopes;

  /// The verified payload, unabridged — an escape hatch for a claim this
  /// type does not parse.
  final Map<String, dynamic> raw;
}
