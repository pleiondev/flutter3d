import 'package:flutter3d_lti/src/rsa_key_pair.dart';
import 'package:pointycastle/export.dart' as pc;

/// A real 2048-bit RSA key pair for a test — shared by `TestPlatform` (the
/// fake LMS `LtiLaunchValidator` is proven against) and any test that needs
/// a second, independent identity (this tool's own signing key for
/// `AgsClient`'s client-credentials assertion, `lti-01`).
///
/// A thin rename over [generateRsaKeyPair], which this file's own generator
/// used to be before `lti-04` needed the identical thing for a second, real
/// caller (`cloud/lti`'s own tool identity, not only a test's).
({pc.RSAPublicKey publicKey, pc.RSAPrivateKey privateKey})
generateTestRsaKeyPair() => generateRsaKeyPair();
