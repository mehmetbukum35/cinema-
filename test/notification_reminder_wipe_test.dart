import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/notification_service.dart';

/// Planlanmış bildirimleri bellekte tutan sahte platform katmanı.
class _FakeNotificationPlatform extends FlutterLocalNotificationsPlatform {
  _FakeNotificationPlatform(this.pending);

  final List<int> pending;
  final List<int> cancelled = [];

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return [
      for (final id in pending) PendingNotificationRequest(id, 'T', 'B', null),
    ];
  }

  @override
  Future<void> cancel({required int id}) async {
    cancelled.add(id);
    pending.remove(id);
  }
}

// notification_service.dart içindeki kimlik şemasının aynısı.
int _releaseId(int movieId, bool isTV) =>
    (isTV ? 0x10000000 : 0x20000000) | (movieId & 0x0FFFFFFF);
int _foregroundId(int n) => 0x40000000 | (n & 0x0FFFFFFF);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Eklenti kurucusu gerçek platform katmanını kaydeder; sahteyi ondan SONRA
    // koymalıyız. Hedef platform da masaüstüne sabitlenir ki `cancel` çağrısı
    // Android'e özel yola sapmayıp platform arayüzüne düşsün.
    NotificationService.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  _FakeNotificationPlatform install(List<int> pending) {
    final fake = _FakeNotificationPlatform(pending);
    FlutterLocalNotificationsPlatform.instance = fake;
    return fake;
  }

  test('yerel veri silinince planlı çıkış hatırlatıcıları iptal edilir', () async {
    final fake = install([_releaseId(603, false), _releaseId(1399, true)]);

    await NotificationService.instance.cancelAllReleaseReminders();

    expect(fake.cancelled, [_releaseId(603, false), _releaseId(1399, true)]);
    expect(fake.pending, isEmpty);
  });

  test('hatırlatıcı olmayan bildirimler iptal edilmez', () async {
    // Ön plandaki sosyal bildirimler ayrı bir yüksek bit'te yaşıyor; toplu
    // iptal onları düşürmemeli (cancelAll() bu yüzden kullanılmıyor).
    final social = _foregroundId(12345);
    final fake = install([social, _releaseId(603, false)]);

    await NotificationService.instance.cancelAllReleaseReminders();

    expect(fake.cancelled, [_releaseId(603, false)]);
    expect(fake.pending, [social]);
  });

  test('planlı hatırlatıcı yokken sessizce geçer', () async {
    final fake = install([]);

    await NotificationService.instance.cancelAllReleaseReminders();

    expect(fake.cancelled, isEmpty);
  });
}
