import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../models/social.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import 'movie_detail_sheet.dart';
import 'match/similar_card.dart';
import 'results_screen.dart';
import 'social_screen.dart';
import 'login_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';

// ─── Tür listesi (Birlikte modu için) ────────────────────────────────────────
const _togetherGenres = [
  (28, 'Aksiyon'),
  (35, 'Komedi'),
  (18, 'Drama'),
  (27, 'Korku'),
  (878, 'Sci-Fi'),
  (53, 'Gerilim'),
  (10749, 'Romantik'),
  (14, 'Fantastik'),
  (80, 'Suç'),
  (99, 'Belgesel'),
  (12, 'Macera'),
  (16, 'Animasyon'),
];

class MatchScreen extends ConsumerStatefulWidget {
  /// Kart-tabanlı açılışta doğrudan başlanacak mod (0: Film, 1: Couch, 2: Arkadaş).
  final int initialMode;

  /// Dashboard kartından açıldığında iç mod seçici gizlenir (çift-navigasyon önlenir).
  final bool hideModeSelector;

  final bool isActive;

  const MatchScreen({
    super.key,
    this.initialMode = 0,
    this.hideModeSelector = false,
    this.isActive = true,
  });

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  TmdbService get _service => ref.read(tmdbServiceProvider);
  final _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _matchMode = widget.initialMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(syncServiceProvider).sync().catchError((_) {});
        ref.read(socialProvider.notifier).loadFriends();
      }
    });
  }

  // ── Eşleştir modu ─────────────────────────────────────────────────────────
  List<Movie> _searchResults = [];
  bool _searching = false;
  Movie? _selected;
  List<Movie> _similar = [];
  bool _loadingSimilar = false;

  // ── Birlikte modu ─────────────────────────────────────────────────────────
  int _matchMode = 0; // 0: Movie Match, 1: Together, 2: Friend
  Friend? _selectedFriend;
  final Set<int> _p1 = {};
  final Set<int> _p2 = {};
  int _activePerson = 1; // 1 veya 2

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // ── Eşleştir: arama ───────────────────────────────────────────────────────
  void _search(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await _service.searchMulti(q);
        if (!mounted) return;
        setState(() {
          _searchResults = results.take(8).toList();
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      }
    });
  }

  Future<void> _selectMovie(Movie movie) async {
    _ctrl.text = movie.title;
    setState(() {
      _selected = movie;
      _searchResults = [];
      _loadingSimilar = true;
      _similar = [];
    });

    try {
      // Üç aday kaynağı: recommendations (davranışsal, birlikte izlenme),
      // similar (metadata) ve tür-bazlı discover — birleşimi recall'u genişletir.
      final results = await Future.wait([
        _service.getRecommendations(movie.id, isTV: movie.isTV),
        _service.getSimilar(movie.id, isTV: movie.isTV),
        _service.discoverForMatch(movie.genreIds, isTV: movie.isTV),
        PrefsService.getRatedIds(),
      ]);

      final recommended = results[0] as List<Movie>;
      final similar = results[1] as List<Movie>;
      final discovered = results[2] as List<Movie>;
      final ratedKeys = results[3] as Set<String>;

      final movieKey = "${movie.isTV ? 'tv' : 'movie'}_${movie.id}";
      final coVisitKeys = recommended
          .map((m) => "${m.isTV ? 'tv' : 'movie'}_${m.id}")
          .toSet();

      // Sıralama artık ham TMDB puanı değil, anchor'a gerçek benzerlik:
      // keyword örtüşmesi + tür + co-visitation + kalite harmanı.
      final ranked = await ref
          .read(recommendationEngineProvider)
          .rankSimilarTo(
            movie,
            candidates: [...recommended, ...similar, ...discovered],
            excludedKeys: {movieKey, ...ratedKeys},
            coVisitKeys: coVisitKeys,
          );

      // Kademeli kalite gevşetme: boş grid göstermektense eşiği düşür.
      var filtered = ranked.where((m) => m.voteAverage >= 6.0).toList();
      if (filtered.length < 10) {
        filtered = ranked.where((m) => m.voteAverage >= 5.0).toList();
      }
      if (filtered.length < 10) filtered = ranked;

      if (!mounted) return;
      setState(() {
        _similar = filtered.take(20).toList();
        _loadingSimilar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _similar = [];
        _loadingSimilar = false;
      });
    }
  }

  // ── Birlikte: tür toggle ───────────────────────────────────────────────────
  void _toggleGenre(int id) {
    setState(() {
      final set = _activePerson == 1 ? _p1 : _p2;
      if (set.contains(id)) {
        set.remove(id);
      } else {
        set.add(id);
      }
    });
  }

  void _findTogether() {
    if (_p1.isEmpty || _p2.isEmpty) return;

    final intersection = _p1.intersection(_p2);
    if (intersection.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) {
          final c = context.c;
          return AlertDialog(
            backgroundColor: c.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              AppLocalizations.of(context)?.get('no_common_genres') ??
                  'No Common Genres',
              style: TextStyle(
                color: c.ink,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.get('you_have_no_common_genres_sele') ??
                  'You have no common genres selected. Please select at least one genre in common to find a joint recommendation.',
              style: TextStyle(color: c.dim, fontSize: 14, height: 1.45),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  AppLocalizations.of(context)?.get('ok') ?? 'OK',
                  style: TextStyle(color: c.gold, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    final genres = intersection.toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          genreStr: genres.join(','),
          sortBy: 'vote_average.desc',
          jointGenres: genres,
        ),
      ),
    );
  }

  void _resetTogether() {
    setState(() {
      _p1.clear();
      _p2.clear();
      _activePerson = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated &&
          next.isAuthenticated) {
        ref.read(syncServiceProvider).sync().catchError((_) {});
        ref.read(socialProvider.notifier).loadFriends();
      }
    });

    final c = context.c;

    return Scaffold(
      backgroundColor: c.bg,
      body: CinematicBackground(
        animate: widget.isActive,
        child: SafeArea(
          child: Column(
            children: [
              // ── Başlık + mod toggle ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (Navigator.of(context).canPop()) ...[
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).pop();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: c.ink,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                        Expanded(
                          child: Text(
                            switch (_matchMode) {
                              0 =>
                                (AppLocalizations.of(
                                      context,
                                    )?.get('movie_match') ??
                                    'Movie Match'),
                              1 =>
                                (AppLocalizations.of(
                                      context,
                                    )?.get('together_couch_title') ??
                                    'Couch Mode'),
                              _ =>
                                (AppLocalizations.of(
                                      context,
                                    )?.get('together_friend_match_title') ??
                                    'Friend Match'),
                            },
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!widget.hideModeSelector) ...[
                      const SizedBox(height: 12),
                      // Sliding Segmented Tab Controller
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final indicatorWidth = (width - 8) / 3;
                          return Container(
                            height: 40,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.borderSoft),
                            ),
                            child: Stack(
                              children: [
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOutCubic,
                                  left: _matchMode * indicatorWidth,
                                  top: 0,
                                  bottom: 0,
                                  width: indicatorWidth,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: CinemaGradients.crimson,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: CinemaShadows.glow(
                                        c.red,
                                        strength: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _segmentedTab(
                                        0,
                                        Icons.compare_arrows_rounded,
                                        AppLocalizations.of(
                                              context,
                                            )?.get('movie_match_alt') ??
                                            'Movie Match',
                                        c,
                                      ),
                                    ),
                                    Expanded(
                                      child: _segmentedTab(
                                        1,
                                        Icons.people_rounded,
                                        AppLocalizations.of(
                                              context,
                                            )?.get('together_couch_title') ??
                                            'Couch Mode',
                                        c,
                                      ),
                                    ),
                                    Expanded(
                                      child: _segmentedTab(
                                        2,
                                        Icons.group_add_rounded,
                                        AppLocalizations.of(
                                              context,
                                            )?.get('with_friend') ??
                                            'With Friend',
                                        c,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              // ── İçerik ─────────────────────────────────────────────────────
              Expanded(
                child: switch (_matchMode) {
                  0 => _matchBody(),
                  1 => _togetherBody(),
                  _ => _friendBody(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // EŞLEŞTİR MODU
  // ────────────────────────────────────────────────────────────────────────────

  Widget _matchBody() {
    final c = context.c;
    return Column(
      children: [
        if (_selected == null && _searchResults.isEmpty && !_searching)
          _buildIntroBanner(
            c,
            Icons.movie_filter_rounded,
            AppLocalizations.of(context)?.get('movie_matcher') ??
                'Movie Matcher',
            AppLocalizations.of(
                  context,
                )?.get('search_for_a_movie_or_tv_show_') ??
                'Search for a movie or TV show you like, we\'ll analyze its similarities to recommend matching titles.',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: c.isLight ? Border.all(color: c.border, width: 1) : null,
            ),
            child: TextField(
              controller: _ctrl,
              onChanged: _search,
              style: TextStyle(color: c.ink, fontSize: 15),
              decoration: InputDecoration(
                hintText:
                    AppLocalizations.of(context)?.get('search_hint') ??
                    'Film veya dizi ara...',
                hintStyle: TextStyle(color: c.dim, fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded, color: c.dim, size: 20),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _ctrl.clear();
                          setState(() {
                            _searchResults = [];
                            _selected = null;
                            _similar = [];
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
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        Expanded(child: _matchContent()),
      ],
    );
  }

  Widget _matchContent() {
    if (_searching) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.c.dim,
          ),
        ),
      );
    }
    if (_searchResults.isNotEmpty) return _searchList();
    if (_selected != null) return _similarGrid();
    return _matchEmptyHint();
  }

  Widget _matchEmptyHint() {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface),
            child: Icon(
              Icons.compare_arrows_rounded,
              color: c.textFaint,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.get('match_search_placeholder') ??
                'Search a movie or TV show',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)?.get('match_empty_title') ??
                'Find similar titles to what you love instantly',
            style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _searchList() => ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    itemCount: _searchResults.length,
    itemBuilder: (ctx, i) {
      final c = ctx.c;
      final m = _searchResults[i];
      return GestureDetector(
        onTap: () => _selectMovie(m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 44,
                  height: 64,
                  child: m.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: m.posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (ctx, url) =>
                              ColoredBox(color: c.border),
                          errorWidget: (ctx, url, err) =>
                              ColoredBox(color: c.border),
                        )
                      : ColoredBox(color: c.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (m.isTV ? c.blue : c.red).withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            m.isTV
                                ? (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_tv') ??
                                      'Dizi')
                                : (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_movie') ??
                                      'Film'),
                            style: TextStyle(
                              color: m.isTV ? c.blue : c.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (m.year.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            m.year,
                            style: TextStyle(color: c.dim, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.dim, size: 20),
            ],
          ),
        ),
      );
    },
  );

  Widget _similarGrid() {
    final c = context.c;
    if (_loadingSimilar) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.dim),
        ),
      );
    }
    if (_similar.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.get('match_no_similar') ??
              'No similar content found',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Builder(
            builder: (context) {
              final template =
                  AppLocalizations.of(context)?.get('match_similar_to') ??
                  'Similar to "{}"';
              final titleIndex = template.indexOf('{}');
              if (titleIndex == -1) {
                return Text(
                  'Similar to "${_selected!.title}"',
                  style: TextStyle(color: c.dim, fontSize: 14),
                );
              }
              final prefix = template.substring(0, titleIndex);
              final suffix = template.substring(titleIndex + 2);
              return RichText(
                text: TextSpan(
                  children: [
                    if (prefix.isNotEmpty)
                      TextSpan(
                        text: prefix,
                        style: TextStyle(color: c.dim, fontSize: 14),
                      ),
                    TextSpan(
                      text: _selected!.title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (suffix.isNotEmpty)
                      TextSpan(
                        text: suffix,
                        style: TextStyle(color: c.dim, fontSize: 14),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.62,
            ),
            itemCount: _similar.length,
            itemBuilder: (ctx, i) => SimilarCard(
              movie: _similar[i],
              onTap: () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) =>
                    MovieDetailSheet(movie: _similar[i], service: _service),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BİRLİKTE MODU
  // ────────────────────────────────────────────────────────────────────────────

  Widget _togetherBody() {
    final c = context.c;
    final canFind = _p1.isNotEmpty && _p2.isNotEmpty;

    return Column(
      children: [
        _buildIntroBanner(
          c,
          Icons.people_rounded,
          AppLocalizations.of(context)?.get('couch_mode_matcher') ??
              'Couch Mode Matcher',
          AppLocalizations.of(context)?.get('pass_the_phone_to_the_person_n') ??
              'Pass the phone to the person next to you. Both select your favorite genres, and we\'ll discover matches you\'ll both enjoy.',
        ),

        // ── Kişi seçici ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Builder(
            builder: (context) {
              return Row(
                children: [
                  Expanded(
                    child: _personTab(
                      1,
                      AppLocalizations.of(context)?.get('match_you') ?? 'You',
                      _p1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _personTab(
                      2,
                      AppLocalizations.of(context)?.get('match_friend') ??
                          'Friend',
                      _p2,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Sıra Yönlendirmesi
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _activePerson == 1
                  ? (AppLocalizations.of(
                          context,
                        )?.get('player_1_you_select_your_favor') ??
                        '👉 Player 1 (You): Select your favorite genres...')
                  : (AppLocalizations.of(
                          context,
                        )?.get('player_2_friend_now_its_your_t') ??
                        '👉 Player 2 (Friend): Now it\'s your turn...'),
              key: ValueKey<int>(_activePerson),
              style: TextStyle(
                color: _activePerson == 1 ? c.red : c.blue,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Renk Lejantı
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(
                c.red,
                AppLocalizations.of(context)?.get('match_you') ?? 'You',
              ),
              const SizedBox(width: 14),
              _legendItem(
                c.blue,
                AppLocalizations.of(context)?.get('match_friend') ?? 'Friend',
              ),
              const SizedBox(width: 14),
              _legendItem(
                Colors.purple,
                AppLocalizations.of(context)?.get('common_match') ??
                    'Common Match',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Seçili türler ──────────────────────────────────────────────────
        if (_p1.isNotEmpty || _p2.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _selectedChips(),
          ),
        ],

        // ── Tür grid ───────────────────────────────────────────────────────
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.2,
            ),
            itemCount: _togetherGenres.length,
            itemBuilder: (ctx, i) {
              final c = ctx.c;
              final (id, _) = _togetherGenres[i];
              final name = PrefsService.genreName(id);
              final inP1 = _p1.contains(id);
              final inP2 = _p2.contains(id);
              final inActive = _activePerson == 1 ? inP1 : inP2;

              Color borderColor = c.border;
              Color bgColor = c.card;
              if (inP1 && inP2) {
                borderColor = Colors.purple;
                bgColor = Colors.purple.withValues(alpha: 0.12);
              } else if (inP1) {
                borderColor = c.red;
                bgColor = c.red.withValues(alpha: 0.10);
              } else if (inP2) {
                borderColor = c.blue;
                bgColor = c.blue.withValues(alpha: 0.10);
              }

              return GestureDetector(
                onTap: () => _toggleGenre(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: inActive ? borderColor : c.border,
                      width: inActive ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (inP1)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.red,
                          ),
                        ),
                      if (inP1 && inP2) const SizedBox(width: 3),
                      if (inP2)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.blue,
                          ),
                        ),
                      if (inP1 || inP2) const SizedBox(width: 5),
                      Text(
                        name,
                        style: TextStyle(
                          color: (inP1 || inP2) ? c.ink : c.dim,
                          fontSize: 12,
                          fontWeight: (inP1 || inP2)
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ── Bul / Sıfırla butonları ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              if (_p1.isNotEmpty || _p2.isNotEmpty) ...[
                Semantics(
                  label:
                      AppLocalizations.of(context)?.get('semantics_reset') ??
                      'Seçimleri sıfırla',
                  button: true,
                  child: GestureDetector(
                    onTap: _resetTogether,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: context.c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.c.border, width: 1),
                      ),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: context.c.dim,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: canFind ? _findTogether : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: canFind
                          ? const LinearGradient(
                              colors: [Color(0xFFE94560), Color(0xFFB83050)],
                            )
                          : null,
                      color: canFind ? null : context.c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Builder(
                      builder: (context) {
                        return Text(
                          canFind
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('match_find_suggestions') ??
                                    'Find Common Suggestions')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('match_select_at_least_one') ??
                                    'Both choose at least 1 genre'),
                          style: TextStyle(
                            color: canFind ? Colors.white : context.c.textFaint,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _personTab(int person, String label, Set<int> genres) {
    final c = context.c;
    final isActive = _activePerson == person;
    final color = person == 1 ? c.red : c.blue;
    return GestureDetector(
      onTap: () => setState(() => _activePerson = person),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color : c.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              person == 1 ? Icons.person_rounded : Icons.person_outline_rounded,
              color: isActive ? color : c.dim,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? c.ink : c.dim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 2),
              Builder(
                builder: (context) {
                  return Text(
                    AppLocalizations.of(context)
                            ?.get('match_genres_count')
                            .replaceAll('{}', genres.length.toString()) ??
                        '${genres.length} genres',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectedChips() {
    final intersection = _p1.intersection(_p2);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final id in _p1)
          _chip(
            id,
            context.c.red,
            icon: intersection.contains(id) ? Icons.favorite_rounded : null,
          ),
        for (final id in _p2.difference(_p1)) _chip(id, context.c.blue),
      ],
    );
  }

  Widget _chip(int id, Color color, {IconData? icon}) {
    final name = PrefsService.genreName(id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 10),
            const SizedBox(width: 4),
          ],
          Text(
            name,
            style: TextStyle(
              color: context.c.ink,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedTab(int mode, IconData icon, String label, ThemePalette c) {
    final active = _matchMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _matchMode = mode;
          _ctrl.clear();
          _searchResults = [];
          _selected = null;
          _similar = [];
          _resetTogether();
          _selectedFriend = null;
        });
        if (mode == 2) {
          ref.read(socialProvider.notifier).loadFriends();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : c.dim, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : c.dim,
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroBanner(
    ThemePalette c,
    IconData icon,
    String title,
    String desc,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.borderSoft),
        boxShadow: CinemaShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.red.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: c.red, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(color: c.dim, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: c.dim,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _friendBody() {
    final c = context.c;

    // Check authentication
    final authState = ref.watch(authProvider);
    if (!authState.isAuthenticated) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                ),
                child: Icon(Icons.lock_outline_rounded, color: c.red, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)?.get('authentication_required') ??
                    'Authentication Required',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                      context,
                    )?.get('please_sign_in_to_view_watchli') ??
                    'Please sign in to view watchlist intersections with your friends.',
                style: TextStyle(color: c.dim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)?.get('auth_title_login') ??
                      'Sign In',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final socialState = ref.watch(socialProvider);

    // If friend is not selected, display friend list
    if (_selectedFriend == null) {
      if (socialState.loading) {
        return Center(child: CircularProgressIndicator(color: c.gold));
      }
      final friends = socialState.friends;
      if (friends.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surface,
                  ),
                  child: Icon(
                    Icons.people_alt_rounded,
                    color: c.gold,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)?.get('no_friends_yet') ??
                      'No Friends Yet',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(
                        context,
                      )?.get('you_must_add_friends_first_to_') ??
                      'You must add friends first to match with them.',
                  style: TextStyle(color: c.dim, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SocialScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.get('add_manage_friends') ??
                        'Add / Manage Friends',
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIntroBanner(
            c,
            Icons.group_add_rounded,
            AppLocalizations.of(context)?.get('online_friend_match') ??
                'Online Friend Match',
            AppLocalizations.of(
                  context,
                )?.get('select_a_friend_to_find_common') ??
                'Select a friend to find common titles in your watchlists and get joint recommendations based on your shared interests.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.get('select_a_friend_to_match_with') ??
                        'Select a friend to match with:',
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SocialScreen(initialTab: 0),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.manage_accounts_rounded,
                        color: c.red,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)?.get('manage') ?? 'Manage',
                        style: TextStyle(
                          color: c.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: friends.length,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (context, idx) {
                final f = friends[idx];
                final name = f.displayName ?? f.username;
                final handle = f.username;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.borderSoft),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: c.border,
                      foregroundColor: c.ink,
                      child: Text(name[0].toUpperCase()),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: handle.isNotEmpty
                        ? Text(
                            '@$handle',
                            style: TextStyle(color: c.dim, fontSize: 12),
                          )
                        : null,
                    trailing: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: c.dim,
                      size: 14,
                    ),
                    onTap: () async {
                      setState(() {
                        _selectedFriend = f;
                      });
                      final auth = ref.read(authProvider);
                      if (auth.isAuthenticated) {
                        try {
                          await ref.read(syncServiceProvider).sync();
                        } catch (e, st) {
                          debugPrint("Sync failed on friend select: $e\n$st");
                        }
                      }
                      final id = f.id;
                      ref
                          .read(socialProvider.notifier)
                          .loadWatchlistIntersection(id);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    // A friend is selected! Display watchlist intersection
    final friendName =
        _selectedFriend!.displayName ??
        _selectedFriend!.username;
    final intersection = socialState.intersection;

    return Column(
      children: [
        // Friend Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                onPressed: () => setState(() => _selectedFriend = null),
              ),
              CircleAvatar(
                radius: 16,
                backgroundColor: c.border,
                foregroundColor: c.ink,
                child: Text(
                  friendName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  friendName,
                  style: TextStyle(
                    color: c.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: socialState.loading
              ? Center(child: CircularProgressIndicator(color: c.gold))
              : socialState.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: c.red,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          socialState.error!,
                          style: TextStyle(
                            color: c.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : intersection.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('no_common_movies') ??
                              'No Common Movies',
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('neither_of_you_have_added_the_') ??
                              'Neither of you have added the same movies to your watchlists.',
                          style: TextStyle(color: c.dim, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Text(
                        AppLocalizations.of(context)
                                ?.get('your_common_watchlist_intersec')
                                .replaceAll('{}', '${intersection.length}') ??
                            'Your Common Watchlist (${intersection.length} Titles)',
                        style: TextStyle(
                          color: c.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2 / 3.4,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: intersection.length,
                        itemBuilder: (context, idx) {
                          final m = intersection[idx];
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              final service = ref.read(tmdbServiceProvider);
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) => MovieDetailSheet(
                                  movie: m,
                                  service: service,
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: m.posterUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: m.posterUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (ctx, url) =>
                                                ColoredBox(color: c.card),
                                            errorWidget: (ctx, url, err) =>
                                                ColoredBox(color: c.card),
                                          )
                                        : ColoredBox(color: c.card),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.ink,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Joint Recommendations Button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: () {
                          // Collect unique genre IDs
                          final genres = intersection
                              .expand((m) => m.genreIds)
                              .toSet()
                              .toList();

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultsScreen(
                                genreStr: genres.isNotEmpty
                                    ? genres.join(',')
                                    : null,
                                sortBy: 'vote_average.desc',
                                jointGenres: genres,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          AppLocalizations.of(
                                context,
                              )?.get('find_joint_recommendations') ??
                              'Find Joint Recommendations',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
