/// A real WebRTC data channel behind `flutter3d_net`'s `NetTransport` —
/// `net-02`'s primary transport, with the relay carrying only the SDP/ICE
/// handshake rather than every game frame.
///
/// Its own package rather than a file in `flutter3d_net`, because
/// `flutter_webrtc` is a real plugin: native code per platform, and a
/// dependency `flutter3d_net`'s own claim — flat Dart, testable under
/// plain `dart test` — is built specifically not to carry.
library;

export 'src/webrtc_transport.dart';
