import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'movie_detail/recommend_sheet.dart';
import 'movie_detail/review_item.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../models/cast_member.dart';
import '../models/watch_provider.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import 'results_screen.dart';
import 'person_screen.dart';
import '../models/review.dart';
import '../providers/watchlist_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../services/providers.dart';
import 'trailer_player_screen.dart';
import '../widgets/spring_button.dart';

class MovieDetailSheet extends ConsumerStatefulWidget {
  final Movie movie;
  final TmdbService service;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.service,
  });

  /// "Arkadaşına Öner" akışı: arkadaş seçici alt sayfa açar, seçilince
  /// öneriyi backend'e gönderir (arkadaş push bildirimi alır).
  static Future<void> showRecommendSheet({
    required BuildContext context,
    required WidgetRef ref,
    required Movie movie,
  }) async {
    final tr = AppLocalizations.of(context);
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('recommend_need_login') ??
                'Öneri göndermek için giriş yapmalısın.',
          ),
        ),
      );
      return;
    }

    // Arkadaş listesi henüz yüklenmediyse çek.
    if (ref.read(socialProvider).friends.isEmpty) {
      await ref.read(socialProvider.notifier).loadFriends();
    }
    if (!context.mounted) return;

    final friends = ref.read(socialProvider).friends;
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('recommend_no_friends') ??
                'Önce Sosyal sekmesinden arkadaş eklemelisin.',
          ),
        ),
      );
      return;
    }

    final c = context.c;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RecommendSheet(
        movie: movie,
        friends: friends,
        ref: ref,
        parentContext: context,
      ),
    );
  }

  static void confirmBlockMovie({
    required BuildContext context,
    required WidgetRef ref,
    required Movie movie,
    required VoidCallback onBlocked,
  }) {
    final c = context.c;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppLocalizations.of(context)?.get('hide_title') ?? 'Hide Title',
          style: TextStyle(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)?.get('are_you_sure_you_want_to_block') ??
              'Are you sure you want to block this title and permanently hide it from all lists?',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Cancel',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog

              await PrefsService.blockMovie(movie.id, movie.isTV);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(
                            context,
                          )?.get('title_hidden_and_removed_from_') ??
                          'Title hidden and removed from lists.',
                    ),
                    backgroundColor: c.green,
                  ),
                );
              }

              ref.invalidate(watchlistProvider);
              ref.invalidate(statsProvider);
              onBlocked();
            },
            child: Text(
              AppLocalizations.of(context)?.get('hide') ?? 'Hide',
              style: TextStyle(color: c.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  ConsumerState<MovieDetailSheet> createState() => _MovieDetailSheetState();
}

class _MovieDetailSheetState extends ConsumerState<MovieDetailSheet> {
  String? _trailerKey;
  List<WatchProvider> _providers = [];
  List<CastMember> _cast = [];
  List<Movie> _similar = [];
  Map<String, dynamic>? _details;
  List<Review> _reviews = [];
  List<String> _keywords = [];
  List<Movie> _collection = [];
  Set<int> _watchedSeasons = {};
  bool _extrasLoaded = false;
  int? _currentRating;
  final TextEditingController _commentController = TextEditingController();
  bool _isSpoiler = false;
  bool _isPrivate = false;
  List<dynamic> _friendsReviews = [];
  List<dynamic> _communityReviews = [];
  bool _loadingFriendsReviews = false;
  bool _justSavedComment = false;
  Map<String, dynamic>? _communityScore;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final id = widget.movie.id;
    final isTV = widget.movie.isTV;

    Future<T> runSafe<T>(Future<T> future, T defaultValue) async {
      try {
        return await future;
      } catch (e, st) {
        debugPrint('Error loading detail item: $e\n$st');
        return defaultValue;
      }
    }

    // Phase 1: Load critical information needed for the upper fold immediately
    final primaryResults = await Future.wait([
      runSafe(widget.service.getFullDetails(id, isTV: isTV), null),
      runSafe(widget.service.getTrailerKey(id, isTV: isTV), null),
      runSafe(PrefsService.getRating(id, isTV), null),
      runSafe(PrefsService.getWatchedSeasons(id), <int>{}),
    ]);

    if (!mounted) return;

    final details = primaryResults[0] as Map<String, dynamic>?;
    final ratingData = primaryResults[2] as Map<String, dynamic>?;

    setState(() {
      _details = details;
      _trailerKey = primaryResults[1] as String?;
      _currentRating = ratingData?['rating'] as int?;
      _commentController.text = ratingData?['comment'] as String? ?? '';
      _isSpoiler = (ratingData?['is_spoiler'] ?? 0) == 1;
      _isPrivate = (ratingData?['is_private'] ?? 0) == 1;
      _watchedSeasons = primaryResults[3] as Set<int>;
    });

    _loadFriendsReviews();
    _loadCommunityScore();

    // Phase 2: Load secondary details asynchronously in the background
    Future.wait([
      runSafe(
        widget.service.getWatchProviders(id, isTV: isTV),
        <WatchProvider>[],
      ),
      runSafe(widget.service.getCredits(id, isTV: isTV), <CastMember>[]),
      runSafe(widget.service.getSimilar(id, isTV: isTV), <Movie>[]),
      runSafe(widget.service.getReviews(id, isTV: isTV), <Review>[]),
      runSafe(widget.service.getKeywords(id, isTV: isTV), <String>[]),
    ]).then((secondaryResults) async {
      if (!mounted) return;

      setState(() {
        _providers = secondaryResults[0] as List<WatchProvider>;
        _cast = secondaryResults[1] as List<CastMember>;
        _similar = (secondaryResults[2] as List<Movie>).take(10).toList();
        _reviews = secondaryResults[3] as List<Review>;
        _keywords = secondaryResults[4] as List<String>;
        _extrasLoaded = true;
      });

      // Load collection separately (needs details first)
      if (!isTV && details != null) {
        final col = details['belongs_to_collection'] as Map<String, dynamic>?;
        if (col != null) {
          final colId = col['id'] as int;
          final parts = await runSafe(
            widget.service.getCollection(colId),
            <Movie>[],
          );
          if (mounted && parts.isNotEmpty) {
            setState(
              () => _collection = parts.where((m) => m.id != id).toList(),
            );
          }
        }
      }
    });
  }

  Future<void> _loadFriendsReviews() async {
    final id = widget.movie.id;
    final isTV = widget.movie.isTV;
    if (!mounted) return;
    setState(() => _loadingFriendsReviews = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final data = await apiService.getTitleReviews(isTV ? 'tv' : 'movie', id);
      if (mounted) {
        setState(() {
          _friendsReviews = data['friends'] as List<dynamic>? ?? [];
          _communityReviews = data['community'] as List<dynamic>? ?? [];
          _loadingFriendsReviews = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading friends reviews: $e');
      if (mounted) {
        setState(() => _loadingFriendsReviews = false);
      }
    }
  }

  /// cinema+ üyelerinin topluluk skorunu çeker (sessiz: hata rozeti gizler).
  Future<void> _loadCommunityScore() async {
    final id = widget.movie.id;
    final isTV = widget.movie.isTV;
    try {
      final apiService = ref.read(apiServiceProvider);
      final score = await apiService.getTitleScore(isTV ? 'tv' : 'movie', id);
      if (mounted) setState(() => _communityScore = score);
    } catch (e) {
      debugPrint('Error loading community score: $e');
    }
  }

  Future<void> _toggleWatchlist() async {
    HapticFeedback.mediumImpact();
    final movie = widget.movie;
    final watchlist = ref.read(watchlistProvider);
    final inWatchlist = watchlist.maybeWhen(
      data: (list) => list.any((m) => m.id == movie.id && m.isTV == movie.isTV),
      orElse: () => false,
    );
    final c = context.c;
    if (inWatchlist) {
      await ref.read(watchlistProvider.notifier).remove(movie.id, movie.isTV);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)
                    ?.get('title_removed_from_watchlist')
                    .replaceAll('{}', movie.title) ??
                '${movie.title} removed from watchlist.',
          ),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: AppLocalizations.of(context)?.get('undo') ?? 'Undo',
            textColor: c.red,
            onPressed: () async {
              await ref.read(watchlistProvider.notifier).add(movie);
            },
          ),
        ),
      );
    } else {
      await ref.read(watchlistProvider.notifier).add(movie);
    }
  }

  void _openTrailer() {
    if (_trailerKey == null) return;
    HapticFeedback.lightImpact();
    // Üstte kapat (✕) butonu olan kendi WebView ekranımız.
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TrailerPlayerScreen(
          videoId: _trailerKey!,
          title: widget.movie.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final watchlistState = ref.watch(watchlistProvider);
    final inWatchlist = watchlistState.maybeWhen(
      data: (list) => list.any((m) => m.id == movie.id && m.isTV == movie.isTV),
      orElse: () => false,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (ctx, ctrl) {
        final c = ctx.c;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: c.bg.withValues(alpha: c.isLight ? 0.96 : 0.85),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border.all(
                  color: c.isLight
                      ? c.border
                      : Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: ctrl,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heroRow(movie),
                          const SizedBox(height: 16),
                          _actionButtons(movie, inWatchlist),
                          const SizedBox(height: 16),
                          _ratingSection(c),
                          _friendsReviewsSection(c),
                          if ((_details?['tagline'] as String? ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              '"${_details!['tagline']}"',
                              style: TextStyle(
                                color: c.dim,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                height: 1.5,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (_extrasLoaded) ...[
                            if (_providers.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('detail_where_to_watch'),
                              const SizedBox(height: 10),
                              _providersRow(),
                            ],
                            if (_cast.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('detail_cast'),
                              const SizedBox(height: 10),
                              _castRow(),
                            ],
                            if (_keywords.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('detail_keywords'),
                              const SizedBox(height: 8),
                              _keywordsWrap(),
                            ],
                          ] else ...[
                            const SizedBox(height: 20),
                            Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.dim,
                                ),
                              ),
                            ),
                          ],
                          if (movie.overview.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('detail_storyline'),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                movie.overview,
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 14,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                          if (_reviews.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('detail_reviews'),
                            const SizedBox(height: 10),
                            ..._reviews.take(3).map(_reviewCard),
                          ],
                          if (_collection.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('detail_collection'),
                            const SizedBox(height: 10),
                            _collectionRow(context),
                          ],
                          if (widget.movie.isTV && _extrasLoaded) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('detail_seasons'),
                            const SizedBox(height: 10),
                            _seasonsSection(),
                          ],
                          if (_similar.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('detail_similar'),
                            const SizedBox(height: 10),
                            _similarRow(context),
                          ],
                          const SizedBox(height: 16),
                          _discoverButton(context, movie),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: MediaQuery.of(context).viewInsets.bottom,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _heroRow(Movie movie) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 100,
                height: 150,
                child: movie.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 180,
                        placeholder: (context, url) =>
                            ColoredBox(color: c.card),
                        errorWidget: (context, url, error) =>
                            ColoredBox(color: c.card),
                      )
                    : ColoredBox(color: c.card),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Tooltip(
                message:
                    AppLocalizations.of(context)?.get('block_and_hide_title') ??
                    'Block and Hide Title',
                child: SpringButton(
                  onTap: _confirmBlockMovie,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.visibility_off_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Tooltip(
                message:
                    AppLocalizations.of(context)?.get('recommend_to_friend') ??
                    'Recommend to Friend',
                child: SpringButton(
                  onTap: _openRecommendSheet,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                movie.title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [_synergyBadge(c)]),
              if (movie.year.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(movie.year, style: TextStyle(color: c.dim, fontSize: 13)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (movie.isTV ? c.blue : c.red).withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      movie.isTV
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_tv') ??
                                'Dizi')
                          : (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_movie') ??
                                'Film'),
                      style: TextStyle(
                        color: movie.isTV ? c.blue : c.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if ((_details?['runtime'] as int? ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_details!['runtime']} ${AppLocalizations.of(context)?.get('detail_minutes') ?? 'dk'}',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmBlockMovie() {
    MovieDetailSheet.confirmBlockMovie(
      context: context,
      ref: ref,
      movie: widget.movie,
      onBlocked: () {
        if (mounted) {
          Navigator.pop(context); // Close detail sheet
        }
      },
    );
  }

  /// "Arkadaşına Öner" akışı: arkadaş seçici alt sayfa açar, seçilince
  /// öneriyi backend'e gönderir (arkadaş push bildirimi alır).
  Future<void> _openRecommendSheet() async {
    await MovieDetailSheet.showRecommendSheet(
      context: context,
      ref: ref,
      movie: widget.movie,
    );
  }

  Widget _actionButtons(Movie movie, bool inWatchlist) {
    final c = context.c;
    final watchlistLabel = inWatchlist
        ? (AppLocalizations.of(context)?.get('detail_watchlist_remove') ??
              'Listeden Çıkar')
        : (AppLocalizations.of(context)?.get('detail_watchlist_add') ??
              'İzleme Listesine Ekle');

    return Row(
      children: [
        // Watchlist toggle
        Expanded(
          child: Tooltip(
            message: watchlistLabel,
            child: Semantics(
              button: true,
              label: watchlistLabel,
              child: SpringButton(
                onTap: _toggleWatchlist,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: inWatchlist ? c.red.withValues(alpha: 0.15) : c.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: inWatchlist ? c.red : c.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        inWatchlist
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: inWatchlist ? c.red : c.dim,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        inWatchlist
                            ? (AppLocalizations.of(
                                    context,
                                  )?.get('detail_watchlist_remove') ??
                                  'Listeden Çıkar')
                            : (AppLocalizations.of(
                                    context,
                                  )?.get('detail_watchlist_add_short') ??
                                  'Watchlist'),
                        style: TextStyle(
                          color: inWatchlist ? c.red : c.dim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Share button
        const SizedBox(width: 10),
        Tooltip(
          message: AppLocalizations.of(context)?.get('share') ?? 'Share',
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context)?.get('share') ?? 'Share',
            child: SpringButton(
              onTap: () {
                final typeLabel = widget.movie.isTV
                    ? (AppLocalizations.of(context)?.get('onboarding_tv') ??
                          'Dizi')
                    : (AppLocalizations.of(context)?.get('onboarding_movie') ??
                          'Film');
                final shareTemplate =
                    AppLocalizations.of(context)?.get('detail_share_text') ??
                    'What to Watch recommendation: {}';
                final shareText = shareTemplate.replaceAll(
                  '{}',
                  '${widget.movie.title} (${widget.movie.year})\n⭐ ${widget.movie.voteAverage.toStringAsFixed(1)} · $typeLabel',
                );
                Share.share(shareText);
              },
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Icon(Icons.share_rounded, color: c.dim, size: 18),
              ),
            ),
          ),
        ),
        // Trailer button (only shown when available)
        if (_trailerKey != null) ...[
          const SizedBox(width: 10),
          Tooltip(
            message:
                AppLocalizations.of(context)?.get('detail_trailer') ??
                'Trailer',
            child: Semantics(
              button: true,
              label:
                  AppLocalizations.of(context)?.get('detail_trailer') ??
                  'Trailer',
              child: SpringButton(
                onTap: _openTrailer,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFF0000).withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_circle_rounded,
                        color: Color(0xFFFF0000),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)?.get('detail_trailer') ??
                            'Trailer',
                        style: const TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _providersRow() {
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _providers.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final p = _providers[i];
          return Container(
            margin: const EdgeInsets.only(right: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: p.logoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: p.logoUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 80,
                            placeholder: (context, url) =>
                                ColoredBox(color: c.card),
                            errorWidget: (context, url, error) =>
                                ColoredBox(color: c.card),
                          )
                        : ColoredBox(color: c.card),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 52,
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _castRow() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _cast.length,
        itemBuilder: (ctx, i) {
          final pal = ctx.c;
          final c = _cast[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonScreen(
                    personId: c.id,
                    personName: c.name,
                    service: widget.service,
                  ),
                ),
              );
            },
            child: Container(
              width: 64,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: c.profileUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: c.profileUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 90,
                              placeholder: (context, url) =>
                                  _avatarPlaceholder(c.name),
                              errorWidget: (context, url, error) =>
                                  _avatarPlaceholder(c.name),
                            )
                          : _avatarPlaceholder(c.name),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: pal.ink,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    c.character,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.dim, fontSize: 8),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _avatarPlaceholder(String name) {
    final c = context.c;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: c.border,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: c.dim,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _similarRow(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _similar.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final s = _similar[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) =>
                    MovieDetailSheet(movie: s, service: widget.service),
              );
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: s.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: s.posterUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 150,
                        placeholder: (context, url) =>
                            ColoredBox(color: c.card),
                        errorWidget: (context, url, error) =>
                            ColoredBox(color: c.card),
                      )
                    : ColoredBox(color: c.card),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _discoverButton(BuildContext context, Movie movie) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultsScreen(
              genreStr: movie.genreIds.isNotEmpty
                  ? movie.genreIds.first.toString()
                  : null,
              includeMovies: !movie.isTV,
              includeTv: movie.isTV,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.red, Color(0xFFB83050)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context)?.get('recommend_similar') ??
              'Recommend Similar',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _collectionRow(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _collection.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final m = _collection[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) =>
                    MovieDetailSheet(movie: m, service: widget.service),
              );
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: m.posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: m.posterUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 150,
                              placeholder: (context, url) =>
                                  ColoredBox(color: c.card),
                              errorWidget: (context, url, error) =>
                                  ColoredBox(color: c.card),
                            )
                          : ColoredBox(color: c.card),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(m.year, style: TextStyle(color: c.dim, fontSize: 9)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _seasonsSection() {
    final c = context.c;
    final seasons = (_details?['seasons'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((s) => (s['season_number'] as int? ?? 0) > 0)
        .toList();
    if (seasons.isEmpty) return const SizedBox.shrink();
    return Column(
      children: seasons.map((s) {
        final num = s['season_number'] as int;
        final name =
            s['name'] as String? ??
            (AppLocalizations.of(context)
                    ?.get('detail_season_label')
                    .replaceAll('{}', num.toString()) ??
                'Season $num');
        final eps = s['episode_count'] as int? ?? 0;
        final year = ((s['air_date'] as String? ?? '').length >= 4)
            ? (s['air_date'] as String).substring(0, 4)
            : '';
        final watched = _watchedSeasons.contains(num);
        return GestureDetector(
          onTap: () async {
            HapticFeedback.mediumImpact();
            await PrefsService.toggleSeason(widget.movie.id, num);
            final updated = await PrefsService.getWatchedSeasons(
              widget.movie.id,
            );
            if (mounted) setState(() => _watchedSeasons = updated);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: watched ? AppColors.green.withValues(alpha: 0.12) : c.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: watched
                    ? AppColors.green.withValues(alpha: 0.3)
                    : c.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  watched
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: watched ? AppColors.green : c.dim,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: watched ? AppColors.green : c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          final suffix =
                              AppLocalizations.of(
                                context,
                              )?.get('detail_episodes_count') ??
                              'episodes';
                          return Text(
                            '$eps $suffix${year.isNotEmpty ? " · $year" : ""}',
                            style: TextStyle(color: c.dim, fontSize: 11),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _keywordsWrap() {
    final c = context.c;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _keywords
          .take(15)
          .map(
            (kw) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border),
              ),
              child: Text(
                kw,
                style: TextStyle(
                  color: c.dim,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _reviewCard(Review r) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.author,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (r.rating != null) ...[
                Icon(Icons.star_rounded, color: c.gold, size: 12),
                const SizedBox(width: 3),
                Text(
                  r.rating!.toStringAsFixed(1),
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (r.date.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(r.date, style: TextStyle(color: c.dim, fontSize: 10)),
          ],
          const SizedBox(height: 8),
          Text(
            r.content.length > 300
                ? '${r.content.substring(0, 300)}…'
                : r.content,
            style: TextStyle(
              color: c.isLight ? const Color(0xFF3A352E) : Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  int _calculateSynergyScore() {
    final matchVal = widget.movie.matchScore;
    final tmdbVal = (widget.movie.voteAverage * 10).clamp(0, 100).toInt();

    if (_communityScore != null && _communityScore!['enough'] == true) {
      final commVal = (_communityScore!['liked_percent'] as num?)?.toInt() ?? 0;
      return (matchVal * 0.4 + commVal * 0.3 + tmdbVal * 0.3).round();
    } else {
      return (matchVal * 0.6 + tmdbVal * 0.4).round();
    }
  }

  Widget _synergyBadge(ThemePalette c) {
    final synergyScore = _calculateSynergyScore();

    return SpringButton(
      onTap: () => _showScoreBreakdown(context, c, synergyScore),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.green.withValues(alpha: 0.3), width: 1),
          boxShadow: CinemaShadows.glow(c.green, strength: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: c.green, size: 14),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context)
                      ?.get('synergy_score_match')
                      .replaceAll('{}', '$synergyScore') ??
                  '$synergyScore% Match',
              style: TextStyle(
                color: c.green,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline_rounded,
              color: c.green.withValues(alpha: 0.7),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }

  void _showScoreBreakdown(
    BuildContext context,
    ThemePalette c,
    int synergyScore,
  ) {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Center(
          child: Text(
            AppLocalizations.of(context)?.get('match_details') ??
                'Match Details',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Featured Aggregate Synergy Score
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.green.withValues(alpha: 0.1),
                border: Border.all(
                  color: c.green.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '%$synergyScore',
                    style: TextStyle(
                      color: c.green,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)?.get('match_button') ??
                        'Match',
                    style: TextStyle(
                      color: c.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildDialogRow(
              AppLocalizations.of(context)?.get('personal_taste_match') ??
                  'Personal Taste Match',
              '%${widget.movie.matchScore}',
              widget.movie.matchScore / 100.0,
              c.green,
            ),
            _buildDialogRow(
              AppLocalizations.of(context)?.get('tmdb_rating') ?? 'TMDB Rating',
              '${widget.movie.voteAverage.toStringAsFixed(1)} / 10',
              widget.movie.voteAverage / 10.0,
              c.gold,
            ),
            if (_communityScore != null && _communityScore!['total'] > 0)
              _buildDialogRow(
                AppLocalizations.of(context)?.get('cinema_member_score') ??
                    'cinema+ Member Score',
                _communityScore!['enough'] == true
                    ? '%${_communityScore!['liked_percent']}'
                    : (isTr
                          ? '${_communityScore!['total']} oy'
                          : '${_communityScore!['total']} votes'),
                _communityScore!['enough'] == true
                    ? ((_communityScore!['liked_percent'] as num?)
                                  ?.toDouble() ??
                              0.0) /
                          100.0
                    : 0.0,
                c.red,
              ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.borderSoft),
              ),
              child: Text(
                isTr
                    ? (_communityScore != null &&
                              _communityScore!['enough'] == true)
                          ? 'Sinerji Skoru; kişisel zevk uyumu (%40), topluluk skoru (%30) ve TMDB puanının (%30) ağırlıklı karmasıdır.'
                          : 'Sinerji Skoru; kişisel zevk uyumu (%60) ve TMDB puanının (%40) ağırlıklı karmasıdır.'
                    : (_communityScore != null &&
                          _communityScore!['enough'] == true)
                    ? 'Synergy Score is a weighted mix of taste match (40%), community score (30%), and TMDB rating (30%).'
                    : 'Synergy Score is a mix of taste match (60%) and TMDB rating (40%).',
                style: TextStyle(color: c.dim, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)?.get('semantics_close') ?? 'Close',
              style: TextStyle(color: c.dim, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(
    String label,
    String value,
    double fraction,
    Color color,
  ) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String key) {
    return Builder(
      builder: (context) {
        final label = AppLocalizations.of(context)?.get(key) ?? key;
        return Text(
          label.toUpperCase(),
          style: TextStyle(
            color: context.c.dim,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        );
      },
    );
  }

  Widget _ratingSection(ThemePalette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('detail_rate_title'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ratingButton(
                0,
                c.rBerbat,
                AppLocalizations.of(context)?.get('recap_stat_awful') ??
                    'Awful',
                c,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ratingButton(
                1,
                c.rEh,
                AppLocalizations.of(context)?.get('recap_stat_meh') ?? 'Meh',
                c,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ratingButton(
                2,
                c.rIyi,
                AppLocalizations.of(context)?.get('recap_stat_good') ?? 'Good',
                c,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ratingButton(
                3,
                c.rHarika,
                AppLocalizations.of(context)?.get('recap_stat_amazing') ??
                    'Amazing',
                c,
              ),
            ),
          ],
        ),
        if (_currentRating != null) ...[_commentSection(c)],
      ],
    );
  }

  Widget _commentSection(ThemePalette c) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _sectionLabel('detail_your_review'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.borderSoft),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              TextField(
                controller: _commentController,
                maxLength: 280,
                maxLines: 3,
                style: TextStyle(color: c.ink, fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      tr?.get('review_comment_hint') ??
                      'Düşüncelerini paylaş...',
                  hintStyle: TextStyle(color: c.dim, fontSize: 13),
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isSpoiler = !_isSpoiler;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _isSpoiler
                                ? c.rBerbat.withValues(alpha: 0.15)
                                : c.borderSoft.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isSpoiler ? c.rBerbat : c.borderSoft,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isSpoiler
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 14,
                                color: _isSpoiler ? c.rBerbat : c.dim,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tr?.get('review_spoiler') ?? 'Spoiler İçerir',
                                style: TextStyle(
                                  color: _isSpoiler ? c.rBerbat : c.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isPrivate = !_isPrivate;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _isPrivate
                                ? c.gold.withValues(alpha: 0.15)
                                : c.borderSoft.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isPrivate ? c.gold : c.borderSoft,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isPrivate
                                    ? Icons.lock_rounded
                                    : Icons.lock_open_rounded,
                                size: 14,
                                color: _isPrivate ? c.gold : c.dim,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tr?.get('review_private') ?? 'Gizli',
                                style: TextStyle(
                                  color: _isPrivate ? c.gold : c.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '${_commentController.text.length} / 280',
                        style: TextStyle(color: c.dim, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _justSavedComment
                            ? null
                            : () async {
                                HapticFeedback.mediumImpact();
                                FocusScope.of(context).unfocus();
                                if (_currentRating != null) {
                                  try {
                                    await PrefsService.saveRating(
                                      movie: widget.movie,
                                      rating: _currentRating!,
                                      comment: _commentController.text,
                                      isSpoiler: _isSpoiler ? 1 : 0,
                                      isPrivate: _isPrivate ? 1 : 0,
                                    );
                                    ref
                                        .read(recommendationEngineProvider)
                                        .invalidateCache(
                                          isNegativeChange:
                                              _currentRating! <= 1,
                                        )
                                        .catchError((_) => {});
                                    ref.invalidate(statsProvider);
                                    ref
                                        .read(syncServiceProvider)
                                        .sync()
                                        .catchError((_) => {});
                                    ref
                                        .read(socialProvider.notifier)
                                        .loadActivityFeed()
                                        .catchError((_) => {});

                                    if (mounted) {
                                      setState(() {
                                        _justSavedComment = true;
                                      });
                                      final isGuest = !ref
                                          .read(authProvider)
                                          .isLoggedIn;
                                      final baseMsg =
                                          AppLocalizations.of(
                                            context,
                                          )?.get('review_saved_successfully') ??
                                          'Review saved successfully';
                                      final suffix = isGuest
                                          ? (AppLocalizations.of(
                                                      context,
                                                    )?.locale.languageCode ==
                                                    'tr'
                                                ? ' (Yerel kaydedildi, giriş yapınca eşitlenecektir.)'
                                                : ' (Saved locally, will sync when logged in.)')
                                          : '';

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$baseMsg$suffix',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          backgroundColor: c.red,
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                      Future.delayed(
                                        const Duration(seconds: 2),
                                        () {
                                          if (mounted) {
                                            setState(() {
                                              _justSavedComment = false;
                                            });
                                          }
                                        },
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)
                                                    ?.get('error_occurred_msg')
                                                    .replaceAll('{}', '$e') ??
                                                'Error: $e',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          backgroundColor: c.red,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _justSavedComment ? c.green : c.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _justSavedComment
                              ? (AppLocalizations.of(context)?.get('saved') ??
                                    'Saved ✔')
                              : (tr?.get('review_save') ?? 'Kaydet'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _friendsReviewsSection(ThemePalette c) {
    final tr = AppLocalizations.of(context);
    if (_loadingFriendsReviews) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_friendsReviews.isEmpty && _communityReviews.isEmpty) {
      final hasUserRated = _currentRating != null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            hasUserRated
                ? (tr?.get('review_no_friends') ??
                      'Arkadaşlarından henüz yorum yok')
                : (tr?.get('review_empty_first') ?? 'İlk yorumu sen bırak'),
            style: TextStyle(
              color: c.dim,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_friendsReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('review_friends_title'),
          const SizedBox(height: 10),
          ..._friendsReviews.map((rev) => ReviewItem(rev: rev)),
        ],
        if (_communityReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('review_community_title'),
          const SizedBox(height: 10),
          ..._communityReviews.map((rev) => ReviewItem(rev: rev)),
        ],
      ],
    );
  }

  Widget _ratingButton(int rating, Color color, String label, ThemePalette c) {
    final active = _currentRating == rating;
    return SpringButton(
      onTap: () async {
        HapticFeedback.lightImpact();
        if (active) {
          await PrefsService.deleteRating(widget.movie.id, widget.movie.isTV);
          ref
              .read(recommendationEngineProvider)
              .invalidateCache(isNegativeChange: true)
              .catchError((_) => {});
          setState(() {
            _currentRating = null;
            _commentController.clear();
            _isSpoiler = false;
            _isPrivate = false;
          });
        } else {
          await PrefsService.saveRating(
            movie: widget.movie,
            rating: rating,
            comment: _commentController.text,
            isSpoiler: _isSpoiler ? 1 : 0,
            isPrivate: _isPrivate ? 1 : 0,
          );
          ref
              .read(recommendationEngineProvider)
              .invalidateCache(isNegativeChange: rating <= 1)
              .catchError((_) => {});

          // İsabet telemetrisi: yalnızca öneri motoru atıflı yapımlar sayılır
          // (discover/seed/friend/explore). Arama gibi atıfsız yüzeyler
          // sayaçları kirletmesin diye recoSource'suz yapımlar atlanır.
          final recoSource = widget.movie.recoSource;
          if (recoSource != null) {
            PrefsService.recordRecoOutcome(
              source: recoSource,
              liked: rating >= 2,
            ).catchError(
              (e) => debugPrint("Reco telemetry write failed: $e"),
            );
          }

          setState(() {
            _currentRating = rating;
          });

          if (mounted && !ref.read(authProvider).isLoggedIn) {
            final tr = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr?.locale.languageCode == 'tr'
                      ? 'Puanınız yerel kaydedildi. Giriş yapınca eşitlenecektir.'
                      : 'Rating saved locally. Will sync when logged in.',
                ),
                backgroundColor: c.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
        ref.invalidate(statsProvider);
        ref.read(syncServiceProvider).sync();
      },
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: active ? color : c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : c.borderSoft,
            width: active ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? ((color == c.rEh || color == c.rIyi || color == c.rHarika)
                      ? Colors.black87
                      : Colors.white)
                : c.dim,
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
