import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import '../screens/social_screen.dart';
import '../models/movie.dart';
import '../screens/movie_detail_sheet.dart';
import 'tmdb_service.dart';

/// Arka planda (uygulama kapalı veya arka planda) gelen FCM mesajları için
/// top-level handler. Sistem bildirimi otomatik gösterilir; burada ağır iş yapma.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Gerekirse arka plan loglama/işleme buraya. Şimdilik no-op.
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

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'social_channel',
    'Sosyal Bildirimler',
    description: 'Arkadaşlık istekleri ve sosyal etkileşimler',
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

      // Android bildirim kanalı
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      // Bildirim izni (iOS + Android 13+)
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Foreground mesajları → yerel bildirim olarak göster
      FirebaseMessaging.onMessage.listen(_showForeground);

      // Bildirime tıklanınca (uygulama arka plandayken)
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _routeFromPayload("${m.data['type']}|${m.data['movie_id']}|${m.data['is_tv'] ?? m.data['isTV']}"),
      );

      // Soğuk başlatma: uygulama bir bildirime tıklanarak açıldıysa
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // Navigator'ın hazır olması için kısa bir gecikme
        Future.delayed(
          const Duration(milliseconds: 700),
          () => _routeFromPayload("${initial.data['type']}|${initial.data['movie_id']}|${initial.data['is_tv'] ?? initial.data['isTV']}"),
        );
      }

      // Token yenilenince sunucuya tekrar kaydet
      FirebaseMessaging.instance.onTokenRefresh.listen(_sendToken);

      // GEÇİCİ (test için): token'ı konsola yazdır. Yayın öncesi bu satırı sil.
      final debugToken = await FirebaseMessaging.instance.getToken();
      debugPrint('🔑 FCM TOKEN: $debugToken');
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
      final isTv = m.data['is_tv']?.toString() ?? m.data['isTV']?.toString() ?? '';
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
    } else if (type == 'movie_recommend' || type == 'recommendation' || type == 'movie_recommendation' || type == 'friend_recommend') {
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

    final service = TmdbService(
      language: 'tr-TR',
      region: 'TR',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.red),
      ),
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
