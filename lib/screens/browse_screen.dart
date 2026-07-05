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
import '../widgets/shimmer.dart';
import 'movie_detail_sheet.dart';
import 'results_screen.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';
import 'onboarding_screen.dart';
import '../widgets/spring_button.dart';

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

const _moods = [
  _Mood(
    icon: Icons.sentiment_very_satisfied_rounded,
    label: 'mood_funny',
    genreStr: '35',
    includeTv: false,
  ),
  _Mood(
    icon: Icons.psychology_rounded,
    label: 'mood_thrill',
    genreStr: '53,27',
    minRating: 7.0,
    includeTv: false,
  ),
  _Mood(
    icon: Icons.sentiment_very_dissatisfied_rounded,
    label: 'mood_cry',
    genreStr: '18,10749',
    minRating: 7.5,
  ),
  _Mood(
    icon: Icons.bolt_rounded,
    label: 'mood_action',
    genreStr: '28,12',
    includeTv: false,
  ),
  _Mood(
    icon: Icons.spa_rounded,
    label: 'mood_light',
    genreStr: '35,16',
    maxRuntime: 100,
    includeTv: false,
  ),
  _Mood(
    icon: Icons.lightbulb_outline_rounded,
    label: 'mood_thought',
    genreStr: '18,9648',
    minRating: 7.8,
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
    genreStr: '14,878',
  ),
  _Mood(icon: Icons.gavel_rounded, label: 'mood_crime', genreStr: '80,53'),
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

  // background=true: pull-to-refresh. İskelete geçmeden mevcut içeriği koru;
  // RefreshIndicator spinner'ı içerik üstünde döner (profil davranışıyla aynı).
  Future<void> _load({bool background = false}) async {
    setState(() {
      if (!background) _loading = true;
      _error = null;
    });
    if (background) {
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
        final likedGenres = await PrefsService.getLikedGenreIds();
        if (likedGenres.isNotEmpty) {
          await DatabaseHelper().deleteTmdbCacheKeysContaining([
            'with_genres=${likedGenres.join('|')}',
          ]);
        }
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
      final likedGenres = await PrefsService.getLikedGenreIds();
      final results = await Future.wait([
        _service.discoverByGenres(likedGenres, isTV: false, page: 1),
        _service.discoverByGenres(likedGenres, isTV: false, page: 2),
        _service.getTrending(),
        _service.getPopular(isTV: false, page: page),
        _service.getPopular(isTV: true, page: page),
        _service.getUpcoming(),
        _service.getTopRated(isTV: false),
        _service.getNowPlaying(),
        _service.getAiringToday(),
        _service.getOnTheAir(),
      ]).timeout(const Duration(seconds: 20));
      if (!mounted) return;

      // Re-ranking process for "Sana Özel" (Personalized) candidates
      final List<Movie> page1 = List<Movie>.from(results[0]);
      final List<Movie> page2 = List<Movie>.from(results[1]);
      final Set<int> seenIds = {};
      final List<Movie> rawCandidates = [];
      for (final m in [...page1, ...page2]) {
        if (seenIds.add(m.id)) {
          rawCandidates.add(m);
        }
      }

      final userWeights = await PrefsService.getGenreWeights();
      final List<Map<String, dynamic>> scoredCandidates = [];

      for (final m in rawCandidates) {
        final double similarity = PrefsService.calculateSimilarity(
          userWeights,
          m.genreIds,
        );
        final double rawScore = 0.7 * similarity + 0.3 * (m.voteAverage / 10.0);

        // Sigmoid normalisation centering around 0.2 (cold start average)
        // Map raw score to realistic display match percentage [40, 98]
        final double z = (rawScore - 0.2) * 4.0;
        final double sigmoid = 1.0 / (1.0 + exp(-z));
        final int displayScore = (40 + (sigmoid * 58)).round();

        m.personalizedMatchScore = displayScore.clamp(40, 98);
        scoredCandidates.add({'movie': m, 'score': rawScore});
      }

      // Sort by raw similarity score descending
      scoredCandidates.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );
      final List<Movie> finalPersonal = scoredCandidates
          .map((e) => e['movie'] as Movie)
          .take(20)
          .toList();

      final ratingCount = await PrefsService.getRatingCount();
      final bannerDismissed = await PrefsService.isOnboardingBannerDismissed();
      final initialGenres = await PrefsService.getInitialGenres();
      final showBanner =
          ratingCount == 0 && initialGenres.isEmpty && !bannerDismissed;

      setState(() {
        _personal = finalPersonal;
        // "Bu Hafta Trend" sıralı bir listedir — shuffle sırayı bozardı.
        _trending = List<Movie>.from(results[2]);
        _movies = List<Movie>.from(results[3])..shuffle(_rng);
        _shows = List<Movie>.from(results[4])..shuffle(_rng);
        _upcoming = List<Movie>.from(results[5])..shuffle(_rng);
        // "En Yüksek Puanlı" sıralı bir listedir — shuffle etiketi yalanlar.
        _topRated = List<Movie>.from(results[6]);
        _nowPlaying = List<Movie>.from(results[7])..shuffle(_rng);
        _airingToday = List<Movie>.from(results[8])..shuffle(_rng);
        _onTheAir = List<Movie>.from(results[9])..shuffle(_rng);
        _showOnboardingBanner = showBanner;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _personal = [];
        _trending = [];
        _movies = [];
        _shows = [];
        _upcoming = [];
        _topRated = [];
        _nowPlaying = [];
        _airingToday = [];
        _onTheAir = [];
        _error = e;
        _loading = false;
      });
    }
  }

  void _removeBlockedMovie(Movie movie) {
    setState(() {
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
        child: SafeArea(child: _loading ? _skeleton() : _content()),
      ),
    );
  }

  Widget _skeleton() {
    final c = context.c;
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header placeholder
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 140,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 120,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ],
              ),
            ),
            // Mood placeholders
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: 120,
                height: 18,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                itemBuilder: (ctx, i) => Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: c.border),
                  ),
                ),
              ),
            ),
            // Category List 1 placeholder
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: 150,
                height: 18,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                itemBuilder: (ctx, i) => Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    child: ColoredBox(color: c.surface),
                  ),
                ),
              ),
            ),
            // Category List 2 placeholder
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: 180,
                height: 18,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                itemBuilder: (ctx, i) => Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    child: ColoredBox(color: c.surface),
                  ),
                ),
              ),
            ),
          ],
        ),
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
      final isNetworkError = errorStr.contains('No internet connection') ||
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
                  ? (AppLocalizations.of(context)?.get('browse_offline_title') ?? 'You are Offline')
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
                    ? (AppLocalizations.of(context)?.get('browse_offline_desc') ?? 'Please check your internet connection and try again.')
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
                      AppLocalizations.of(context)?.locale.languageCode == 'tr'
                          ? 'ne '
                          : 'what to ',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)?.locale.languageCode == 'tr'
                          ? 'izlesem?'
                          : 'watch?',
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
                            AppLocalizations.of(context)?.locale.languageCode ==
                                'tr'
                            ? 'Dil Seçimi'
                            : 'Change Language',
                        onSelected: (String langCode) {
                          HapticFeedback.mediumImpact();
                          ref.read(localeProvider.notifier).setLocale(langCode);
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
                                  style: TextStyle(color: c.ink, fontSize: 14),
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
                                  style: TextStyle(color: c.ink, fontSize: 14),
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
                            AppLocalizations.of(context)?.get('theme_switch') ??
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
                            AppLocalizations.of(context)?.get('tab_profile') ??
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

        // ── Bu Akşam Ne İzlesem? CTA Kartı ──────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SpringButton(
              onTap: _luckyPick,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE94560), Color(0xFF8B0000)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE94560).withValues(alpha: 0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.get('browse_cta_title') ?? 'What to Watch Tonight?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppLocalizations.of(context)?.get('browse_cta_subtitle') ?? "Let's roll the dice and pick a random movie matched to your taste.",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.casino_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
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

        // ── Sana Özel ─────────────────────────────────────────────────────────
        if (_personal.isNotEmpty)
          _section(
            AppLocalizations.of(context)?.get('browse_for_you_personal') ?? '',
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
            AppLocalizations.of(context)?.get('browse_now_playing_theaters') ??
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
            AppLocalizations.of(context)?.get('browse_top_rated_movies') ?? '',
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
                                              placeholder: (context, url) =>
                                                  const PulsingPlaceholder(),
                                              errorWidget: (context, url, error) =>
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
                                          onBlocked: () => _removeBlockedMovie(movie),
                                        );
                                      },
                                      child: Container(
                                        width: 24,
                                        height: 24,
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
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
                          isTr
                              ? 'Önerileri Zevkine Göre Kişiselleştir'
                              : 'Personalize Recommendations',
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isTr
                              ? 'Sana en uygun film ve dizileri bulmamız için 2 dakikalık analizi tamamla!'
                              : 'Complete the 2-minute survey for the best matching movies and shows!',
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
            Text(movie.year, style: TextStyle(color: c.dim, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
