/// Where statements go, and how this tool authenticates to send them.
///
/// This package does not pick an auth scheme for a Learning Record Store —
/// LRSs commonly take HTTP Basic, and some take a Bearer token, and which
/// one is a fact about the LRS a caller already knows. [authorizationHeader]
/// is the finished `Authorization` header value (`'Basic base64(...)'` or
/// `'Bearer ...'`), built by the caller.
final class XapiLrsSettings {
  const XapiLrsSettings({
    required this.statementsEndpoint,
    required this.authorizationHeader,
  });

  /// A copy with the given fields replaced.
  XapiLrsSettings copyWith({
    Uri? statementsEndpoint,
    String? authorizationHeader,
  }) => XapiLrsSettings(
    statementsEndpoint: statementsEndpoint ?? this.statementsEndpoint,
    authorizationHeader: authorizationHeader ?? this.authorizationHeader,
  );

  /// The LRS's `/statements` endpoint (xAPI spec §Data — Resources), e.g.
  /// `https://lrs.example.test/xapi/statements`.
  final Uri statementsEndpoint;

  final String authorizationHeader;
}
