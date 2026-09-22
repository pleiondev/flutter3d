/// Why `XapiClient.send` could not deliver a statement to the LRS.
final class XapiException implements Exception {
  const XapiException(this.message);

  final String message;

  @override
  String toString() => 'XapiException: $message';
}
