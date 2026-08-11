import 'dart:async';
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
import '../screens/social_screen.dart';
import '../screens/couch_screen.dart';
import '../models/movie.dart';
import '../screens/movie_detail_sheet.dart';
import 'tmdb_service.dart';
import '../widgets/blocking_loading_dialog.dart';

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
  Future<void> Function()? _deleteTokenOverride;
  Future<String?> Function()? _getTokenOverride;
  Future<void> Function(String token)? _registerTokenOverride;
  Future<void> Function(String token)? _unregisterTokenOverride;
  Future<void> Function()? _authReadyHandler;
  String Function()? _localeSource;
  Future<void> _tokenOperationTail = Future.value();
  Future<void> _reminderOperationTail = Future.value();
  bool _tokenRegistrationEnabled = false;
  int _tokenRegistrationGeneration = 0;
  bool _ready = false;
  Future<void>? _initFlight;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  StreamSubscription<String>? _tokenRefreshes;
  Future<bool>? _tzInit;
  String? _lastRegisteredToken;

  /// Saat dilimi veritabanını bir kez kurar; zamanlanmış bildirimler için
  /// gereklidir. init()'ten bağımsız çağrılabilir (ör. açılıştaki watchlist
  /// yüklemesi init tamamlanmadan koşabilir).
  Future<bool> _ensureTimezone() {
    return _tzInit ??= () async {
      try {
        tzdata.initializeTimeZones();
        final Object rawTz = await FlutterTimezone.getLocalTimezone();
        final String localTz = rawTz is String
            ? rawTz
            : (rawTz as dynamic)?.identifier?.toString() ?? 'UTC';
        try {
          tz.setLocalLocation(tz.getLocation(localTz));
        } catch (_) {
          tz.setLocalLocation(tz.getLocation('UTC'));
        }
        return true;
      } catch (e) {
        final isTest =
            const bool.fromEnvironment('dart.library.io') &&
            Platform.environment.containsKey('FLUTTER_TEST');
        if (!isTest) {
          debugPrint('Timezone init failed: $e');
        }
        _tzInit = null; // sonraki çağrıda yeniden dene
        return false;
      }
    }();
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'social_channel',
    'Social Notifications',
    description: 'Friend requests and social activity',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _releaseChannel =
      AndroidNotificationChannel(
        'release_channel',
        'Release Reminders',
        description: 'Alerts when watchlist titles are released',
        importance: Importance.high,
      );

  AndroidNotificationChannel get _localizedSocialChannel {
    final tr = localeCode == 'tr';
    return AndroidNotificationChannel(
      _channel.id,
      tr ? 'Sosyal Bildirimler' : _channel.name,
      description: tr
          ? 'Arkadaşlık istekleri ve sosyal etkileşimler'
          : _channel.description,
      importance: Importance.high,
    );
  }

  AndroidNotificationChannel get _localizedReleaseChannel {
    final tr = localeCode == 'tr';
    return AndroidNotificationChannel(
      _releaseChannel.id,
      tr ? 'Çıkış Hatırlatıcıları' : _releaseChannel.name,
      description: tr
          ? 'İzleme listendeki yapımlar yayınlandığında haber verir'
          : _releaseChannel.description,
      importance: Importance.high,
    );
  }

  /// Uygulama açılışında bir kez çağrılır. Birden çok çağrı güvenlidir.
  Future<void> init(ApiService api) {
    _api = api;
    if (_ready) return Future.value();
    final activeFlight = _initFlight;
    if (activeFlight != null) return activeFlight;

    late final Future<void> flight;
    flight = _initialize().whenComplete(() {
      if (identical(_initFlight, flight)) {
        _initFlight = null;
      }
    });
    _initFlight = flight;
    return flight;
  }

  Future<void> _initialize() async {
    String? localLaunchPayload;
    try {
      // Yerel bildirim eklentisi
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
        onDidReceiveNotificationResponse: (resp) =>
            _routeFromPayload(resp.payload),
      );
      // Uygulama tamamen kapalıyken zamanlanmış/yerel bildirime dokunularak
      // açıldıysa callback tek başına çalışmaz; launch payloadunu ayrıca tüket.
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true) {
        localLaunchPayload = localLaunch?.notificationResponse?.payload;
      }

      // Android bildirim kanalları
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_localizedSocialChannel);
      await androidPlugin?.createNotificationChannel(_localizedReleaseChannel);

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
      _foregroundMessages = FirebaseMessaging.onMessage.listen(_showForeground);

      // Bildirime tıklanınca (uygulama arka plandayken)
      _openedMessages = FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _routeFromPayload(payloadFromData(m.data)),
      );

      // Soğuk başlatma: uygulama bir bildirime tıklanarak açıldıysa
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      final remoteLaunchPayload = initial == null
          ? null
          : payloadFromData(initial.data);

      // Token yenilenince sunucuya tekrar kaydet
      _tokenRefreshes = FirebaseMessaging.instance.onTokenRefresh.listen(
        _sendToken,
      );
      _ready = true;
      _routeInitialPayloadWhenReady(
        selectInitialPayload(
          remote: remoteLaunchPayload,
          local: localLaunchPayload,
        ),
      );

      if (kDebugMode) {
        try {
          final debugToken = await FirebaseMessaging.instance.getToken();
          debugPrint(
            'FCM token acquired (${debugToken?.length ?? 0} chars; value redacted).',
          );
        } catch (e) {
          debugPrint('FCM debug token lookup failed: $e');
        }
      }
    } catch (e, st) {
      _ready = false;
      await _cancelMessagingSubscriptions();
      // Firebase yapılandırılmamış olabilir; sessizce geç.
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Firebase messaging init failed: $e\n$st');
      }
    }
  }

  Future<void> _cancelMessagingSubscriptions() async {
    await _foregroundMessages?.cancel();
    await _openedMessages?.cancel();
    await _tokenRefreshes?.cancel();
    _foregroundMessages = null;
    _openedMessages = null;
    _tokenRefreshes = null;
  }

  /// Giriş/kayıt veya oturum geri yüklendikten sonra çağrılır:
  /// mevcut FCM token'ını sunucuya kaydeder.
  Future<void> registerToken() async {
    _tokenRegistrationEnabled = true;
    final generation = ++_tokenRegistrationGeneration;
    try {
      final token = await _getToken();
      if (kDebugMode) {
        final tokenPreview = token?.substring(0, token.length.clamp(0, 20));
        debugPrint(
          'FCM registerToken: ${token == null ? "NULL (APNs/Firebase yapılandırmasını kontrol edin)" : "$tokenPreview..."}',
        );
      }
      if (token != null &&
          _tokenRegistrationEnabled &&
          generation == _tokenRegistrationGeneration) {
        await _sendToken(token);
      }
    } catch (e, st) {
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Failed to register FCM token: $e\n$st');
      }
    }
  }

  /// Çıkış yapmadan ÖNCE çağrılır: token'ı sunucudan siler ki kullanıcı
  /// artık bu cihaza bildirim almasın.
  Future<void> unregisterToken() async {
    _tokenRegistrationEnabled = false;
    ++_tokenRegistrationGeneration;
    try {
      final token = await _getToken();
      if (token != null) {
        await _enqueueTokenOperation(() async {
          final override = _unregisterTokenOverride;
          if (override != null) {
            await override(token);
          } else {
            await _api?.unregisterDevice(token);
          }
          _lastRegisteredToken = null;
        });
      } else {
        _lastRegisteredToken = null;
      }
    } catch (e, st) {
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Failed to unregister FCM token: $e\n$st');
      }
    }
  }

  /// Invalidates this installation's token when authenticated unregister is
  /// no longer possible (for example after a refresh token is rejected).
  Future<void> invalidateLocalToken() async {
    _tokenRegistrationEnabled = false;
    ++_tokenRegistrationGeneration;
    try {
      final override = _deleteTokenOverride;
      if (override != null) {
        await override();
      } else {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (e, st) {
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Failed to invalidate local FCM token: $e\n$st');
      }
    }
  }

  @visibleForTesting
  void debugSetDeleteTokenHandler(Future<void> Function()? handler) {
    _deleteTokenOverride = handler;
  }

  @visibleForTesting
  void debugSetTokenHandlers({
    Future<String?> Function()? getToken,
    Future<void> Function(String token)? register,
    Future<void> Function(String token)? unregister,
  }) {
    _getTokenOverride = getToken;
    _registerTokenOverride = register;
    _unregisterTokenOverride = unregister;
    _tokenRegistrationEnabled = false;
    ++_tokenRegistrationGeneration;
  }

  @visibleForTesting
  Future<void> debugHandleTokenRefresh(String token) => _sendToken(token);

  /// Cold-start deep link'lerinin yerel oturum geri yüklenmeden çalışmasını
  /// engeller. Auth katmanı kendi hazır olma future'ını burada sağlar.
  void setAuthReadyHandler(Future<void> Function()? handler) {
    _authReadyHandler = handler;
  }

  /// Aktif arayüz dilini okuyan kaynak. `AuthNotifier` kurulurken verir,
  /// dispose olurken `null`'lar — bu servis singleton olduğu için ölü bir
  /// `ProviderContainer`'a bağlı kalmamalı ([setAuthReadyHandler] ile aynı
  /// kur/temizle döngüsü).
  void setLocaleSource(String Function()? source) {
    _localeSource = source;
  }

  /// Kaynak yoksa (uygulama henüz kurulmadıysa veya container düştüyse)
  /// varsayılan dile düşer; bildirim metni hiçbir koşulda patlamaz.
  String get localeCode => _localeSource?.call() ?? 'tr';

  Future<void> _sendToken(String token) async {
    if (!_tokenRegistrationEnabled) return;
    final generation = _tokenRegistrationGeneration;
    try {
      await _enqueueTokenOperation(() async {
        if (!_tokenRegistrationEnabled ||
            generation != _tokenRegistrationGeneration) {
          return;
        }
        final previous = _lastRegisteredToken;
        if (previous != null && previous != token) {
          try {
            final unreg = _unregisterTokenOverride;
            if (unreg != null) {
              await unreg(previous);
            } else {
              await _api?.unregisterDevice(previous);
            }
          } catch (e) {
            debugPrint('Failed to unregister previous FCM token: $e');
          }
        }
        final override = _registerTokenOverride;
        if (override != null) {
          await override(token);
          _lastRegisteredToken = token;
          return;
        }
        final platform = Platform.isIOS
            ? 'ios'
            : (Platform.isAndroid ? 'android' : 'web');
        await _api?.registerDevice(token, platform: platform);
        _lastRegisteredToken = token;
      });
    } catch (e, st) {
      debugPrint('Failed to send FCM token to API: $e\n$st');
    }
  }

  Future<String?> _getToken() {
    final override = _getTokenOverride;
    return override?.call() ?? FirebaseMessaging.instance.getToken();
  }

  Future<void> _enqueueTokenOperation(Future<void> Function() operation) {
    final previous = _tokenOperationTail;
    final next = () async {
      try {
        await previous;
      } catch (_) {
        // Bir önceki best-effort token işlemi sonraki temizliği engellemesin.
      }
      await operation();
    }();
    _tokenOperationTail = next;
    return next;
  }

  // Release reminders occupy 0x10000000 / 0x20000000. Foreground FCM IDs must
  // live in a disjoint high bit so a social ping cannot cancel a scheduled
  // release reminder that happens to share the same low bits of hashCode.
  static const int _foregroundIdBase = 0x40000000;
  static const int _releaseIdMovie = 0x20000000;
  static const int _releaseIdTv = 0x10000000;
  static const int _releaseIdMask = 0x30000000;

  static int _foregroundNotifId(Object n) =>
      _foregroundIdBase | (n.hashCode & 0x0FFFFFFF);

  static int _releaseNotifId(int movieId, bool isTV) =>
      (isTV ? _releaseIdTv : _releaseIdMovie) | (movieId & 0x0FFFFFFF);

  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    try {
      await _local.show(
        id: _foregroundNotifId(n),
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _localizedSocialChannel.id,
            _localizedSocialChannel.name,
            channelDescription: _localizedSocialChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payloadFromData(m.data),
      );
    } catch (e, st) {
      debugPrint('Failed to show foreground notification: $e\n$st');
    }
  }

  // ── Çıkış hatırlatıcıları ──────────────────────────────────────────────
  // Watchlist'teki henüz yayınlanmamış yapımlar için çıkış gününde yerel
  // bildirim planlar. Bildirim kimliği movie id + tür bitinden türetilir ki
  // ekleme/çıkarma ve cihazlar arası senkron sonrası tutarlı kalsın.

  /// Çıkış tarihi gelecekteyse o gün saat 10:00'a bildirim planlar.
  Future<void> scheduleReleaseReminder(Movie movie) {
    return _enqueueReminderOperation(() => _scheduleReleaseReminder(movie));
  }

  Future<void> _scheduleReleaseReminder(Movie movie) async {
    // Plugin init olmadan veya kullanıcı izni yokken planlama denemesi
    // sessizce başarısız olur; gereksiz zonedSchedule çağrısından kaçın.
    if (!_ready) return;
    if (!await _ensureTimezone()) return;
    try {
      final raw = movie.releaseDate;
      if (raw == null || raw.isEmpty) return;
      final date = DateTime.tryParse(raw);
      if (date == null) return;

      final when = tz.TZDateTime(tz.local, date.year, date.month, date.day, 10);
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

      final tr = localeCode == 'tr';
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
        id: _releaseNotifId(movie.id, movie.isTV),
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _localizedReleaseChannel.id,
            _localizedReleaseChannel.name,
            channelDescription: _localizedReleaseChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'release|${movie.id}|${movie.isTV}',
      );
    } catch (e, st) {
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Failed to schedule release reminder: $e\n$st');
      }
    }
  }

  Future<void> cancelReleaseReminder(int movieId, bool isTV) {
    return _enqueueReminderOperation(
      () => _cancelReleaseReminder(movieId, isTV),
    );
  }

  Future<void> _cancelReleaseReminder(int movieId, bool isTV) async {
    try {
      await _local.cancel(id: _releaseNotifId(movieId, isTV));
    } catch (e) {
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Failed to cancel release reminder: $e');
      }
    }
  }

  /// Planlanmış hatırlatıcıları watchlist ile hizalar: listeden çıkanları
  /// iptal eder, eksik olanları planlar. Cihazlar arası senkron sonrası
  /// (başka cihazda eklenen/çıkarılan yapımlar) tutarlılık için çağrılır.
  Future<void> syncReleaseReminders(List<Movie> watchlist) {
    final snapshot = List<Movie>.of(watchlist);
    return _enqueueReminderOperation(() => _syncReleaseReminders(snapshot));
  }

  Future<void> _syncReleaseReminders(List<Movie> watchlist) async {
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
          await _local.cancel(id: p.id);
        } else {
          scheduled.add(p.id);
        }
      }

      for (final entry in expected.entries) {
        if (!scheduled.contains(entry.key)) {
          // Geçmiş tarihli olanları scheduleReleaseReminder kendisi eler.
          await _scheduleReleaseReminder(entry.value);
        }
      }
    } catch (e, st) {
      final isTest =
          const bool.fromEnvironment('dart.library.io') &&
          Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest) {
        debugPrint('Failed to sync release reminders: $e\n$st');
      }
    }
  }

  Future<void> _enqueueReminderOperation(Future<void> Function() operation) {
    final previous = _reminderOperationTail;
    final next = () async {
      try {
        await previous;
      } catch (_) {
        // Bir hatırlatıcı hatası sonraki ekleme/çıkarma işlemini engellemesin.
      }
      await operation();
    }();
    _reminderOperationTail = next;
    return next;
  }

  @visibleForTesting
  Future<void> debugEnqueueReminderOperation(
    Future<void> Function() operation,
  ) => _enqueueReminderOperation(operation);

  /// FCM `data` haritasından yerel bildirim / deep-link payload'u üretir.
  @visibleForTesting
  static String? payloadFromData(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    if (type.isEmpty) return null;
    if (type == 'couch_invite' || type == 'couch_match') {
      final sessionId = data['session_id']?.toString() ?? '';
      if (sessionId.isEmpty) return null;
      return '$type|$sessionId';
    }
    if (type == 'friend_request' || type == 'friend_accept') {
      return type;
    }
    final movieId = data['movie_id']?.toString() ?? '';
    final isTv = data['is_tv']?.toString() ?? data['isTV']?.toString() ?? '';
    return '$type|$movieId|$isTv';
  }

  /// Maps friendship notifications to their relevant social tab.
  @visibleForTesting
  static int? socialTabForNotificationType(String type) {
    return switch (type) {
      'friend_request' => 1,
      'friend_accept' => 0,
      _ => null,
    };
  }

  @visibleForTesting
  static ({String language, String region}) notificationContentLocale(
    String languageCode,
  ) {
    return languageCode == 'tr'
        ? (language: 'tr-TR', region: 'TR')
        : (language: 'en-US', region: 'US');
  }

  @visibleForTesting
  static bool shouldRetryInitialRoute({
    required bool navigatorReady,
    required int attempt,
    int maxAttempts = 120,
  }) => !navigatorReady && attempt < maxAttempts;

  @visibleForTesting
  static String? selectInitialPayload({
    required String? remote,
    required String? local,
  }) => remote ?? local;

  Future<void> _routeInitialPayloadWhenReady(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    final authReady = _authReadyHandler;
    if (authReady != null) {
      try {
        await authReady().timeout(const Duration(seconds: 30));
      } on TimeoutException {
        // Yavaş unlock/restore: payload'ı atma — navigator hazır olunca yine dene.
        debugPrint(
          'Initial notification: auth restore timed out; routing when navigator ready.',
        );
      }
    }
    const retryDelay = Duration(milliseconds: 250);
    const maxAttempts = 120;
    for (var attempt = 0; attempt <= maxAttempts; attempt++) {
      final ready = navigatorKey.currentState != null;
      if (ready) {
        _routeFromPayload(payload);
        return;
      }
      if (!shouldRetryInitialRoute(
        navigatorReady: ready,
        attempt: attempt,
        maxAttempts: maxAttempts,
      )) {
        debugPrint(
          'Initial notification route expired before navigator ready.',
        );
        return;
      }
      await Future<void>.delayed(retryDelay);
    }
  }

  /// Bir payload'un hangi hedefe gideceğini çözer. Navigasyondan ayrı tutulur ki
  /// deep-link ayrıştırma kuralları context olmadan doğrulanabilsin.
  ///
  /// `socialTab` doluysa Social ekranı, `couch` true ise Couch ekranı, `movieId`
  /// doluysa film detayı açılır. Tanınmayan tip, eksik parça veya çözümlenemeyen
  /// film kimliği null döndürür (yönlendirme yapılmaz).
  @visibleForTesting
  static ({
    int? socialTab,
    bool couch,
    int? sessionId,
    int? movieId,
    bool isTV,
  })?
  routeForPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final parts = payload.split('|');
    if (parts.isEmpty) return null;
    final type = parts[0];

    final socialTab = socialTabForNotificationType(type);
    if (socialTab != null) {
      return (
        socialTab: socialTab,
        couch: false,
        sessionId: null,
        movieId: null,
        isTV: false,
      );
    }

    if (type == 'couch_invite' || type == 'couch_match') {
      final sessionId = parts.length > 1 ? int.tryParse(parts[1]) : null;
      return (
        socialTab: null,
        couch: true,
        sessionId: (sessionId != null && sessionId > 0) ? sessionId : null,
        movieId: null,
        isTV: false,
      );
    }

    if (type == 'release' ||
        type == 'movie_recommend' ||
        type == 'recommendation' ||
        type == 'movie_recommendation' ||
        type == 'friend_recommend') {
      if (parts.length < 3) return null;
      final movieId = int.tryParse(parts[1]) ?? 0;
      if (movieId == 0) return null;
      return (
        socialTab: null,
        couch: false,
        sessionId: null,
        movieId: movieId,
        isTV: parts[2] == '1' || parts[2] == 'true',
      );
    }

    return null;
  }

  /// Bildirim payload'una göre ilgili ekrana yönlendirir.
  void _routeFromPayload(String? payload) {
    final route = routeForPayload(payload);
    if (route == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final socialTab = route.socialTab;
    if (socialTab != null) {
      nav.push(
        MaterialPageRoute(builder: (_) => SocialScreen(initialTab: socialTab)),
      );
      return;
    }

    if (route.couch) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => CouchScreen(sessionId: route.sessionId),
        ),
      );
      return;
    }

    final movieId = route.movieId;
    if (movieId != null) {
      _openMovieDetailDirectly(movieId, route.isTV);
    }
  }

  Future<void> _openMovieDetailDirectly(int movieId, bool isTV) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final context = nav.overlay?.context;
    if (context == null) return;

    final locale = notificationContentLocale(localeCode);
    final service = TmdbService(
      language: locale.language,
      region: locale.region,
    );

    try {
      final details = await runWithBlockingLoadingDialog(
        context: context,
        color: Colors.red,
        task: () => service.getFullDetails(movieId, isTV: isTV),
      );
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
      debugPrint('Error opening movie from notification: $e');
    }
  }
}
