/// The claim URIs LTI 1.3 (IMS Core spec §5) and its Assignment and Grade
/// Services extension define on top of a plain OIDC `id_token`. Kept as
/// constants rather than typed once into `LtiLaunchClaims` and forgotten,
/// because `lti-04` reads more of the AGS claim than `LtiLaunchClaims`
/// exposes today (the `lineitem` URL) and will want these names again.
abstract final class LtiClaim {
  static const messageType =
      'https://purl.imsglobal.org/spec/lti/claim/message_type';
  static const deploymentId =
      'https://purl.imsglobal.org/spec/lti/claim/deployment_id';
  static const targetLinkUri =
      'https://purl.imsglobal.org/spec/lti/claim/target_link_uri';
  static const roles = 'https://purl.imsglobal.org/spec/lti/claim/roles';
  static const resourceLink =
      'https://purl.imsglobal.org/spec/lti/claim/resource_link';
  static const context = 'https://purl.imsglobal.org/spec/lti/claim/context';
  static const agsEndpoint =
      'https://purl.imsglobal.org/spec/lti-ags/claim/endpoint';
}

/// The two message types this tool understands. LTI 1.3 defines others
/// (`LtiDeepLinkingRequest` among them — out of scope, see `doc/
/// edu-03-lti-plan.md` §6); an unrecognised value round-trips as
/// [LtiMessageType.other] rather than failing verification, because deciding
/// what to do with an unsupported message type is a route's job, not the
/// validator's.
enum LtiMessageType {
  resourceLinkRequest,
  other;

  static LtiMessageType fromClaim(Object? value) => switch (value) {
    'LtiResourceLinkRequest' => LtiMessageType.resourceLinkRequest,
    _ => LtiMessageType.other,
  };
}

/// What this tool needs out of a verified launch — a subset of the
/// `id_token`'s payload, not a copy of it. `raw` carries the rest for a
/// caller that needs a claim this type does not name yet.
final class LtiLaunchClaims {
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

  final String deploymentId;
  final LtiMessageType messageType;
  final String targetLinkUri;
  final List<String> roles;
  final String? resourceLinkId;
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
