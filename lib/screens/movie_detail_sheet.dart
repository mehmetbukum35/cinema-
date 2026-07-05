import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isTr ? 'Yapımı Gizle' : 'Hide Title',
          style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          isTr
              ? 'Bu yapımı engellemek ve tüm listelerden kalıcı olarak gizlemek istediğinize emin misiniz?'
              : 'Are you sure you want to block this title and permanently hide it from all lists?',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              isTr ? 'İptal' : 'Cancel',
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
                      isTr
                          ? 'Yapım gizlendi ve listelerden kaldırıldı.'
                          : 'Title hidden and removed from lists.',
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
              isTr ? 'Gizle' : 'Hide',
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

    final results = await Future.wait([
      runSafe(widget.service.getTrailerKey(id, isTV: isTV), null),
      runSafe(
        widget.service.getWatchProviders(id, isTV: isTV),
        <WatchProvider>[],
      ),
      runSafe(widget.service.getCredits(id, isTV: isTV), <CastMember>[]),
      runSafe(widget.service.getSimilar(id, isTV: isTV), <Movie>[]),
      runSafe(widget.service.getFullDetails(id, isTV: isTV), null),
      runSafe(widget.service.getReviews(id, isTV: isTV), <Review>[]),
      runSafe(widget.service.getKeywords(id, isTV: isTV), <String>[]),
      runSafe(PrefsService.getWatchedSeasons(id), <int>{}),
      runSafe(PrefsService.getRating(id, isTV), null),
    ]);
    if (!mounted) return;
    final details = results[4] as Map<String, dynamic>?;
    setState(() {
      _trailerKey = results[0] as String?;
      _providers = results[1] as List<WatchProvider>;
      _cast = results[2] as List<CastMember>;
      _similar = (results[3] as List<Movie>).take(10).toList();
      _details = details;
      _reviews = results[5] as List<Review>;
      _keywords = results[6] as List<String>;
      _watchedSeasons = results[7] as Set<int>;
      final ratingData = results[8] as Map<String, dynamic>?;
      _currentRating = ratingData?['rating'] as int?;
      _commentController.text = ratingData?['comment'] as String? ?? '';
      _isSpoiler = (ratingData?['is_spoiler'] ?? 0) == 1;
      _extrasLoaded = true;
    });

    _loadFriendsReviews();
    _loadCommunityScore();

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
          setState(() => _collection = parts.where((m) => m.id != id).toList());
        }
      }
    }
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    final c = context.c;
    if (inWatchlist) {
      await ref.read(watchlistProvider.notifier).remove(movie.id, movie.isTV);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTr
                ? '${movie.title} izleme listesinden çıkarıldı.'
                : '${movie.title} removed from watchlist.',
          ),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: isTr ? 'Geri Al' : 'Undo',
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
                              _sectionLabel('NEREDE İZLENİR?'),
                              const SizedBox(height: 10),
                              _providersRow(),
                            ],
                            if (_cast.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('OYUNCULAR'),
                              const SizedBox(height: 10),
                              _castRow(),
                            ],
                            if (_keywords.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _sectionLabel('ANAHTAR KELİMELER'),
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
                            _sectionLabel('KONU'),
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
                            _sectionLabel('YORUMLAR'),
                            const SizedBox(height: 10),
                            ..._reviews.take(3).map(_reviewCard),
                          ],
                          if (_collection.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('SERİNİN DİĞER FİLMLERİ'),
                            const SizedBox(height: 10),
                            _collectionRow(context),
                          ],
                          if (widget.movie.isTV && _extrasLoaded) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('SEZONLAR'),
                            const SizedBox(height: 10),
                            _seasonsSection(),
                          ],
                          if (_similar.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('BENZER İÇERİKLER'),
                            const SizedBox(height: 10),
                            _similarRow(context),
                          ],
                          const SizedBox(height: 16),
                          _discoverButton(context, movie),
                          const SizedBox(height: 8),
                          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
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
                        placeholder: (context, url) => ColoredBox(color: c.card),
                        errorWidget: (context, url, error) =>
                            ColoredBox(color: c.card),
                      )
                    : ColoredBox(color: c.card),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
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
            Positioned(
              top: 6,
              right: 6,
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
              Row(
                children: [
                  _synergyBadge(c),
                ],
              ),
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
    return Row(
      children: [
        // Watchlist toggle
        Expanded(
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
        // Share button
        const SizedBox(width: 10),
        SpringButton(
          onTap: () {
            final typeLabel = widget.movie.isTV
                ? (AppLocalizations.of(context)?.get('onboarding_tv') ?? 'Dizi')
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
        // Trailer button (only shown when available)
        if (_trailerKey != null) ...[
          const SizedBox(width: 10),
          SpringButton(
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
          AppLocalizations.of(context)?.locale.languageCode == 'tr'
              ? 'Benzer Öner'
              : 'Recommend Similar',
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    final synergyScore = _calculateSynergyScore();
    
    return SpringButton(
      onTap: () => _showScoreBreakdown(context, c, synergyScore),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: c.green.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: CinemaShadows.glow(c.green, strength: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: c.green, size: 14),
            const SizedBox(width: 4),
            Text(
              isTr ? '%$synergyScore Uyumlu' : '$synergyScore% Match',
              style: TextStyle(
                color: c.green,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.info_outline_rounded, color: c.green.withValues(alpha: 0.7), size: 12),
          ],
        ),
      ),
    );
  }

  void _showScoreBreakdown(BuildContext context, ThemePalette c, int synergyScore) {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Center(
          child: Text(
            isTr ? 'Uyum Detayları' : 'Match Details',
            style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w800),
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
                border: Border.all(color: c.green.withValues(alpha: 0.3), width: 2),
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
                    isTr ? 'Uyum' : 'Match',
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
              isTr ? 'Kişisel Beğeni Uyumu' : 'Personal Taste Match',
              '%${widget.movie.matchScore}',
              widget.movie.matchScore / 100.0,
              c.green,
            ),
            _buildDialogRow(
              isTr ? 'TMDB Puanı' : 'TMDB Rating',
              '${widget.movie.voteAverage.toStringAsFixed(1)} / 10',
              widget.movie.voteAverage / 10.0,
              c.gold,
            ),
            if (_communityScore != null && _communityScore!['total'] > 0)
              _buildDialogRow(
                isTr ? 'cinema+ Üye Skoru' : 'cinema+ Member Score',
                _communityScore!['enough'] == true
                    ? '%${_communityScore!['liked_percent']}'
                    : (isTr ? '${_communityScore!['total']} oy' : '${_communityScore!['total']} votes'),
                _communityScore!['enough'] == true
                    ? ((_communityScore!['liked_percent'] as num?)?.toDouble() ?? 0.0) / 100.0
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
                    ? (_communityScore != null && _communityScore!['enough'] == true)
                        ? 'Sinerji Skoru; kişisel zevk uyumu (%40), topluluk skoru (%30) ve TMDB puanının (%30) ağırlıklı karmasıdır.'
                        : 'Sinerji Skoru; kişisel zevk uyumu (%60) ve TMDB puanının (%40) ağırlıklı karmasıdır.'
                    : (_communityScore != null && _communityScore!['enough'] == true)
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
              isTr ? 'Kapat' : 'Close',
              style: TextStyle(color: c.dim, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value, double fraction, Color color) {
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

  Widget _sectionLabel(String text) {
    return Builder(
      builder: (context) {
        final key = switch (text) {
          'NEREDE İZLENİR?' => 'detail_where_to_watch',
          'OYUNCULAR' => 'detail_cast',
          'ANAHTAR KELİMELER' => 'detail_keywords',
          'KONU' => 'detail_storyline',
          'YORUMLAR' => 'detail_reviews',
          'SERİNİN DİĞER FİLMLERİ' => 'detail_collection',
          'SEZONLAR' => 'detail_seasons',
          'BENZER İÇERİKLER' => 'detail_similar',
          _ => null,
        };
        final label = key != null
            ? (AppLocalizations.of(context)?.get(key) ?? text)
            : text;
        return Text(
          label,
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(isTr ? 'BU YAPIMI PUANLA' : 'RATE THIS TITLE'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _ratingButton(0, c.rBerbat, isTr ? 'Berbat' : 'Awful', c)),
            const SizedBox(width: 6),
            Expanded(child: _ratingButton(1, c.rEh, isTr ? 'Eh' : 'Meh', c)),
            const SizedBox(width: 6),
            Expanded(child: _ratingButton(2, c.rIyi, isTr ? 'İyi' : 'Good', c)),
            const SizedBox(width: 6),
            Expanded(child: _ratingButton(3, c.rHarika, isTr ? 'Harika' : 'Amazing', c)),
          ],
        ),
        if (_currentRating != null) ...[
          _commentSection(c),
        ],
      ],
    );
  }

  Widget _commentSection(ThemePalette c) {
    final tr = AppLocalizations.of(context);
    final isTr = tr?.locale.languageCode == 'tr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _sectionLabel(isTr ? 'YORUMUNUZ' : 'YOUR REVIEW'),
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
                  hintText: tr?.get('review_comment_hint') ?? 'Düşüncelerini paylaş...',
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
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _isSpoiler = !_isSpoiler;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            _isSpoiler ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
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
                  Row(
                    children: [
                      Text(
                        '${_commentController.text.length} / 280',
                        style: TextStyle(color: c.dim, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _justSavedComment ? null : () async {
                          HapticFeedback.mediumImpact();
                          FocusScope.of(context).unfocus();
                          if (_currentRating != null) {
                            try {
                              await PrefsService.saveRating(
                                movie: widget.movie,
                                rating: _currentRating!,
                                comment: _commentController.text,
                                isSpoiler: _isSpoiler ? 1 : 0,
                              );
                              ref.invalidate(statsProvider);
                              ref.read(syncServiceProvider).sync().catchError((_) => {});
                              ref.read(socialProvider.notifier).loadActivityFeed().catchError((_) => {});
                              
                              if (mounted) {
                                setState(() {
                                  _justSavedComment = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isTr ? 'Yorumunuz kaydedildi' : 'Review saved successfully',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: c.red,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (mounted) {
                                    setState(() {
                                      _justSavedComment = false;
                                    });
                                  }
                                });
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isTr ? 'Hata oluştu: $e' : 'Error: $e',
                                      style: const TextStyle(color: Colors.white),
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
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _justSavedComment
                              ? (isTr ? 'Kaydedildi ✔' : 'Saved ✔')
                              : (tr?.get('review_save') ?? 'Kaydet'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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

  Widget _buildReviewItem(dynamic rev, ThemePalette c) {
    final tr = AppLocalizations.of(context);
    final ratingVal = rev['rating'] is int
        ? rev['rating'] as int
        : (int.tryParse(rev['rating']?.toString() ?? '') ?? 3);
    final reviewerName = rev['friend_name'] ?? rev['friend_username'] ?? 'User';
    final comment = rev['comment'] as String? ?? '';
    final isSpoiler = (rev['is_spoiler'] ?? 0) == 1;

    Color badgeColor = c.rIyi;
    String badgeText = 'İyi';
    if (ratingVal == 3) {
      badgeColor = c.rHarika;
      badgeText = tr?.get('profile_harika') ?? 'Harika';
    } else if (ratingVal == 2) {
      badgeColor = c.rIyi;
      badgeText = tr?.get('profile_iyi') ?? 'İyi';
    } else if (ratingVal == 1) {
      badgeColor = c.rEh;
      badgeText = tr?.get('profile_eh') ?? 'Eh';
    } else if (ratingVal == 0) {
      badgeColor = c.rBerbat;
      badgeText = tr?.get('profile_berbat') ?? 'Berbat';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.border,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      reviewerName.isNotEmpty ? reviewerName[0].toUpperCase() : 'U',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    reviewerName,
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: badgeColor, size: 10),
                    const SizedBox(width: 2),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SpoilerComment(comment: comment, isSpoiler: isSpoiler),
        ],
      ),
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
                ? (tr?.get('review_no_friends') ?? 'Arkadaşlarından henüz yorum yok')
                : (tr?.get('review_empty_first') ?? 'İlk yorumu sen bırak'),
            style: TextStyle(color: c.dim, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_friendsReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel(tr?.get('review_friends_title') ?? 'Arkadaşlarından Yorumlar'),
          const SizedBox(height: 10),
          ..._friendsReviews.map((rev) => _buildReviewItem(rev, c)),
        ],
        if (_communityReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel(tr?.get('review_community_title') ?? 'Topluluk Yorumları'),
          const SizedBox(height: 10),
          ..._communityReviews.map((rev) => _buildReviewItem(rev, c)),
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
          setState(() {
            _currentRating = null;
            _commentController.clear();
            _isSpoiler = false;
          });
        } else {
          await PrefsService.saveRating(
            movie: widget.movie,
            rating: rating,
            comment: _commentController.text,
            isSpoiler: _isSpoiler ? 1 : 0,
          );
          setState(() {
            _currentRating = rating;
          });
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
                ? ((color == c.rEh || color == c.rIyi) ? Colors.black87 : Colors.white)
                : c.dim,
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class RecommendSheet extends StatefulWidget {
  final Movie movie;
  final List<dynamic> friends;
  final WidgetRef ref;

  const RecommendSheet({
    super.key,
    required this.movie,
    required this.friends,
    required this.ref,
  });

  @override
  State<RecommendSheet> createState() => RecommendSheetState();
}

class RecommendSheetState extends State<RecommendSheet> {
  final _noteCtrl = TextEditingController();
  int? _sendingToFriendId;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr?.get('recommend_pick_friend') ?? 'Kime önerelim?',
            style: TextStyle(
              color: c.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.movie.title,
            style: TextStyle(color: c.dim, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteCtrl,
            maxLength: 280,
            enabled: _sendingToFriendId == null,
            style: TextStyle(color: c.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  tr?.get('recommend_note_hint') ?? 'Not ekle (isteğe bağlı)',
              hintStyle: TextStyle(color: c.dim, fontSize: 13),
              counterText: '',
              filled: true,
              fillColor: c.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.friends.length,
              itemBuilder: (listCtx, idx) {
                final f = widget.friends[idx];
                final name = f['display_name'] ?? f['username'] ?? 'User';
                final friendId = int.tryParse(f['id'].toString()) ?? 0;
                final isSending = _sendingToFriendId == friendId;
                final isAnySending = _sendingToFriendId != null;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: CinemaGradients.crimson,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.toString().isNotEmpty
                          ? name.toString()[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    name.toString(),
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.gold,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: isAnySending ? c.dim : c.gold,
                          size: 20,
                        ),
                  onTap: isAnySending
                      ? null
                      : () async {
                          final sm = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);

                          setState(() {
                            _sendingToFriendId = friendId;
                          });

                          final ok = await widget.ref
                              .read(socialProvider.notifier)
                              .recommendToFriend(
                                friendId: friendId,
                                movie: widget.movie,
                                note: _noteCtrl.text.trim(),
                              );

                          if (!mounted) return;

                          sm.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? (tr?.get('recommend_sent') ??
                                          'Öneri gönderildi!')
                                    : (widget.ref.read(socialProvider).error ??
                                          'Öneri gönderilemedi.'),
                              ),
                            ),
                          );

                          if (ok) {
                            nav.pop();
                          } else {
                            setState(() {
                              _sendingToFriendId = null;
                            });
                          }
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SpoilerComment extends StatefulWidget {
  final String comment;
  final bool isSpoiler;

  const SpoilerComment({
    super.key,
    required this.comment,
    required this.isSpoiler,
  });

  @override
  State<SpoilerComment> createState() => _SpoilerCommentState();
}

class _SpoilerCommentState extends State<SpoilerComment> {
  late bool _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = !widget.isSpoiler;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    if (widget.isSpoiler && !_reveal) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _reveal = true);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.rBerbat.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.rBerbat.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: c.rBerbat, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr?.get('review_spoiler_warning') ?? 'Spoiler içeriyor. Görmek için dokunun.',
                  style: TextStyle(
                    color: c.rBerbat,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.borderSoft.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      width: double.infinity,
      child: Text(
        widget.comment,
        style: TextStyle(
          color: c.ink,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}
