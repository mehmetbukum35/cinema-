import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks/secure_storage_mock.dart';

/// Kaydedilen son isteği yakalayan yardımcı; her testin gövde/başlık
/// doğrulaması için ayrı ayrı MockClient kurmasına gerek kalmıyor.
class _Recorder {
  http.Request? last;
  final List<String> paths = [];
}

void main() {
  setupSecureStorageMock();

  late _Recorder recorder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsService.activeLanguageCode = 'tr';
    recorder = _Recorder();
  });

  /// [status] ve [body] ile yanıt veren, isteği [recorder]'a yazan istemci.
  ApiService apiWith(int status, Object? body) {
    final client = MockClient((request) async {
      recorder.last = request;
      recorder.paths.add(request.url.path);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return ApiService(client: client);
  }

  Map<String, dynamic> sentBody() =>
      jsonDecode(recorder.last!.body) as Map<String, dynamic>;

  group('AuthApi success paths', () {
    test('register posts credentials and returns the payload', () async {
      final api = apiWith(201, {
        'user': {'id': 7},
        'verification_required': true,
      });

      final res = await api.register(
        email: 'a@b.com',
        password: 'secret',
        displayName: 'Ayşe',
      );

      expect(recorder.last!.url.path, '/api/auth/register');
      expect(recorder.last!.method, 'POST');
      expect(sentBody(), {
        'email': 'a@b.com',
        'password': 'secret',
        'display_name': 'Ayşe',
      });
      expect(res['verification_required'], isTrue);
    });

    test('register accepts 200 as well as 201', () async {
      final api = apiWith(200, {'ok': true});
      await expectLater(
        api.register(email: 'a@b.com', password: 'x'),
        completion(containsPair('ok', true)),
      );
    });

    test('login posts email and password', () async {
      final api = apiWith(200, {
        'tokens': {'access_token': 'a', 'refresh_token': 'r'},
      });

      await api.login(email: 'a@b.com', password: 'secret');

      expect(recorder.last!.url.path, '/api/auth/login');
      expect(sentBody(), {'email': 'a@b.com', 'password': 'secret'});
    });

    test('verifyEmail posts the code', () async {
      final api = apiWith(200, {'verified': true});

      await api.verifyEmail('a@b.com', '123456');

      expect(recorder.last!.url.path, '/api/auth/verify-email');
      expect(sentBody(), {'email': 'a@b.com', 'code': '123456'});
    });

    test('loginWithGoogle posts the id token', () async {
      final api = apiWith(200, {'tokens': <String, dynamic>{}});

      await api.loginWithGoogle('google-id-token');

      expect(recorder.last!.url.path, '/api/auth/google');
      expect(sentBody(), {'id_token': 'google-id-token'});
    });

    test(
      'loginWithApple sends display_name only when it is non-empty',
      () async {
        final api = apiWith(200, {'tokens': <String, dynamic>{}});

        await api.loginWithApple('apple-token', displayName: 'Mehmet');
        expect(sentBody(), {
          'identity_token': 'apple-token',
          'display_name': 'Mehmet',
        });

        await api.loginWithApple('apple-token', displayName: '');
        expect(sentBody(), {'identity_token': 'apple-token'});

        await api.loginWithApple('apple-token');
        expect(sentBody(), {'identity_token': 'apple-token'});
      },
    );

    test('getMe returns the decoded profile', () async {
      await PrefsService.saveTokens(accessToken: 'a', refreshToken: 'r');
      final api = apiWith(200, {
        'user': {'username': 'mehmet'},
      });

      final res = await api.getMe();

      expect(recorder.last!.url.path, '/api/me');
      expect(recorder.last!.method, 'GET');
      expect((res['user'] as Map)['username'], 'mehmet');
    });
  });

  group('AuthApi error mapping', () {
    test(
      'surfaces the server error message and machine-readable code',
      () async {
        final api = apiWith(403, {
          'error': 'E-posta doğrulanmamış.',
          'code': 'email_unverified',
        });

        await expectLater(
          api.login(email: 'a@b.com', password: 'x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.code, 'code', 'email_unverified')
                .having((e) => e.message, 'message', 'E-posta doğrulanmamış.'),
          ),
        );
      },
    );

    test(
      'falls back to a default message when the server sends none',
      () async {
        final api = apiWith(500, <String, dynamic>{});

        await expectLater(
          api.register(email: 'a@b.com', password: 'x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', 'Kayıt başarısız.')
                .having((e) => e.code, 'code', isNull),
          ),
        );
      },
    );

    test('a non-JSON error body still yields ApiException', () async {
      final api = apiWith(502, '<html>Bad Gateway</html>');

      await expectLater(
        api.verifyEmail('a@b.com', '000000'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502),
        ),
      );
    });

    test('each void endpoint throws on a non-200', () async {
      final cases = <String, Future<void> Function(ApiService)>{
        '/api/auth/resend-verification': (a) => a.resendVerification('a@b.com'),
        '/api/auth/forgot-password': (a) => a.forgotPassword('a@b.com'),
        '/api/auth/verify-reset-code': (a) =>
            a.verifyResetCode('a@b.com', '1234'),
        '/api/auth/reset-password': (a) =>
            a.resetPassword('a@b.com', '1234', 'newpass'),
        '/api/auth/google/link': (a) => a.unlinkGoogle(password: 'p'),
        '/api/auth/apple/link': (a) => a.unlinkApple(password: 'p'),
      };

      for (final entry in cases.entries) {
        await PrefsService.saveTokens(accessToken: 'a', refreshToken: 'r');
        final api = apiWith(400, {'error': 'nope', 'code': 'bad_request'});

        await expectLater(
          entry.value(api),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'bad_request'),
          ),
          reason: entry.key,
        );
        expect(recorder.last!.url.path, entry.key);
      }
    });
  });

  group('AuthApi local session handling', () {
    Future<void> seedSession() async {
      await PrefsService.saveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      await PrefsService.saveUserData({'id': 1, 'email': 'a@b.com'});
    }

    test('logout revokes the refresh token and clears local data', () async {
      await seedSession();
      final api = apiWith(200, {'ok': true});

      await api.logout();

      expect(recorder.last!.url.path, '/api/auth/logout');
      expect(sentBody(), {'refresh_token': 'refresh'});
      expect(await PrefsService.getAccessToken(), isNull);
      expect(await PrefsService.getRefreshToken(), isNull);
      expect(await PrefsService.getUserData(), isNull);
    });

    test('logout still clears local data when the server call fails', () async {
      await seedSession();
      final client = MockClient((_) async => throw const SocketExceptionStub());
      final api = ApiService(client: client);

      await api.logout();

      expect(await PrefsService.getAccessToken(), isNull);
      expect(await PrefsService.getRefreshToken(), isNull);
      expect(await PrefsService.getUserData(), isNull);
    });

    test(
      'logout skips the server call when there is no refresh token',
      () async {
        final api = apiWith(200, {'ok': true});

        await api.logout();

        expect(recorder.paths, isEmpty);
      },
    );

    test('revokeRefreshToken swallows transport failures', () async {
      final client = MockClient((_) async => throw const SocketExceptionStub());
      final api = ApiService(client: client);

      await expectLater(api.revokeRefreshToken('some-token'), completes);
    });

    test('deleteAccount clears the local session', () async {
      await seedSession();
      final api = apiWith(200, {'deleted': true});

      await api.deleteAccount();

      expect(recorder.last!.method, 'DELETE');
      expect(recorder.last!.url.path, '/api/me');
      expect(await PrefsService.getRefreshToken(), isNull);
      expect(await PrefsService.getUserData(), isNull);
    });

    test('deleteAccount keeps the session when the server refuses', () async {
      await seedSession();
      final api = apiWith(403, {'error': 'no', 'code': 'forbidden'});

      await expectLater(api.deleteAccount(), throwsA(isA<ApiException>()));

      expect(await PrefsService.getRefreshToken(), 'refresh');
    });

    test('changePassword forces re-login by clearing the session', () async {
      await seedSession();
      final api = apiWith(200, {'ok': true});

      await api.changePassword(oldPassword: 'old', newPassword: 'new');

      expect(sentBody(), {'old_password': 'old', 'new_password': 'new'});
      expect(await PrefsService.getRefreshToken(), isNull);
    });

    test('a failed changePassword leaves the session intact', () async {
      await seedSession();
      final api = apiWith(400, {'error': 'wrong', 'code': 'bad_password'});

      await expectLater(
        api.changePassword(oldPassword: 'old', newPassword: 'new'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'bad_password'),
        ),
      );

      expect(await PrefsService.getRefreshToken(), 'refresh');
    });
  });
}

/// MockClient içinden ağ hatası taklit etmek için; dart:io'ya bağlanmadan
/// transport katmanının hatayı yutup yutmadığını sınar.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: connection failed';
}
