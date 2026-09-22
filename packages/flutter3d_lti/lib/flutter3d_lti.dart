/// LTI 1.3 launch and xAPI reporting, with no Flutter and no HTTP framework
/// of its own. See `doc/edu-03-lti-plan.md` for what this package is for
/// and what still lives elsewhere (`cloud/lti`'s routes, the AGS and xAPI
/// clients of `lti-01`/`lti-02`).
///
/// What is here today: [LtiPlatformConfig] names one platform registration;
/// [OidcLoginInitiation] builds the redirect for LTI's OIDC third-party
/// login initiation; [LtiLaunchValidator] verifies the `id_token` that comes
/// back and produces [LtiLaunchClaims], throwing an [LtiLaunchException]
/// subtype when it does not check out (`lti-00`). [AgsClient] posts a score
/// to a platform's gradebook via a client-credentials grant signed with
/// [LtiToolCredentials] (`lti-01`). [XapiClient] sends an [XapiStatement] to
/// a Learning Record Store (`lti-02`).
library;

export 'src/ags_client.dart';
export 'src/ags_exception.dart';
export 'src/ags_score.dart';
export 'src/jwk.dart'
    show
        rsaPrivateKeyFromJwk,
        rsaPrivateKeyToJwk,
        rsaPublicKeyFromJwk,
        rsaPublicKeyToJwk;
export 'src/lti_launch_claims.dart';
export 'src/lti_launch_exception.dart';
export 'src/lti_launch_validator.dart';
export 'src/lti_platform_config.dart';
export 'src/lti_tool_credentials.dart';
export 'src/oidc_login_initiation.dart';
export 'src/rsa_key_pair.dart';
export 'src/xapi_client.dart';
export 'src/xapi_exception.dart';
export 'src/xapi_lrs_config.dart';
export 'src/xapi_statement.dart';
export 'src/xapi_uuid.dart';
