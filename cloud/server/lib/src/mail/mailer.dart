/// Sending the two letters an account needs.
///
/// **Through Resend's HTTP API rather than SMTP from this machine.** A letter
/// from a VPS address with no sending history goes to spam often enough that a
/// verification link would regularly fail to arrive, and a registration that
/// depends on a letter nobody receives is a registration that does not work.
/// The domain is still ours: SPF, DKIM and DMARC are records in Cloudflare, and
/// Resend only signs with the key those records publish.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One letter, in both forms a mail client may choose to show.
class Letter {
  const Letter({
    required this.to,
    required this.subject,
    required this.html,
    required this.text,
  });

  final String to;
  final String subject;
  final String html;

  /// The plain version. Not optional: a letter with only HTML is scored as
  /// more likely to be spam, and some people read mail in a terminal.
  final String text;
}

abstract interface class Mailer {
  /// Sends [letter]. Throws [MailError] when the provider refuses it.
  Future<void> send(Letter letter);
}

class MailError implements Exception {
  const MailError(this.message);

  final String message;

  @override
  String toString() => 'MailError: $message';
}

class ResendMailer implements Mailer {
  ResendMailer({required this.apiKey, required this.from, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final String from;
  final http.Client _client;

  static final _endpoint = Uri.parse('https://api.resend.com/emails');

  @override
  Future<void> send(Letter letter) async {
    final response = await _client
        .post(
          _endpoint,
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'from': from,
            'to': [letter.to],
            'subject': letter.subject,
            'html': letter.html,
            'text': letter.text,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 300) {
      // The body names the reason — an unverified domain, a bad key — and it
      // carries no secret, so it goes into the error whole.
      throw MailError('Resend answered ${response.statusCode}: ${response.body}');
    }
  }
}

/// Prints letters instead of sending them, and keeps them for a test to read.
///
/// What development runs with: the verification link appears in the terminal
/// the server was started in, which is the one place a developer is already
/// looking.
class ConsoleMailer implements Mailer {
  ConsoleMailer({this.quiet = false});

  /// When true, keeps letters without printing — for tests.
  final bool quiet;

  final List<Letter> sent = [];

  @override
  Future<void> send(Letter letter) async {
    sent.add(letter);
    if (quiet) return;
    stdout
      ..writeln('──── letter to ${letter.to}: ${letter.subject}')
      ..writeln(letter.text)
      ..writeln('────');
  }
}
