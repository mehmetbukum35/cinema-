import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/db_helper.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pulsing_placeholder.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/entrance.dart';
import '../widgets/tonight_pick_card.dart';
import 'browse/browse_skeleton.dart';
import 'movie_detail_sheet.dart';
import 'results_screen.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';
import 'onboarding_screen.dart';

class _Mood {
  final IconData icon;
  final String label;
  final String? genreStr;
  final double? minRating;
  final int? maxRuntime;
  final String? decade;
  final bool includeTv;

  const _Mood({
    required this.icon,
    required this.label,
    this.genreStr,
    this.minRating,
    this.maxRuntime,
    this.decade,
    this.includeTv = true,
  });
}

// NOT: TMDB with_genres'te virgül VE, pipe VEYA anlamına gelir. Mood'lar
// niyet olarak VEYA'dır ("gerilim lazım" = gerilim VEYA korku); virgüllü hali
// kesişim sorguladığı için (üstüne vote_count/minRating filtreleri binince)
// çoğu zaman boş sayfa döndürüyordu.
const _moods = [
  _Mood(
    icon: Icons.sentiment_very_satisfied_rounded,
    label: 'mood_funny',
    genreStr: '35|10402',
    includeTv: false,
  ),
  _Mood(
    icon: Icons.psychology_rounded,
    label: 'mood_thrill',
    genreStr: '53|27|9648',
    minRating: 7.0,
    includeTv: false,
  ),
  _Mood(
    icon: Icons.sentiment_very_dissatisfied_rounded,
    label: 'mood_cry',
    genreStr: '18|10749',
    minRating: 7.5,
  ),
  _Mood(
    icon: Icons.bolt_rounded,
    label: 'mood_action',
    genreStr: '28|12',
    includeTv: false,
  ),
  _Mood(
    icon: Icons.spa_rounded,
    label: 'mood_light',
    genreStr: '35|16|10751',
    maxRuntime: 100,
    includeTv: false,
  ),
  _Mood(
    icon: Icons.lightbulb_outline_rounded,
    label: 'mood_thought',
    genreStr: '18|9648|36',
    minRating: 7.5,
  ),
  _Mood(
    icon: Icons.favorite_rounded,
    label: 'mood_romance',
    genreStr: '10749',
    includeTv: false,
  ),
  _Mood(
    icon: Icons.movie_filter_rounded,
    label: 'mood_classic',
    decade: '1990',
    minRating: 7.0,
    includeTv: false,
  ),
  _Mood(
    icon: Icons.nights_stay_rounded,
    label: 'mood_scary',
    genreStr: '27',
    minRating: 6.5,
    includeTv: false,
  ),
  _Mood(
    icon: Icons.public_rounded,
    label: 'mood_doc',
    genreStr: '99',
    minRating: 7.0,
  ),
  _Mood(
    icon: Icons.auto_awesome_rounded,
    label: 'mood_fantasy',
    genreStr: '14|878',
  ),
  _Mood(icon: Icons.gavel_rounded, label: 'mood_crime', genreStr: '80|53'),
];

class BrowseScreen extends ConsumerStatefulWidget {
  /// Başlıktaki avatara dokununca profil sekmesine geçmek için (MainShell verir).
  final VoidCallback? onOpenProfile;
  const BrowseScreen({super.key, this.onOpenProfile});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  TmdbService get _service => ref.read(tmdbServiceProvider);
  final _rng = Random();
  final ScrollController _scrollController = ScrollController();

  Movie? _tonight;

  /// Vitrin alternatif havuzu: sıralamanın tepe dilimi (7 gün vitrin soğuması
  /// uygulanmış). "Başka öner" bu havuzda döner; böylece kullanıcı beğenmezse
  /// tam sayfa yenilemeye gerek kalmadan K adet alternatif sunulur.
  List<Movie> _tonightPool = [];
  int _tonightCursor = 0;

  /// Pull-to-refresh sayacı: gün içinde her yenilemede tohumlu rastgeleliğe
  /// farklı bir nüans katar (aynı gün + aynı veriyle bile farklı seçki).
  int _reloadNonce = 0;
  List<Movie> _personal = [];
  List<Movie> _trending = [];
  List<Movie> _movies = [];
  List<Movie> _shows = [];
  List<Movie> _upcoming = [];
  List<Movie> _topRated = [];
  List<Movie> _nowPlaying = [];
  List<Movie> _airingToday = [];
  List<Movie> _onTheAir = [];
  bool _loading = true;
  Object? _error;
  bool _showOnboardingBanner = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Öneri motorunun anahtar biçimi: "movie_123" / "tv_456".
  static String _movieKey(Movie m) => "${m.isTV ? 'tv' : 'movie'}_${m.id}";

  /// Film tür id'lerini TMDB'nin dizi tür id'lerine çevirir; dizi tarafında
  /// karşılığı olmayanlar elenir. Boş dönerse TV discover atlanır.
  static List<int> _toTvGenres(List<int> ids) {
    const tvValid = {
      16, 18, 35, 37, 80, 99, 9648, 10751, 10759, 10762, 10763, 10764,
      10765, 10766, 10767, 10768,
    };
    const movieToTv = {28: 10759, 12: 10759, 878: 10765, 14: 10765, 10752: 10768};
    final out = <int>[];
    for (final id in ids) {
      final mapped = movieToTv[id] ?? id;
      if (tvValid.contains(mapped) && !out.contains(mapped)) out.add(mapped);
    }
    return out;
  }

  /// Sıralamayı bozmadan tazelik veren yerel karıştırma: liste [window]'luk
  /// pencerelere bölünür ve her pencere kendi içinde karıştırılır. En iyiler
  /// yine üstte kalır ama dizilim her gün/turda farklı görünür.
  static List<Movie> _windowShuffle(
    List<Movie> items,
    Random rng, {
    int window = 4,
  }) {
    final out = List.of(items);
    for (var start = 0; start < out.length; start += window) {
      final end = min(start + window, out.length);
      final slice = out.sublist(start, end)..shuffle(rng);
      out.setRange(start, end, slice);
    }
    return out;
  }

  // background=true: pull-to-refresh. İskelete geçmeden mevcut içeriği koru;
  // RefreshIndicator spinner'ı içerik üstünde döner (profil davranışıyla aynı).
  Future<void> _load({bool background = false}) async {
    setState(() {
      if (!background) _loading = true;
      _error = null;
    });
    if (background) {
      _reloadNonce++;
      try {
        await DatabaseHelper().deleteTmdbCachePaths([
          '/3/trending/all/week',
          '/3/movie/popular',
          '/3/tv/popular',
          '/3/movie/upcoming',
          '/3/movie/top_rated',
          '/3/movie/now_playing',
          '/3/tv/airing_today',
          '/3/tv/on_the_air',
        ]);
        // Tür örneklemesi tura göre değiştiği için tüm discover cache'i temizle.
        await DatabaseHelper().deleteTmdbCacheKeysContaining([
          'with_genres=',
        ]);
      } catch (e, st) {
        debugPrint("Error clearing TMDB cache on browse refresh: $e\n$st");
      }
    }
    final isAuthenticated = ref.read(authProvider).isAuthenticated;
    if (isAuthenticated) {
      // initState/build sırasında provider state'i değiştirmek yasaktır
      // (Riverpod "Tried to modify a provider while the widget tree was
      // building" hatası). Bu yüzden build bitene kadar erteliyoruz.
      Future.microtask(() {
        if (!mounted) return;
        ref.read(socialProvider.notifier).loadFriends();
        ref.read(socialProvider.notifier).loadActivityFeed();
      });
    }

    try {
      final page = ref.read(browsePopularPageProvider);
      final engine = ref.read(recommendationEngineProvider);

      // Güne bağlı tohumlu rastgelelik: aynı gün içinde stabil ("günün seçkisi"
      // hissi), her gün farklı. Pull-to-refresh (_reloadNonce) gün içinde de
      // yeni bir seçki üretir. Rastgelelik keyfî değil; tohum deterministik.
      final now = DateTime.now();
      final daySeed = now.year * 10000 + now.month * 100 + now.day;
      final rng = Random(daySeed + _reloadNonce * 101);

      // Tür örnekleme: hep aynı "top-3 tür" yerine ağırlık dağılımından örnekle
      // (uzun kuyruktaki türler de ara sıra havuza girer).
      final likedGenres = await PrefsService.sampleLikedGenreIds(
        Random(daySeed + _reloadNonce * 101),
      );

      // Sayfa rotasyonu: sabit 1-2. sayfalar yerine güne/tura göre kaydır.
      final basePage = 1 + (daySeed + _reloadNonce) % 4;
      final tvGenres = _toTvGenres(likedGenres);

      // Phase 1: Load critical lists needed for Tonight's Pick, For You, and Trending
      final phase1Results = await Future.wait([
        _service.discoverByGenres(likedGenres, isTV: false, page: basePage),
        _service.discoverByGenres(likedGenres, isTV: false, page: basePage + 1),
        _service.getTrending(),
        // Dizi discover'ı: Sana Özel artık yalnız filmden beslenmiyor.
        tvGenres.isEmpty
            ? Future.value(<Movie>[])
            : _service
                .discoverByGenres(tvGenres, isTV: true, page: basePage)
                .catchError((_) => <Movie>[]),
      ]).timeout(const Duration(seconds: 12));

      if (!mounted) return;

      final List<Movie> page1 = List<Movie>.from(phase1Results[0]);
      final List<Movie> page2 = List<Movie>.from(phase1Results[1]);
      final List<Movie> trendingList = List<Movie>.from(phase1Results[2]);
      final List<Movie> tvDiscover = List<Movie>.from(phase1Results[3]);

      // Tohum rotasyonu: her gün/turda farklı beğeniler tohum olur.
      final seedCandidates = await engine.fetchSeedCandidates(
        rng: Random(daySeed + _reloadNonce * 101 + 7),
      );

      Map<String, List<String>> friendSignals = const {};
      if (isAuthenticated) {
        try {
          final raw = await ref.read(apiServiceProvider).getFriendSignals();
          friendSignals = raw.map(
            (k, v) => MapEntry(
              k,
              (v as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          );
        } catch (e) {
          debugPrint("Friend signals unavailable for browse: $e");
        }
      }

      // Zaten puanlanmış + kullanıcının engellediği yapımlar vitrine dönmesin.
      final ratedIds = await PrefsService.getRatedIds();
      final blockedKeys = await PrefsService.getBlockedKeys();

      // Impression cooldown: son 72 saatte gösterilenler hafif geri çekilir.
      final impressions = await PrefsService.getRecoImpressions();
      final nowMs = now.millisecondsSinceEpoch;
      const coolWindowMs = 72 * 3600 * 1000;
      final cooldownKeys = {
        for (final e in impressions.entries)
          if (nowMs - e.value < coolWindowMs) e.key,
      };

      final ranked = await engine.rankForYou(
        [...page1, ...page2, ...tvDiscover, ...seedCandidates],
        excludedKeys: {...ratedIds, ...blockedKeys},
        friendSignals: friendSignals,
        cooldownKeys: cooldownKeys,
      );

      // Vitrin havuzu: tepe 12 aday; son 7 gün vitrin olmuş yapımlar elenir
      // (havuz boşalırsa kısıt gevşetilir). Başlangıç noktası tepe 5 içinden
      // güne bağlı seçilir — argmax'ın "hep aynı film" tekelini kırar.
      final tonightHistory = await PrefsService.getTonightHistory();
      const tonightCooldownMs = 7 * 24 * 3600 * 1000;
      final topSlice = ranked.take(12).toList();
      var pool = topSlice.where((m) {
        final last = tonightHistory[_movieKey(m)];
        return last == null || nowMs - last > tonightCooldownMs;
      }).toList();
      if (pool.isEmpty) pool = topSlice;
      if (pool.length > 1) {
        final start = rng.nextInt(min(5, pool.length));
        pool = [...pool.sublist(start), ...pool.sublist(0, start)];
      }
      final Movie? tonightPick = pool.isNotEmpty ? pool.first : null;

      // Sana Özel: vitrindeki hariç ilk 20; pencere-içi karıştırma ile her
      // gün/turda farklı dizilim (en iyiler yine üstte kalır).
      final List<Movie> finalPersonal = _windowShuffle(
        ranked
            .where((m) => tonightPick == null || _movieKey(m) != _movieKey(tonightPick))
            .take(20)
            .toList(),
        rng,
      );

      // Keşif dilimi (epsilon-greedy): rayın küçük bir kısmı bilinçli olarak
      // zevk profili DIŞINDAN (trend listesi) gelir; oran, 'explore'
      // kaynağının telemetrideki beğeni dönüşümüne göre kendini ayarlar.
      try {
        final exploreRate = await engine.adaptiveExploreRate();
        final exploreCount =
            (finalPersonal.length * exploreRate).round().clamp(0, 3);
        if (exploreCount > 0) {
          final explorePicks = engine.pickExplorationCandidates(
            pool: trendingList,
            rankedKeys: ranked.map(_movieKey).toSet(),
            excludedKeys: {
              ...ratedIds,
              ...blockedKeys,
              if (tonightPick != null) _movieKey(tonightPick),
            },
            rng: rng,
            count: exploreCount,
          );
          // Kümelenmesin: 4., 9., 14. pozisyonlara serpiştir; ray 20'de kalsın.
          var pos = 4;
          for (final m in explorePicks) {
            if (pos >= finalPersonal.length) {
              finalPersonal.add(m);
            } else {
              finalPersonal.insert(pos, m);
            }
            pos += 5;
          }
          while (finalPersonal.length > 20) {
            finalPersonal.removeLast();
          }
        }
      } catch (e) {
        debugPrint("Exploration slice failed (non-fatal): $e");
      }

      // Gösterim hafızasını yaz (best-effort, akışı bekletme).
      final shownKeys = <String>[
        if (tonightPick != null) _movieKey(tonightPick),
        ...finalPersonal.take(10).map(_movieKey),
      ];
      unawaited(PrefsService.recordRecoImpressions(shownKeys));
      if (tonightPick != null) {
        unawaited(PrefsService.recordTonightPick(_movieKey(tonightPick)));
      }

      final ratingCount = await PrefsService.getRatingCount();
      final bannerDismissed = await PrefsService.isOnboardingBannerDismissed();
      final initialGenres = await PrefsService.getInitialGenres();
      final showBanner =
          ratingCount == 0 && initialGenres.isEmpty && !bannerDismissed;

      setState(() {
        _tonight = tonightPick;
        _tonightPool = pool;
        _tonightCursor = 0;
        _personal = finalPersonal;
        _trending = trendingList;
        _showOnboardingBanner = showBanner;
        _loading = false;
      });

      // Phase 2: Load secondary lists in the background
      Future.wait([
            _service.getPopular(isTV: false, page: page),
            _service.getPopular(isTV: true, page: page),
            _service.getUpcoming(),
            _service.getTopRated(isTV: false),
            _service.getNowPlaying(),
            _service.getAiringToday(),
            _service.getOnTheAir(),
          ])
          .then((phase2Results) {
            if (!mounted) return;
            setState(() {
              _movies = List<Movie>.from(phase2Results[0])..shuffle(_rng);
              _shows = List<Movie>.from(phase2Results[1])..shuffle(_rng);
              _upcoming = List<Movie>.from(phase2Results[2])..shuffle(_rng);
              _topRated = List<Movie>.from(phase2Results[3]);
              _nowPlaying = List<Movie>.from(phase2Results[4])..shuffle(_rng);
              _airingToday = List<Movie>.from(phase2Results[5])..shuffle(_rng);
              _onTheAir = List<Movie>.from(phase2Results[6])..shuffle(_rng);
            });
          })
          .catchError((e, st) {
            debugPrint("Error loading secondary browse lists: $e\n$st");
          });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tonight = null;
        _tonightPool = [];
        _tonightCursor = 0;
        _personal = [];
        _trending = [];
        _movies = [];
        _shows = [];
        _upcoming = [];
        _topRated = [];
        _nowPlaying = [];
        _airingToday = [];
        _onTheAir = [];
        _showOnboardingBanner = false;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// "Başka öner": vitrin havuzundaki sıradaki adayı getirir. Eski seçim
  /// "Sana Özel" rayının üstlerine geri konur (kaybolmaz), yeni seçim raydan
  /// düşürülür (ekranda kopya görünmesin).
  void _shuffleTonight() {
    if (_tonightPool.length < 2) return;
    HapticFeedback.lightImpact();
    setState(() {
      final old = _tonight;
      _tonightCursor = (_tonightCursor + 1) % _tonightPool.length;
      _tonight = _tonightPool[_tonightCursor];
      final newPick = _tonight!;
      _personal.removeWhere(
        (m) => m.id == newPick.id && m.isTV == newPick.isTV,
      );
      if (old != null &&
          !_personal.any((m) => m.id == old.id && m.isTV == old.isTV)) {
        _personal.insert(min(3, _personal.length), old);
      }
    });
    final pick = _tonight;
    if (pick != null) {
      unawaited(PrefsService.recordTonightPick(_movieKey(pick)));
      unawaited(PrefsService.recordRecoImpressions([_movieKey(pick)]));
    }
  }

  /// "İlgimi çekmedi": yapımı kalıcı engeller (bir daha hiçbir öneri yüzeyinde
  /// çıkmaz) ve vitrine sıradaki adayı getirir — motor için gerçek negatif sinyal.
  Future<void> _dismissTonight() async {
    final dismissed = _tonight;
    if (dismissed == null) return;
    HapticFeedback.mediumImpact();
    await PrefsService.blockMovie(dismissed.id, dismissed.isTV);
    if (!mounted) return;
    setState(() {
      _tonightPool.removeWhere(
        (m) => m.id == dismissed.id && m.isTV == dismissed.isTV,
      );
      if (_tonightPool.isNotEmpty) {
        _tonightCursor %= _tonightPool.length;
        _tonight = _tonightPool[_tonightCursor];
        final promoted = _tonight!;
        _personal.removeWhere(
          (m) => m.id == promoted.id && m.isTV == promoted.isTV,
        );
      } else {
        _tonight = null;
      }
    });
    _removeBlockedMovie(dismissed);
    // Havuz da ray da boşaldıysa vitrini rayın ilk adayıyla doldur.
    if (_tonight == null && _personal.isNotEmpty) {
      setState(() => _tonight = _personal.removeAt(0));
    }
    final pick = _tonight;
    if (pick != null) {
      unawaited(PrefsService.recordTonightPick(_movieKey(pick)));
    }
  }

  void _removeBlockedMovie(Movie movie) {
    setState(() {
      _tonightPool.removeWhere(
        (m) => m.id == movie.id && m.isTV == movie.isTV,
      );
      if (_tonight?.id == movie.id && _tonight?.isTV == movie.isTV) {
        // Vitrindeki seçim engellendi → havuzdaki/raydaki ilk aday terfi eder.
        if (_tonightPool.isNotEmpty) {
          _tonightCursor %= _tonightPool.length;
          _tonight = _tonightPool[_tonightCursor];
          final promoted = _tonight!;
          _personal.removeWhere(
            (m) => m.id == promoted.id && m.isTV == promoted.isTV,
          );
        } else {
          _tonight = _personal.isNotEmpty ? _personal.removeAt(0) : null;
        }
      }
      _personal.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _trending.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _movies.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _shows.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _upcoming.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _topRated.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _nowPlaying.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _airingToday.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
      _onTheAir.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
    });
  }

  Future<void> _luckyPick() async {
    HapticFeedback.lightImpact();

    final isFirst = await PrefsService.isFirstTimeDice();
    if (isFirst && mounted) {
      final tr = AppLocalizations.of(context);
      final c = context.c;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            tr?.locale.languageCode == 'tr'
                ? 'Şanslı Seçim 🎲'
                : 'Lucky Pick 🎲',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            tr?.locale.languageCode == 'tr'
                ? 'Bu zar butonu, puanladığınız filmlerden yola çıkarak zevklerinize uygun rastgele bir film seçer. "Şaşırt beni" demek istediğinizde kullanabilirsiniz!'
                : 'This dice button selects a random movie tailored to your tastes based on the films you have rated. Use it whenever you want to be surprised!',
            style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                tr?.locale.languageCode == 'tr' ? 'Anladım' : 'Got it',
                style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    try {
      final likedGenres = await PrefsService.getLikedGenreIds();
      var results = await _service.discoverByGenres(likedGenres, isTV: false);
      if (results.isEmpty) {
        results = await _service.getPopular(isTV: false);
      }
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('browse_conn_error') ??
                  'Bağlantı hatası veya sonuç bulunamadı.',
            ),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
      final movie = results[_rng.nextInt(results.length)];
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => MovieDetailSheet(movie: movie, service: _service),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red),
      );
    }
  }

  void _goMood(_Mood mood) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          genreStr: mood.genreStr,
          minRating: mood.minRating,
          maxRuntime: mood.maxRuntime,
          decade: mood.decade,
          includeTv: mood.includeTv,
          sortBy: 'vote_average.desc',
          // Mood bir kısayoldur, sıralaması yine kullanıcının zevkine göre:
          // aynı "Korku gecesi" iki kullanıcıda farklı dizilir.
          personalRank: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(localeProvider, (previous, next) {
      if (previous != next) {
        _load();
      }
    });

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated &&
          next.isAuthenticated) {
        ref.read(socialProvider.notifier).loadFriends();
        ref.read(socialProvider.notifier).loadActivityFeed();
      }
    });

    return Scaffold(
      backgroundColor: context.c.bg,
      body: CinematicBackground(
        animate: true,
        child: SafeArea(child: _loading ? const BrowseSkeleton() : _content()),
      ),
    );
  }

  Widget _content() {
    final c = context.c;
    final authState = ref.watch(authProvider);
    final socialState = ref.watch(socialProvider);
    final isAuthenticated = authState.isAuthenticated;
    if (_personal.isEmpty && _trending.isEmpty && _movies.isEmpty) {
      final errorStr = _error.toString();
      final isNetworkError =
          errorStr.contains('No internet connection') ||
          errorStr.contains('SocketException') ||
          errorStr.contains('Failed host lookup') ||
          errorStr.contains('timed out') ||
          errorStr.contains('TimeoutException');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isNetworkError
                  ? Icons.cloud_off_rounded
                  : Icons.error_outline_rounded,
              color: c.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isNetworkError
                  ? (AppLocalizations.of(
                          context,
                        )?.get('browse_offline_title') ??
                        'You are Offline')
                  : (_error.toString().contains('401')
                        ? (AppLocalizations.of(
                                context,
                              )?.get('browse_api_unauthorized') ??
                              'Service Unauthorized')
                        : (AppLocalizations.of(context)?.get('browse_error') ??
                              'An error occurred while loading content.')),
              style: TextStyle(
                color: c.ink,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isNetworkError
                    ? (AppLocalizations.of(
                            context,
                          )?.get('browse_offline_desc') ??
                          'Please check your internet connection and try again.')
                    : (_error.toString().contains('401')
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('browse_api_unauthorized_desc') ??
                                'The server is unable to authenticate with the movie service. Please contact support.')
                          : (AppLocalizations.of(
                                  context,
                                )?.get('browse_conn_error') ??
                                'Check your internet connection and try again.')),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                AppLocalizations.of(context)?.get('browse_retry') ??
                    'Yeniden Dene',
              ),
            ),
          ],
        ),
      );
    }

    ref.listen<int>(browseScrollTriggerProvider, (previous, next) {
      if (next > 0 && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: () => _load(background: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // ── Header ────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Başlık ─────────────────────────────────────────────────
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context)?.get('what_to') ??
                            'what to ',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)?.get('watch') ?? 'watch?',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Semantics(
                        label:
                            AppLocalizations.of(
                              context,
                            )?.get('semantics_refresh') ??
                            'Refresh recommendations',
                        button: true,
                        child: IconButton(
                          icon: Icon(
                            Icons.refresh_rounded,
                            color: c.dim,
                            size: 20,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _load();
                          },
                          tooltip:
                              AppLocalizations.of(
                                context,
                              )?.get('browse_refresh') ??
                              'Yenile',
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.language_rounded,
                            color: c.dim,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip:
                              AppLocalizations.of(
                                    context,
                                  )?.locale.languageCode ==
                                  'tr'
                              ? 'Dil Seçimi'
                              : 'Change Language',
                          onSelected: (String langCode) {
                            HapticFeedback.mediumImpact();
                            ref
                                .read(localeProvider.notifier)
                                .setLocale(langCode);
                          },
                          itemBuilder: (BuildContext context) => [
                            PopupMenuItem(
                              value: 'tr',
                              child: Row(
                                children: [
                                  const Text(
                                    '🇹🇷',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Türkçe',
                                    style: TextStyle(
                                      color: c.ink,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'en',
                              child: Row(
                                children: [
                                  const Text(
                                    '🇺🇸',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'English',
                                    style: TextStyle(
                                      color: c.ink,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          offset: const Offset(0, 40),
                          color: c.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sürpriz/zar: zevke uygun rastgele film. "Bu Gece"
                      // kartı motorun EN İYİ tahminini verirken bu "şaşırt
                      // beni" niyetini karşılar; header'da küçük durur ki iki
                      // ayrı "ne izlesem" kahramanı çakışmasın.
                      Semantics(
                        label:
                            AppLocalizations.of(
                              context,
                            )?.get('browse_surprise') ??
                            'Sürpriz film',
                        button: true,
                        child: IconButton(
                          icon: Icon(
                            Icons.casino_rounded,
                            color: c.dim,
                            size: 20,
                          ),
                          onPressed: _luckyPick,
                          tooltip:
                              AppLocalizations.of(
                                context,
                              )?.get('browse_surprise') ??
                              'Sürpriz film',
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        label:
                            AppLocalizations.of(context)?.get('theme_switch') ??
                            'Tema',
                        button: true,
                        child: IconButton(
                          icon: Icon(
                            Theme.of(context).brightness == Brightness.light
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            color: c.dim,
                            size: 20,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            ref.read(themeModeProvider.notifier).toggle();
                          },
                          tooltip:
                              AppLocalizations.of(
                                context,
                              )?.get('theme_switch') ??
                              'Tema',
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      if (isAuthenticated) ...[
                        const SizedBox(width: 8),
                        // Hesap/profil kısayolu. Sosyal ağ artık "Birlikte"
                        // alt sekmesinde; başlık sadeleşti.
                        Semantics(
                          label:
                              AppLocalizations.of(
                                context,
                              )?.get('tab_profile') ??
                              'Profil',
                          button: true,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onOpenProfile?.call();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: CinemaGradients.crimson,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _profileInitial(authState),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Ruh hali ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    AppLocalizations.of(context)?.get('browse_mood') ??
                        'Ruh haline göre',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _moods.length,
                    itemBuilder: (ctx, i) {
                      final m = _moods[i];
                      return GestureDetector(
                        onTap: () => _goMood(m),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: c.border, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(m.icon, color: c.red, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context)?.get(m.label) ??
                                    m.label,
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ── Onboarding / Taste Banner Reminder ──────────────────────────────
          if (_showOnboardingBanner)
            SliverToBoxAdapter(child: _buildOnboardingBanner(context, c)),

          // ── Bu Gece Ne İzlesem? (motorun en yüksek skorlu seçimi) ────────────
          if (_tonight != null)
            SliverToBoxAdapter(
              child: EntranceFade(
                child: TonightPickCard(
                  movie: _tonight!,
                  onTap: () => _openDetail(_tonight!),
                  onShuffle: _tonightPool.length > 1 ? _shuffleTonight : null,
                  onDismiss: _dismissTonight,
                ),
              ),
            ),

          // ── Sana Özel ─────────────────────────────────────────────────────────
          if (_personal.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_for_you_personal') ??
                  '',
              _personal,
              showScore: true,
            ),

          // ── Arkadaşlarından Son Sinyaller ──────────────────────────────────────────
          if (isAuthenticated && socialState.activityFeed.isNotEmpty)
            _friendsActivitySection(socialState.activityFeed),

          // ── Bu Hafta Trend ────────────────────────────────────────────────────
          if (_trending.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_trending_week') ?? '',
              _trending,
            ),

          // ── Sinema'da ─────────────────────────────────────────────────────────
          if (_nowPlaying.isNotEmpty)
            _section(
              AppLocalizations.of(
                    context,
                  )?.get('browse_now_playing_theaters') ??
                  '',
              _nowPlaying,
              badge: '🎬',
            ),

          // ── Popüler Filmler ───────────────────────────────────────────────────
          if (_movies.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_popular_movies') ?? '',
              _movies,
            ),

          // ── Bu Gün TV'de ──────────────────────────────────────────────────────
          if (_airingToday.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_airing_today_tv') ?? '',
              _airingToday,
              badge: '📺',
            ),

          // ── Şu An Yayında ─────────────────────────────────────────────────────
          if (_onTheAir.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_on_the_air_tv') ?? '',
              _onTheAir,
            ),

          // ── Popüler Diziler ───────────────────────────────────────────────────
          if (_shows.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_popular_tvs') ?? '',
              _shows,
            ),

          // ── Yakında Gelecekler ────────────────────────────────────────────────
          if (_upcoming.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_upcoming_coming') ?? '',
              _upcoming,
            ),

          // ── En Yüksek Puanlı ─────────────────────────────────────────────────
          if (_topRated.isNotEmpty)
            _section(
              AppLocalizations.of(context)?.get('browse_top_rated_movies') ??
                  '',
              _topRated,
              // showScore kapalı: buradaki skor kişisel eşleşme değil, ham TMDB
              // puanı (voteAverage×10) olurdu — yanıltıcı "%92 uyum" gösterirdi.
              showScore: false,
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _section(
    String title,
    List<Movie> items, {
    bool showScore = false,
    String? badge,
  }) {
    final c = context.c;
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      gradient: CinemaGradients.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (badge != null) ...[
                    Text(badge, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 275,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (ctx, i) => _BrowseCard(
                  movie: items[i],
                  showScore: showScore,
                  onTap: () => _openDetail(items[i]),
                  onBlocked: () => _removeBlockedMovie(items[i]),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _friendsActivitySection(List<dynamic> feed) {
    final c = context.c;
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      gradient: CinemaGradients.crimson,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.get('browse_friends_activity') ??
                        'Arkadaşlarından Son Sinyaller',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: feed.length,
                itemBuilder: (ctx, i) {
                  final item = feed[i];
                  final title = item['title'] as String? ?? '';
                  final posterPath = item['poster_path'] as String? ?? '';
                  final rating = item['rating'] is int
                      ? item['rating'] as int
                      : (int.tryParse(item['rating']?.toString() ?? '') ?? 0);
                  final friendName =
                      item['friend_name'] as String? ??
                      item['friend_username'] as String? ??
                      'Arkadaşın';

                  final ratingKey = rating >= 3
                      ? 'browse_rating_excellent'
                      : 'browse_rating_good';
                  final ratingText =
                      AppLocalizations.of(context)?.get(ratingKey) ??
                      (rating >= 3 ? 'Harika dedi' : 'İyi dedi');

                  final parsedId = item['movie_id'] is int
                      ? item['movie_id'] as int
                      : (int.tryParse(item['movie_id']?.toString() ?? '') ?? 0);
                  final parsedIsTvVal = item['is_tv'] is int
                      ? item['is_tv'] as int
                      : (int.tryParse(item['is_tv']?.toString() ?? '') ?? 0);

                  final movie = Movie(
                    id: parsedId,
                    isTV: parsedIsTvVal == 1,
                    title: title,
                    posterPath: posterPath,
                    backdropPath: '',
                    overview: '',
                    voteAverage: 0,
                    releaseDate: '',
                    genreIds: [],
                  );

                  return GestureDetector(
                    onTap: () => _openDetail(movie),
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: CinemaShadows.card,
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      color: c.surface,
                                      child: posterPath.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl:
                                                  'https://image.tmdb.org/t/p/w342$posterPath',
                                              fit: BoxFit.cover,
                                              memCacheWidth: 180,
                                              placeholder: (context, url) =>
                                                  const PulsingPlaceholder(),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const PulsingPlaceholder(),
                                            )
                                          : const PulsingPlaceholder(),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        MovieDetailSheet.confirmBlockMovie(
                                          context: context,
                                          ref: ref,
                                          movie: movie,
                                          onBlocked: () =>
                                              _removeBlockedMovie(movie),
                                        );
                                      },
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.visibility_off_rounded,
                                          color: Colors.white,
                                          size: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        MovieDetailSheet.showRecommendSheet(
                                          context: context,
                                          ref: ref,
                                          movie: movie,
                                        );
                                      },
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.send_rounded,
                                          color: Colors.white,
                                          size: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                rating >= 3
                                    ? Icons.favorite_rounded
                                    : Icons.thumb_up_rounded,
                                color: c.red,
                                size: 11,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$friendName $ratingText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.dim,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: _service),
    );
  }

  /// Başlık avatarı için kullanıcının baş harfi (display_name → username → '?').
  String _profileInitial(AuthState authState) {
    final user = authState.user;
    final name = (user?['display_name'] as String?)?.trim();
    final username = (user?['username'] as String?)?.trim();
    final source = (name != null && name.isNotEmpty)
        ? name
        : (username != null && username.isNotEmpty ? username : '');
    return source.isEmpty ? '?' : source[0].toUpperCase();
  }

  Widget _buildOnboardingBanner(BuildContext context, ThemePalette c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.gold.withValues(alpha: 0.12),
            c.goldSoft.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gold.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 40, 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.gold.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: c.gold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('personalize_recommendations') ??
                              'Personalize Recommendations',
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('complete_the_2minute_survey_fo') ??
                              'Complete the 2-minute survey for the best matching movies and shows!',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Icon(Icons.close_rounded, color: c.dim, size: 18),
              onPressed: () async {
                HapticFeedback.lightImpact();
                await PrefsService.dismissOnboardingBanner();
                setState(() {
                  _showOnboardingBanner = false;
                });
              },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              splashRadius: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseCard extends ConsumerWidget {
  final Movie movie;
  final bool showScore;
  final VoidCallback onTap;
  final VoidCallback onBlocked;

  const _BrowseCard({
    required this.movie,
    required this.showScore,
    required this.onTap,
    required this.onBlocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: CinemaShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      movie.posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: movie.posterUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 240,
                              placeholder: (context, url) =>
                                  const PulsingPlaceholder(),
                              errorWidget: (context, url, error) =>
                                  const PulsingPlaceholder(),
                            )
                          : const PulsingPlaceholder(),
                      // İnce iç kenar ışığı
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            MovieDetailSheet.confirmBlockMovie(
                              context: context,
                              ref: ref,
                              movie: movie,
                              onBlocked: onBlocked,
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.visibility_off_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            MovieDetailSheet.showRecommendSheet(
                              context: context,
                              ref: ref,
                              movie: movie,
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                      if (showScore)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.66),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.green.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.bolt_rounded,
                                  color: AppColors.green,
                                  size: 11,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${movie.matchScore}',
                                  style: const TextStyle(
                                    color: AppColors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Gerekçe varsa yılın yerine "neden önerildi" satırı — "seni
            // tanıyor" hissini kart seviyesine taşır (yıl detayda zaten var).
            Builder(
              builder: (context) {
                final reason = showScore
                    ? recoReasonLabel(context, movie)
                    : null;
                if (reason == null) {
                  return Text(
                    movie.year,
                    style: TextStyle(color: c.dim, fontSize: 12.5),
                  );
                }
                return Row(
                  children: [
                    Icon(
                      movie.recoReasonType == 'friend'
                          ? Icons.favorite_rounded
                          : Icons.auto_awesome_rounded,
                      size: 11,
                      color: c.goldSoft,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.goldSoft,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
