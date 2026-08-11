import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/services/prefs/auth_storage.dart';

import 'mocks/secure_storage_mock.dart';

/// Çıkış (clearTokens) ile uçuştaki token yenilemesinin (saveTokens) yarışı.
/// ApiClient._attemptTokenRefresh yazmadan önce "oturum hâlâ duruyor mu" diye
/// bakar, ama o kontrol ile yazı arasında bir await boşluğu var: çıkış tam
/// oraya denk gelirse kullanıcı çıkmış görünürken oturum ayakta kalıyordu.
void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsAuthStorage.clearTokens();
    PrefsAuthStorage.clearTokenCache();
  });

  test('a refresh landing after logout cannot resurrect the session', () async {
    await PrefsAuthStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );

    // Yenileme ağ turuna çıkıyor; epoch bu noktada alınır.
    final refreshEpoch = PrefsAuthStorage.tokenEpoch;

    // Kullanıcı çıkış yapıyor ve çıkış TAMAMLANIYOR.
    await PrefsAuthStorage.clearTokens();

    // Yenileme yanıtı ancak şimdi geliyor.
    await PrefsAuthStorage.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      expectedEpoch: refreshEpoch,
    );

    expect(
      await PrefsAuthStorage.getAccessToken(),
      isNull,
      reason: 'çıkıştan sonra bellekteki access token oturumu ayakta tutuyor',
    );
    expect(
      await PrefsAuthStorage.getRefreshToken(),
      isNull,
      reason: 'çıkıştan sonra kalan refresh token yeni access token üretir',
    );
  });

  test('logout interleaved with a refresh write still wins', () async {
    await PrefsAuthStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    final refreshEpoch = PrefsAuthStorage.tokenEpoch;

    // clearTokens epoch'u senkron artırıp ilk await'inde askıya alınır;
    // yenilemenin yazısı tam o boşlukta başlar.
    final clear = PrefsAuthStorage.clearTokens();
    final save = PrefsAuthStorage.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      expectedEpoch: refreshEpoch,
    );
    await Future.wait([clear, save]);

    expect(await PrefsAuthStorage.getAccessToken(), isNull);
    expect(await PrefsAuthStorage.getRefreshToken(), isNull);
  });

  test('logout started while a save is in flight still wins', () async {
    await PrefsAuthStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );

    final save = PrefsAuthStorage.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    final clear = PrefsAuthStorage.clearTokens();
    await Future.wait([save, clear]);

    expect(await PrefsAuthStorage.getAccessToken(), isNull);
    expect(await PrefsAuthStorage.getRefreshToken(), isNull);
  });

  test('an uncontested refresh still replaces both tokens', () async {
    await PrefsAuthStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    final refreshEpoch = PrefsAuthStorage.tokenEpoch;
    await PrefsAuthStorage.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      expectedEpoch: refreshEpoch,
    );

    expect(await PrefsAuthStorage.getAccessToken(), 'new-access');
    expect(await PrefsAuthStorage.getRefreshToken(), 'new-refresh');
  });

  test('login right after logout is not dropped', () async {
    await PrefsAuthStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    await PrefsAuthStorage.clearTokens();

    // Giriş akışı epoch geçirmez: yeni oturum koşulsuz yazılır.
    await PrefsAuthStorage.saveTokens(
      accessToken: 'fresh-access',
      refreshToken: 'fresh-refresh',
    );

    expect(await PrefsAuthStorage.getAccessToken(), 'fresh-access');
    expect(await PrefsAuthStorage.getRefreshToken(), 'fresh-refresh');
  });
}
