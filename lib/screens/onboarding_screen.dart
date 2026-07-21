import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../services/sync_service.dart';
import '../providers/auth_provider.dart';
import '../providers/top_list_provider.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';
import 'onboarding/genre_step.dart';
import 'onboarding/favorite_pick_step.dart';
import 'onboarding/rating_widgets.dart';

const _rBerbat = AppColors.rBerbat;
const _rEh = AppColors.rEh;
const _rIyi = AppColors.rIyi;
const _rHarika = AppColors.rHarika;

// ─── Genre data ──────────────────────────────────────────────────────────────
const _movieGenres = [
  (28, 'Aksiyon', Icons.local_fire_department_rounded),
  (12, 'Macera', Icons.explore_rounded),
  (35, 'Komedi', Icons.sentiment_very_satisfied_rounded),
  (18, 'Drama', Icons.theater_comedy_rounded),
  (27, 'Korku', Icons.mood_bad_rounded),
  (878, 'Bilim Kurgu', Icons.rocket_launch_rounded),
  (53, 'Gerilim', Icons.speed_rounded),
  (10749, 'Romantik', Icons.favorite_rounded),
  (14, 'Fantastik', Icons.auto_fix_high_rounded),
  (80, 'Suç', Icons.gavel_rounded),
  (99, 'Belgesel', Icons.videocam_rounded),
  (16, 'Animasyon', Icons.animation_rounded),
];

const _tvGenres = [
  (10759, 'Aksiyon &\nMacera', Icons.local_fire_department_rounded),
  (18, 'Drama', Icons.theater_comedy_rounded),
  (35, 'Komedi', Icons.sentiment_very_satisfied_rounded),
  (80, 'Suç', Icons.gavel_rounded),
  (10765, 'Bilim Kurgu', Icons.rocket_launch_rounded),
  (9648, 'Gizem', Icons.search_rounded),
  (14, 'Fantastik', Icons.auto_fix_high_rounded),
  (10749, 'Romantik', Icons.favorite_rounded),
  (99, 'Belgesel', Icons.videocam_rounded),
  (10752, 'Savaş', Icons.military_tech_rounded),
  (10764, 'Reality', Icons.live_tv_rounded),
  (16, 'Animasyon', Icons.animation_rounded),
];

// ─── Main Screen ─────────────────────────────────────────────────────────────
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  // 0=film türleri, 1=dizi türleri, 2=fav filmler, 3=fav diziler, 4=değerlendirme
  int _step = 0;

  final Set<int> _selectedMovieGenres = {};
  final Set<int> _selectedTvGenres = {};
  final List<Movie> _favMovies = [];
  final List<Movie> _favTvShows = [];

  final _service = TmdbService();
  List<Movie> _items = [];
  int _current = 0;
  bool _loadingCards = false;
  bool _processing = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _toggleFavMovie(Movie m) {
    setState(() {
      final idx = _favMovies.indexWhere((f) => f.id == m.id);
      if (idx >= 0) {
        _favMovies.removeAt(idx);
      } else if (_favMovies.length < 3) {
        _favMovies.add(m);
      }
    });
  }

  void _toggleFavTv(Movie m) {
    setState(() {
      final idx = _favTvShows.indexWhere((f) => f.id == m.id);
      if (idx >= 0) {
        _favTvShows.removeAt(idx);
      } else if (_favTvShows.length < 3) {
        _favTvShows.add(m);
      }
    });
  }

  Future<void> _nextStep() async {
    if (_step == 0) {
      setState(() => _step = 1);
    } else if (_step == 1) {
      final all = {..._selectedMovieGenres, ..._selectedTvGenres};
      await PrefsService.saveInitialGenres(all.toList());
      if (!mounted) return;
      setState(() => _step = 2);
    } else if (_step == 2) {
      // Birleştir, üzerine yazma: kullanıcının mevcut Top 20'si (varsa) korunur.
      await PrefsService.mergeFavoriteMovies(_favMovies);
      ref.invalidate(topListProvider);
      if (!mounted) return;
      setState(() => _step = 3);
    } else if (_step == 3) {
      await PrefsService.mergeFavoriteTvShows(_favTvShows);
      ref.invalidate(topListProvider);
      final auth = ref.read(authProvider);
      if (auth.isLoggedIn) {
        unawaited(ref.read(syncProvider.notifier).performSync());
      }
      if (!mounted) return;
      setState(() {
        _step = 4;
        _loadingCards = true;
      });
      _loadCards();
    }
  }

  Future<void> _loadCards() async {
    try {
      final movieGenres = _selectedMovieGenres.toList();
      final tvGenres = _selectedTvGenres.toList();

      final results = await Future.wait([
        movieGenres.isNotEmpty
            ? _service.discoverByGenres(movieGenres, isTV: false)
            : _service.getPopular(isTV: false),
        tvGenres.isNotEmpty
            ? _service.discoverByGenres(tvGenres, isTV: true)
            : _service.getPopular(isTV: true),
      ]).timeout(const Duration(seconds: 15));

      var movies = results[0].take(8).toList();
      var shows = results[1].take(8).toList();

      if (movies.isEmpty) {
        movies = (await _service.getPopular(isTV: false)).take(8).toList();
      }
      if (shows.isEmpty) {
        shows = (await _service.getPopular(isTV: true)).take(8).toList();
      }

      final merged = <Movie>[];
      for (var i = 0; i < 8; i++) {
        if (i < movies.length) merged.add(movies[i]);
        if (i < shows.length) merged.add(shows[i]);
      }

      // Ağ tamamen başarısız oldu - değerlendirme adımını atla
      if (merged.isEmpty) {
        await PrefsService.setOnboardingDone();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
        return;
      }

      if (!mounted) return;
      setState(() {
        _items = merged.take(15).toList();
        _loadingCards = false;
      });
      _fadeCtrl.forward();
    } on Exception {
      if (!mounted) return;
      await PrefsService.setOnboardingDone();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  Future<void> _rate(int rating) async {
    if (_processing) return;
    _processing = true;
    try {
      final movie = _items[_current];
      await PrefsService.saveRating(movie: movie, rating: rating);
      if (_current + 1 >= _items.length) {
        await PrefsService.setOnboardingDone();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
        return;
      }
      if (!mounted) return;
      final disableAnims =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (disableAnims) {
        setState(() {
          _current++;
          _processing = false;
        });
        return;
      }
      await _fadeCtrl.reverse();
      if (!mounted) return;
      setState(() {
        _current++;
      });
      _fadeCtrl.forward();
    } finally {
      _processing = false;
    }
  }

  Future<void> _undo() async {
    if (_current == 0) return;
    final disableAnims =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnims) {
      if (mounted) setState(() => _current--);
      return;
    }
    await _fadeCtrl.reverse();
    if (!mounted) return;
    setState(() => _current--);
    _fadeCtrl.forward();
  }

  Future<void> _skipOnboarding() async {
    await PrefsService.skipOnboarding();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return GenreStep(
          key: const ValueKey(0),
          stepIndex: 0,
          title:
              AppLocalizations.of(
                context,
              )?.get('onboarding_title_movie_genres') ??
              '',
          subtitle:
              AppLocalizations.of(
                context,
              )?.get('onboarding_subtitle_movie_genres') ??
              '',
          genres: _movieGenres,
          selected: _selectedMovieGenres,
          onToggle: (id) => setState(
            () => _selectedMovieGenres.contains(id)
                ? _selectedMovieGenres.remove(id)
                : _selectedMovieGenres.add(id),
          ),
          onNext: _selectedMovieGenres.isNotEmpty ? _nextStep : null,
          onSkip: _skipOnboarding,
        );
      case 1:
        return GenreStep(
          key: const ValueKey(1),
          stepIndex: 1,
          title:
              AppLocalizations.of(context)?.get('onboarding_title_tv_genres') ??
              '',
          subtitle:
              AppLocalizations.of(
                context,
              )?.get('onboarding_subtitle_tv_genres') ??
              '',
          genres: _tvGenres,
          selected: _selectedTvGenres,
          onToggle: (id) => setState(
            () => _selectedTvGenres.contains(id)
                ? _selectedTvGenres.remove(id)
                : _selectedTvGenres.add(id),
          ),
          onNext: _selectedTvGenres.isNotEmpty ? _nextStep : null,
          onSkip: _skipOnboarding,
        );
      case 2:
        return FavoritePickStep(
          key: const ValueKey(2),
          stepIndex: 2,
          title:
              AppLocalizations.of(
                context,
              )?.get('onboarding_title_fav_movies') ??
              '',
          isTV: false,
          service: _service,
          selected: _favMovies,
          onToggle: _toggleFavMovie,
          onNext: _nextStep,
          onSkip: _skipOnboarding,
        );
      case 3:
        return FavoritePickStep(
          key: const ValueKey(3),
          stepIndex: 3,
          title:
              AppLocalizations.of(context)?.get('onboarding_title_fav_tvs') ??
              '',
          isTV: true,
          service: _service,
          selected: _favTvShows,
          onToggle: _toggleFavTv,
          onNext: _nextStep,
          onSkip: _skipOnboarding,
        );
      default:
        return KeyedSubtree(
          key: const ValueKey(4),
          child: _loadingCards || _items.isEmpty
              ? _loadingView()
              : _ratingView(),
        );
    }
  }

  Widget _loadingView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context)?.get('onboarding_loading') ?? '',
          style: TextStyle(color: context.c.dim, fontSize: 14),
        ),
      ],
    ),
  );

  Widget _ratingView() {
    final c = context.c;
    final movie = _items[_current];
    final progress = (_current + 1) / _items.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.get('onboarding_quick_rating') ??
                        '',
                    style: TextStyle(color: c.dim, fontSize: 13),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _skipOnboarding,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.glassFill,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        AppLocalizations.of(context)?.get('onboarding_skip') ??
                            '',
                        style: TextStyle(
                          color: c.dim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_current + 1} / ${_items.length}',
                    style: TextStyle(color: c.dim, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: c.surface,
                  color: Colors.white,
                  minHeight: 3,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: OnboardingMovieCard(movie: movie),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _undo,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surface,
                  ),
                  child: Icon(
                    Icons.undo_rounded,
                    color: _current > 0 ? Colors.white54 : Colors.white12,
                    size: 20,
                  ),
                ),
              ),
              OnboardingRatingBtn(
                label:
                    AppLocalizations.of(context)?.get('profile_berbat') ?? '',
                color: _rBerbat,
                size: 68,
                onTap: () => _rate(0),
              ),
              OnboardingRatingBtn(
                label: AppLocalizations.of(context)?.get('profile_eh') ?? '',
                color: _rEh,
                size: 80,
                onTap: () => _rate(1),
              ),
              OnboardingRatingBtn(
                label: AppLocalizations.of(context)?.get('profile_iyi') ?? '',
                color: _rIyi,
                size: 80,
                onTap: () => _rate(2),
              ),
              OnboardingRatingBtn(
                label:
                    AppLocalizations.of(context)?.get('profile_harika') ?? '',
                color: _rHarika,
                size: 68,
                onTap: () => _rate(3),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: GestureDetector(
            onTap: () => _rate(-1),
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                AppLocalizations.of(context)?.get('onboarding_not_watched') ??
                    '',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
