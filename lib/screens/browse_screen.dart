import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../models/social.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/db_helper.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/entrance.dart';
import '../widgets/tonight_pick_card.dart';
import 'browse/browse_skeleton.dart';
import 'browse/browse_card.dart';
import 'browse/browse_error_view.dart';
import 'browse/browse_section_header.dart';
import 'browse/browse_top_profile_card.dart';
import 'browse/friend_signal_card.dart';
import 'browse/moods.dart';
import 'browse/onboarding_banner.dart';
import 'movie_detail_sheet.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';

/// Keşfet orkestratörü: öneri motoru kablolaması (günlük tohumlu seçki,
/// vitrin havuzu, keşif dilimi) ve ray düzeni burada; kartlar ve yardımcı
/// görünümler browse/ altında yaşar.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

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
      16,
      18,
      35,
      37,
      80,
      99,
      9648,
      10751,
      10759,
      10762,
      10763,
      10764,
      10765,
      10766,
      10767,
      10768,
    };
    const movieToTv = {
      28: 10759,
      12: 10759,
      878: 10765,
      14: 10765,
      10752: 10768,
    };
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
        await DatabaseHelper().deleteTmdbCacheKeysContaining(['with_genres=']);
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
        ref.read(socialProvider.notifier).loadTopProfiles();
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
          friendSignals =
              (await ref.read(apiServiceProvider).getFriendSignals())
                  .toRecommendationMap();
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
            .where(
              (m) =>
                  tonightPick == null || _movieKey(m) != _movieKey(tonightPick),
            )
            .take(20)
            .toList(),
        rng,
      );

      // Keşif dilimi (epsilon-greedy): rayın küçük bir kısmı bilinçli olarak
      // zevk profili DIŞINDAN (trend listesi) gelir; oran, 'explore'
      // kaynağının telemetrideki beğeni dönüşümüne göre kendini ayarlar.
      try {
        final exploreRate = await engine.adaptiveExploreRate();
        final exploreCount = (finalPersonal.length * exploreRate).round().clamp(
          0,
          3,
        );
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
      _tonightPool.removeWhere((m) => m.id == movie.id && m.isTV == movie.isTV);
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
        ref.read(socialProvider.notifier).loadTopProfiles();
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
    final socialState = ref.watch(socialProvider);
    final isAuthenticated = ref.watch(authProvider).isAuthenticated;
    if (_personal.isEmpty && _trending.isEmpty && _movies.isEmpty) {
      return BrowseErrorView(error: _error, onRetry: _load);
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
          // Araç ikonları (yenile, zar, dil, tema, hakkında, web, avatar)
          // global üst bara/menüye taşındı; başlık tek başına kaldı.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)?.get('what_to') ?? 'what to ',
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
                const MoodChipsRow(),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ── Onboarding / Taste Banner Reminder ──────────────────────────────
          if (_showOnboardingBanner)
            SliverToBoxAdapter(
              child: OnboardingReminderBanner(
                onDismissed: () =>
                    setState(() => _showOnboardingBanner = false),
              ),
            ),

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

          // ── Popüler Üyeler ─────────────────────────────────────────────────────────
          if (isAuthenticated && socialState.topProfiles.isNotEmpty)
            _topProfilesSection(socialState.topProfiles),

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
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title: title,
              badge: badge,
              gradient: CinemaGradients.gold,
            ),
            SizedBox(
              height: 275,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (ctx, i) => BrowseCard(
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

  Widget _friendsActivitySection(List<ActivityItem> feed) {
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title:
                  AppLocalizations.of(
                        context,
                      )?.get('browse_friends_activity') ??
                      'Arkadaşlarından Son Sinyaller',
              gradient: CinemaGradients.crimson,
            ),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: feed.length,
                itemBuilder: (ctx, i) => FriendSignalCard(
                  item: feed[i],
                  onOpen: _openDetail,
                  onBlocked: _removeBlockedMovie,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _topProfilesSection(List<TopProfile> profiles) {
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title:
                  AppLocalizations.of(context)?.get('top_lists_title') ??
                  'Popüler Listeler',
              gradient: CinemaGradients.crimson,
            ),
            SizedBox(
              height: 136,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: profiles.length,
                itemBuilder: (ctx, i) =>
                    BrowseTopProfileCard(profile: profiles[i], rank: i + 1),
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
}
