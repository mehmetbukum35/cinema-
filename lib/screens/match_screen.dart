import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'results_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import 'match/match_widgets.dart';
import 'match/match_movie_body.dart';
import 'match/match_together_body.dart';
import 'match/match_friend_body.dart';

/// Eşleştir orkestratörü: mod seçimi, arama/benzerlik mantığı ve
/// couch/arkadaş akışları burada; sunum parçaları match/ altında yaşar.
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

  List<Movie> _searchResults = [];
  bool _searching = false;
  Movie? _selected;
  List<Movie> _similar = [];
  bool _loadingSimilar = false;

  int _matchMode = 0;
  Friend? _selectedFriend;
  final Set<int> _p1 = {};
  final Set<int> _p2 = {};
  int _activePerson = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

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

      final ranked = await ref.read(recommendationEngineProvider).rankSimilarTo(
            movie,
            candidates: [...recommended, ...similar, ...discovered],
            excludedKeys: {movieKey, ...ratedKeys},
            coVisitKeys: coVisitKeys,
          );

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

  void _clearSearch() {
    _ctrl.clear();
    setState(() {
      _searchResults = [];
      _selected = null;
      _similar = [];
    });
  }

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
              AppLocalizations.of(context)
                      ?.get('you_have_no_common_genres_sele') ??
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

  void _onModeChanged(int mode) {
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
  }

  Future<void> _onSelectFriend(Friend friend) async {
    setState(() => _selectedFriend = friend);
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      try {
        await ref.read(syncServiceProvider).sync();
      } catch (e, st) {
        debugPrint("Sync failed on friend select: $e\n$st");
      }
    }
    ref.read(socialProvider.notifier).loadWatchlistIntersection(friend.id);
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
                                (AppLocalizations.of(context)
                                        ?.get('movie_match') ??
                                    'Movie Match'),
                              1 =>
                                (AppLocalizations.of(context)
                                        ?.get('together_couch_title') ??
                                    'Couch Mode'),
                              _ =>
                                (AppLocalizations.of(context)
                                        ?.get('together_friend_match_title') ??
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
                      MatchModeSelector(
                        matchMode: _matchMode,
                        onModeChanged: _onModeChanged,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: switch (_matchMode) {
                  0 => MatchMovieBody(
                      searchController: _ctrl,
                      onSearch: _search,
                      onClear: _clearSearch,
                      searchResults: _searchResults,
                      searching: _searching,
                      selected: _selected,
                      similar: _similar,
                      loadingSimilar: _loadingSimilar,
                      onSelectMovie: _selectMovie,
                      service: _service,
                      onSimilarTap: (movie) => showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => MovieDetailSheet(
                          movie: movie,
                          service: _service,
                        ),
                      ),
                    ),
                  1 => MatchTogetherBody(
                      p1: _p1,
                      p2: _p2,
                      activePerson: _activePerson,
                      onPersonChanged: (p) =>
                          setState(() => _activePerson = p),
                      onToggleGenre: _toggleGenre,
                      onFind: _findTogether,
                      onReset: _resetTogether,
                    ),
                  _ => MatchFriendBody(
                      selectedFriend: _selectedFriend,
                      onSelectFriend: _onSelectFriend,
                      onDeselectFriend: () =>
                          setState(() => _selectedFriend = null),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
