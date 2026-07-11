import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../firebase_options.dart';
import 'api_service.dart';
import 'prefs_service.dart';
import '../screens/social_screen.dart';
import '../models/movie.dart';
import '../screens/movie_detail_sheet.dart';
import 'tmdb_service.dart';

/// Arka planda (uygulama kapalı veya arka planda) gelen FCM mesajları için
/// top-level handler. Sistem bildirimi otomatik gösterilir; burada ağır iş yapma.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    debugPrint('FCM background message: ${message.messageId}');
  }
}

/// FCM push bildirimlerini yönetir: izin, token kayıt/yenileme, foreground'da
/// yerel bildirim gösterme ve bildirime tıklanınca ilgili ekrana yönlendirme.
///
/// Tüm metodlar best-effort'tur: Firebase yapılandırılmamışsa veya bir hata
/// olursa uygulamanın ana akışını bozmaz.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// MaterialApp'e verilecek global navigator anahtarı — bildirim tıklamasından
  /// context olmadan yönlendirme yapabilmek için.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  ApiService? _api;
  bool _ready = false;
  Future<bool>? _tzInit;

  /// Saat dilimi veritabanını bir kez kurar; zamanlanmış bildirimler için
  /// gereklidir. init()'ten bağımsız çağrılabilir (ör. açılıştaki watchlist
  /// yüklemesi init tamamlanmadan koşabilir).
  Future<bool> _ensureTimezone() {
    return _tzInit ??= () async {
      try {
        tzdata.initializeTimeZones();
        final localTz = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(localTz));
        return true;
      } catch (e) {
        debugPrint('Timezone init failed: $e');
        _tzInit = null; // sonraki çağrıda yeniden dene
        return false;
      }
    }();
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'social_channel',
    'Sosyal Bildirimler',
    description: 'Arkadaşlık istekleri ve sosyal etkileşimler',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _releaseChannel =
      AndroidNotificationChannel(
        'release_channel',
        'Çıkış Hatırlatıcıları',
        description: 'İzleme listendeki yapımlar yayınlandığında haber verir',
        importance: Importance.high,
      );

  /// Uygulama açılışında bir kez çağrılır. Birden çok çağrı güvenlidir.
  Future<void> init(ApiService api) async {
    _api = api;
    if (_ready) return;
    _ready = true;

    try {
      // Yerel bildirim eklentisi
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (resp) =>
            _routeFromPayload(resp.payload),
      );

      // Android bildirim kanalları
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_channel);
      await androidPlugin?.createNotificationChannel(_releaseChannel);

      // Zamanlanmış bildirimler için saat dilimi veritabanı
      await _ensureTimezone();

      // Bildirim izni (iOS + Android 13+)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (kDebugMode) {
        debugPrint(
          'FCM permission: ${settings.authorizationStatus.name} '
          '(iOS=${Platform.isIOS})',
        );
      }

      // iOS: uygulama ön plandayken sistem bildirimi göster
      if (Platform.isIOS) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Foreground mesajları → yerel bildirim olarak göster
      FirebaseMessaging.onMessage.listen(_showForeground);

      // Bildirime tıklanınca (uygulama arka plandayken)
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _routeFromPayload(
          "${m.data['type']}|${m.data['movie_id']}|${m.data['is_tv'] ?? m.data['isTV']}",
        ),
      );

      // Soğuk başlatma: uygulama bir bildirime tıklanarak açıldıysa
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // Navigator'ın hazır olması için kısa bir gecikme
        Future.delayed(
          const Duration(milliseconds: 700),
          () => _routeFromPayload(
            "${initial.data['type']}|${initial.data['movie_id']}|${initial.data['is_tv'] ?? initial.data['isTV']}",
          ),
        );
      }

      // Token yenilenince sunucuya tekrar kaydet
      FirebaseMessaging.instance.onTokenRefresh.listen(_sendToken);

      if (kDebugMode) {
        final debugToken = await FirebaseMessaging.instance.getToken();
        debugPrint('🔑 FCM TOKEN: $debugToken');
      }
    } catch (e, st) {
      // Firebase yapılandırılmamış olabilir; sessizce geç.
      debugPrint('Firebase messaging init failed: $e\n$st');
    }
  }

  /// Giriş/kayıt veya oturum geri yüklendikten sonra çağrılır:
  /// mevcut FCM token'ını sunucuya kaydeder.
  Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        debugPrint(
          'FCM registerToken: ${token == null ? "NULL (APNs/Firebase yapılandırmasını kontrol edin)" : "${token.substring(0, 20)}..."}',
        );
      }
      if (token != null) await _sendToken(token);
    } catch (e, st) {
      debugPrint('Failed to register FCM token: $e\n$st');
    }
  }

  /// Çıkış yapmadan ÖNCE çağrılır: token'ı sunucudan siler ki kullanıcı
  /// artık bu cihaza bildirim almasın.
  Future<void> unregisterToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _api?.unregisterDevice(token);
    } catch (e, st) {
      debugPrint('Failed to unregister FCM token: $e\n$st');
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      final platform = Platform.isIOS
          ? 'ios'
          : (Platform.isAndroid ? 'android' : 'web');
      await _api?.registerDevice(token, platform: platform);
    } catch (e, st) {
      debugPrint('Failed to send FCM token to API: $e\n$st');
    }
  }

  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    try {
      final type = m.data['type'] as String? ?? '';
      final movieId = m.data['movie_id']?.toString() ?? '';
      final isTv =
          m.data['is_tv']?.toString() ?? m.data['isTV']?.toString() ?? '';
      await _local.show(
        n.hashCode,
        n.title,
        n.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: "$type|$movieId|$isTv",
      );
    } catch (e, st) {
      debugPrint('Failed to show foreground notification: $e\n$st');
    }
  }

  // ── Çıkış hatırlatıcıları ──────────────────────────────────────────────
  // Watchlist'teki henüz yayınlanmamış yapımlar için çıkış gününde yerel
  // bildirim planlar. Bildirim kimliği movie id + tür bitinden türetilir ki
  // ekleme/çıkarma ve cihazlar arası senkron sonrası tutarlı kalsın.

  static const int _releaseIdMovie = 0x20000000;
  static const int _releaseIdTv = 0x10000000;
  static const int _releaseIdMask = 0x30000000;

  static int _releaseNotifId(int movieId, bool isTV) =>
      (isTV ? _releaseIdTv : _releaseIdMovie) | (movieId & 0x0FFFFFFF);

  /// Çıkış tarihi gelecekteyse o gün saat 10:00'a bildirim planlar.
  Future<void> scheduleReleaseReminder(Movie movie) async {
    if (!await _ensureTimezone()) return;
    try {
      final raw = movie.releaseDate;
      if (raw == null || raw.isEmpty) return;
      final date = DateTime.tryParse(raw);
      if (date == null) return;

      final when = tz.TZDateTime(tz.local, date.year, date.month, date.day, 10);
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

      final tr = PrefsService.activeLanguageCode == 'tr';
      final title = movie.isTV
          ? (tr ? '📺 Bugün yayında!' : '📺 Streaming today!')
          : (tr ? '🎬 Bugün vizyonda!' : '🎬 In theaters today!');
      final body = movie.isTV
          ? (tr
                ? '${movie.title} bugün yayınlanıyor. İzleme listende seni bekliyor!'
                : '${movie.title} premieres today. It\'s waiting on your watchlist!')
          : (tr
                ? '${movie.title} bugün vizyona giriyor. İzleme listende seni bekliyor!'
                : '${movie.title} is out today. It\'s waiting on your watchlist!');

      await _local.zonedSchedule(
        _releaseNotifId(movie.id, movie.isTV),
        title,
        body,
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _releaseChannel.id,
            _releaseChannel.name,
            channelDescription: _releaseChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'release|${movie.id}|${movie.isTV}',
      );
    } catch (e, st) {
      debugPrint('Failed to schedule release reminder: $e\n$st');
    }
  }

  Future<void> cancelReleaseReminder(int movieId, bool isTV) async {
    try {
      await _local.cancel(_releaseNotifId(movieId, isTV));
    } catch (e) {
      debugPrint('Failed to cancel release reminder: $e');
    }
  }

  /// Planlanmış hatırlatıcıları watchlist ile hizalar: listeden çıkanları
  /// iptal eder, eksik olanları planlar. Cihazlar arası senkron sonrası
  /// (başka cihazda eklenen/çıkarılan yapımlar) tutarlılık için çağrılır.
  Future<void> syncReleaseReminders(List<Movie> watchlist) async {
    if (!await _ensureTimezone()) return;
    try {
      final expected = <int, Movie>{
        for (final m in watchlist) _releaseNotifId(m.id, m.isTV): m,
      };

      final pending = await _local.pendingNotificationRequests();
      final scheduled = <int>{};
      for (final p in pending) {
        if ((p.id & _releaseIdMask) == 0) continue; // hatırlatıcı değil
        if (!expected.containsKey(p.id)) {
          await _local.cancel(p.id);
        } else {
          scheduled.add(p.id);
        }
      }

      for (final entry in expected.entries) {
        if (!scheduled.contains(entry.key)) {
          // Geçmiş tarihli olanları scheduleReleaseReminder kendisi eler.
          await scheduleReleaseReminder(entry.value);
        }
      }
    } catch (e, st) {
      debugPrint('Failed to sync release reminders: $e\n$st');
    }
  }

  /// Bildirim payload'una göre ilgili ekrana yönlendirir.
  void _routeFromPayload(String? payload) {
    if (payload == null) return;
    final parts = payload.split('|');
    if (parts.isEmpty) return;
    final type = parts[0];
    if (type == 'friend_request' || type == 'friend_accept') {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.push(
        MaterialPageRoute(builder: (_) => const SocialScreen(initialTab: 1)),
      );
    } else if (type == 'release' ||
        type == 'movie_recommend' ||
        type == 'recommendation' ||
        type == 'movie_recommendation' ||
        type == 'friend_recommend') {
      if (parts.length < 3) return;
      final movieId = int.tryParse(parts[1]) ?? 0;
      final isTV = parts[2] == '1' || parts[2] == 'true';
      if (movieId == 0) return;
      _openMovieDetailDirectly(movieId, isTV);
    }
  }

  Future<void> _openMovieDetailDirectly(int movieId, bool isTV) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final context = nav.overlay?.context;
    if (context == null) return;

    final service = TmdbService(language: 'tr-TR', region: 'TR');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.red)),
    );

    try {
      final details = await service.getFullDetails(movieId, isTV: isTV);
      nav.pop(); // Dismiss loading dialog
      if (details == null) return;

      if (!context.mounted) return;
      final movie = Movie.fromJson(details, isTV: isTV);
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => MovieDetailSheet(movie: movie, service: service),
      );
    } catch (e) {
      nav.pop(); // Dismiss loading dialog
      debugPrint('Error opening movie from notification: $e');
    }
  }
}
