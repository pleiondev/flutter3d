import 'package:flutter3d_models/src/auth/accounts.dart';
import 'package:flutter3d_models/src/http/cookies.dart';
import 'package:flutter3d_models/src/http/request.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _post({Map<String, String> headers = const {}}) =>
    Request('POST', Uri.parse('https://models.pleion.dev/login'), headers: headers);

void main() {
  const production = CookiePolicy(secure: true, origin: 'https://models.pleion.dev');

  group('CookiePolicy', () {
    test('uses the __Host- prefix only where the browser will keep it', () {
      expect(production.sessionName, '__Host-session');
      expect(CookiePolicy.forBaseUrl('http://localhost:8793').sessionName, 'session');
    });

    test('a session cookie is HttpOnly, Lax, rooted and Secure in production', () {
      final cookie = production.session('abc', const Duration(days: 30));
      expect(cookie, startsWith('__Host-session=abc; '));
      expect(cookie, contains('Path=/'));
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Lax'));
      expect(cookie, contains('Max-Age=2592000'));
      expect(cookie, contains('Secure'));
      expect(cookie, isNot(contains('Domain')));
    });

    test('clearing a session expires it now', () {
      expect(production.clearSession(), contains('Max-Age=0'));
    });
  });

  group('formIsOurs', () {
    test('accepts a token that matches the cookie', () {
      final request = _post(headers: {
        'cookie': 'other=1; __Host-csrf=token123',
        'origin': 'https://models.pleion.dev',
      });
      expect(formIsOurs(request, {'csrf': 'token123'}, production), isTrue);
    });

    test('refuses a missing, empty or different token', () {
      final request = _post(headers: {'cookie': '__Host-csrf=token123'});
      expect(formIsOurs(request, {}, production), isFalse);
      expect(formIsOurs(request, {'csrf': ''}, production), isFalse);
      expect(formIsOurs(request, {'csrf': 'token124'}, production), isFalse);
      expect(formIsOurs(_post(), {'csrf': ''}, production), isFalse);
    });

    test('refuses a matching token sent from another origin', () {
      final request = _post(headers: {
        'cookie': '__Host-csrf=token123',
        'origin': 'https://evil.example',
      });
      expect(formIsOurs(request, {'csrf': 'token123'}, production), isFalse);
    });

    test('refuses what the browser marks as cross-site', () {
      final request = _post(headers: {
        'cookie': '__Host-csrf=token123',
        'sec-fetch-site': 'cross-site',
      });
      expect(formIsOurs(request, {'csrf': 'token123'}, production), isFalse);
    });
  });

  group('cookiesOf', () {
    test('reads name=value pairs and ignores the malformed', () {
      final request = _post(headers: {'cookie': 'a=1; b = two ;junk; =x; c=3=3'});
      expect(cookiesOf(request), {'a': '1', 'b': 'two', 'c': '3=3'});
    });
  });

  group('safeNext', () {
    test('keeps a path on this host', () {
      expect(safeNext('/m/12-chair'), '/m/12-chair');
    });

    test('refuses anything a browser would read as another host', () {
      expect(safeNext('//evil.example'), '/me');
      expect(safeNext('/\\evil.example'), '/me');
      expect(safeNext('https://evil.example'), '/me');
      expect(safeNext(null), '/me');
    });
  });

  group('clientIp', () {
    test('takes the address nginx forwarded', () {
      expect(clientIp(_post(headers: {'x-real-ip': '203.0.113.7'})), '203.0.113.7');
      expect(clientIp(_post(headers: {'cf-connecting-ip': '198.51.100.1, 10.0.0.1'})), '198.51.100.1');
    });
  });

  group('isPlausibleEmail', () {
    test('catches typos without pretending to validate', () {
      expect(isPlausibleEmail('ann@example.com'), isTrue);
      expect(isPlausibleEmail('ann+models@sub.example.co'), isTrue);
      expect(isPlausibleEmail('ann@example'), isFalse);
      expect(isPlausibleEmail('ann example.com'), isFalse);
      expect(isPlausibleEmail('@example.com'), isFalse);
      expect(isPlausibleEmail('${'a' * 250}@example.com'), isFalse);
    });
  });
}
