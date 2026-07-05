import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';

const _rBerbat = AppColors.rBerbat;
const _rEh = AppColors.rEh;
const _rIyi = AppColors.rIyi;
const _rHarika = AppColors.rHarika;

const _kTotalSteps = 5;

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
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
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
      setState(() => _step = 2);
    } else if (_step == 2) {
      await PrefsService.saveFavoriteMovies(_favMovies);
      setState(() => _step = 3);
    } else if (_step == 3) {
      await PrefsService.saveFavoriteTvShows(_favTvShows);
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
        return _GenreStep(
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
        return _GenreStep(
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
        return _FavoritePickStep(
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
        return _FavoritePickStep(
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
              child: _MovieCard(movie: movie),
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
              _RatingBtn(
                label:
                    AppLocalizations.of(context)?.get('profile_berbat') ?? '',
                color: _rBerbat,
                size: 68,
                onTap: () => _rate(0),
              ),
              _RatingBtn(
                label: AppLocalizations.of(context)?.get('profile_eh') ?? '',
                color: _rEh,
                size: 80,
                onTap: () => _rate(1),
              ),
              _RatingBtn(
                label: AppLocalizations.of(context)?.get('profile_iyi') ?? '',
                color: _rIyi,
                size: 80,
                onTap: () => _rate(2),
              ),
              _RatingBtn(
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

// ─── Step dots helper ─────────────────────────────────────────────────────────
Widget _buildDots(
  BuildContext context,
  int currentStep, {
  VoidCallback? onSkip,
}) {
  final c = context.c;
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: List.generate(_kTotalSteps, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < _kTotalSteps - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == currentStep ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == currentStep ? c.red : c.textFaint,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
      if (onSkip != null)
        GestureDetector(
          onTap: onSkip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.glassFill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              AppLocalizations.of(context)?.get('onboarding_skip') ?? '',
              style: TextStyle(
                color: c.dim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ],
  );
}

// ─── Continue button helper ───────────────────────────────────────────────────
Widget _buildContinueBtn(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
}) {
  final c = context.c;
  final enabled = onTap != null;
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: enabled ? LinearGradient(colors: [c.red, c.crimson]) : null,
        color: enabled ? null : c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? Colors.white : c.dim,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

// ─── Genre selection step ─────────────────────────────────────────────────────
class _GenreStep extends StatelessWidget {
  final int stepIndex;
  final String title;
  final String subtitle;
  final List<(int, String, IconData)> genres;
  final Set<int> selected;
  final void Function(int) onToggle;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;

  const _GenreStep({
    super.key,
    required this.stepIndex,
    required this.title,
    required this.subtitle,
    required this.genres,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDots(context, stepIndex, onSkip: onSkip),
              const SizedBox(height: 22),
              Text(
                title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(color: c.dim, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: genres.length,
            itemBuilder: (ctx, i) {
              final (id, _, icon) = genres[i];
              final name = PrefsService.genreName(id);
              final isSel = selected.contains(id);
              return GestureDetector(
                onTap: () => onToggle(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isSel ? c.red.withValues(alpha: 0.12) : c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSel ? c.red : c.textFaint,
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: isSel ? c.red : c.dim, size: 26),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: isSel ? c.ink : c.dim,
                          fontSize: 11.5,
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: _buildContinueBtn(
            context,
            label:
                AppLocalizations.of(context)?.get('onboarding_next') ?? 'Devam',
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}

// ─── Favourite pick step ──────────────────────────────────────────────────────
class _FavoritePickStep extends StatefulWidget {
  final int stepIndex;
  final String title;
  final bool isTV;
  final TmdbService service;
  final List<Movie> selected;
  final void Function(Movie) onToggle;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  const _FavoritePickStep({
    super.key,
    required this.stepIndex,
    required this.title,
    required this.isTV,
    required this.service,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    this.onSkip,
  });

  @override
  State<_FavoritePickStep> createState() => _FavoritePickStepState();
}

class _FavoritePickStepState extends State<_FavoritePickStep> {
  final _ctrl = TextEditingController();
  List<Movie> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    setState(() {}); // suffix icon
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final all = await widget.service.searchMulti(query);
      final res = all.where((m) => m.isTV == widget.isTV).toList();
      if (!mounted) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final canAdd = widget.selected.length < 3;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDots(context, widget.stepIndex, onSkip: widget.onSkip),
              const SizedBox(height: 22),
              Text(
                widget.title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppLocalizations.of(context)?.get('onboarding_fav_desc') ?? '',
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Search box
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: TextField(
                  controller: _ctrl,
                  onChanged: _onSearch,
                  style: TextStyle(color: c.ink, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: widget.isTV
                        ? (AppLocalizations.of(
                                context,
                              )?.get('onboarding_search_hint_tv') ??
                              '')
                        : (AppLocalizations.of(
                                context,
                              )?.get('onboarding_search_hint_movie') ??
                              ''),
                    hintStyle: TextStyle(color: c.dim),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: c.dim,
                      size: 20,
                    ),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _ctrl.clear();
                              setState(() {
                                _results = [];
                                _searching = false;
                              });
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: c.dim,
                              size: 18,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Selected chips
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.selected.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final m = widget.selected[i];
                  return GestureDetector(
                    onTap: () => widget.onToggle(m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.red, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              m.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.close_rounded, color: c.red, size: 13),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Results / empty state
        Expanded(
          child: _searching
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white38,
                    ),
                  ),
                )
              : _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _ctrl.text.isEmpty
                          ? (widget.isTV
                                ? (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_search_empty_tv') ??
                                      '')
                                : (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_search_empty_movie') ??
                                      ''))
                          : (AppLocalizations.of(
                                  context,
                                )?.get('search_no_results') ??
                                ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.dim, fontSize: 14, height: 1.6),
                    ),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final m = _results[i];
                    final sel = widget.selected.any((s) => s.id == m.id);
                    final disabled = !sel && !canAdd;
                    return Semantics(
                      label:
                          '${m.title}${m.year.isNotEmpty ? ", ${m.year}" : ""}',
                      button: true,
                      selected: sel,
                      enabled: !disabled,
                      child: GestureDetector(
                        onTap: disabled
                            ? null
                            : () {
                                final willSelect = !sel;
                                widget.onToggle(m);
                                if (willSelect) {
                                  _ctrl.clear();
                                  setState(() {
                                    _results = [];
                                    _searching = false;
                                  });
                                }
                              },
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: disabled ? 0.3 : 1.0,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? c.red.withValues(alpha: 0.1)
                                  : c.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? c.red : c.border,
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(9),
                                  ),
                                  child: m.posterUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: m.posterUrl,
                                          width: 44,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              _posterPlaceholder(context),
                                          errorWidget: (context, url, error) =>
                                              _posterPlaceholder(context),
                                        )
                                      : _posterPlaceholder(context),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.ink,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (m.year.isNotEmpty)
                                        Text(
                                          m.year,
                                          style: TextStyle(
                                            color: c.dim,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Icon(
                                    sel
                                        ? Icons.check_circle_rounded
                                        : Icons.add_circle_outline_rounded,
                                    color: sel ? c.red : c.dim,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Continue button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: _buildContinueBtn(
            context,
            label: AppLocalizations.of(context)?.get('onboarding_next') ?? '',
            onTap: widget.onNext,
          ),
        ),
      ],
    );
  }

  Widget _posterPlaceholder(BuildContext context) {
    final c = context.c;
    return Container(
      width: 44,
      height: 64,
      color: c.surface,
      child: Center(child: Icon(Icons.movie_rounded, color: c.dim, size: 18)),
    );
  }
}

// ─── Movie card (rating step) ─────────────────────────────────────────────────
class _MovieCard extends StatelessWidget {
  final Movie movie;
  const _MovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                movie.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _placeholder(c),
                        errorWidget: (context, url, error) => _placeholder(c),
                      )
                    : _placeholder(c),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      movie.isTV
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_tv') ??
                                '')
                          : (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_movie') ??
                                ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (movie.year.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('(${movie.year})', style: TextStyle(color: c.dim, fontSize: 14)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _placeholder(ThemePalette c) => Container(
    color: c.surface,
    child: Center(child: Icon(Icons.movie_rounded, color: c.dim, size: 48)),
  );
}

// ─── Rating button ────────────────────────────────────────────────────────────
class _RatingBtn extends StatelessWidget {
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _RatingBtn({
    required this.label,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: size > 72 ? 13 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
