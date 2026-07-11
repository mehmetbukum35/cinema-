import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'movie_detail/recommend_sheet.dart';
import 'movie_detail/review_item.dart';
import 'movie_detail/detail_section_label.dart';
import 'movie_detail/detail_hero_row.dart';
import 'movie_detail/detail_action_buttons.dart';
import 'movie_detail/detail_media_rows.dart';
import 'movie_detail/seasons_section.dart';
import 'movie_detail/keywords_wrap.dart';
import 'movie_detail/tmdb_review_card.dart';
import '../models/movie.dart';
import '../models/cast_member.dart';
import '../models/watch_provider.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../models/review.dart';
import '../providers/watchlist_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../services/providers.dart';
import 'trailer_player_screen.dart';
import '../widgets/spring_button.dart';
import '../widgets/app_toast.dart';

/// Detay alt sayfası orkestratörü: veri yükleme fazları, puan/yorum durumu
/// ve moderasyon akışları burada; sunumsal bölümler movie_detail/ altında.
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
      showAppToast(
        context,
        tr?.get('recommend_need_login') ??
            'Öneri göndermek için giriş yapmalısın.',
        success: false,
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
      showAppToast(
        context,
        tr?.get('recommend_no_friends') ??
            'Önce Sosyal sekmesinden arkadaş eklemelisin.',
        success: false,
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
                showAppToast(
                  context,
                  AppLocalizations.of(
                        context,
                      )?.get('title_hidden_and_removed_from_') ??
                      'Title hidden and removed from lists.',
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

  void _showToast(String msg, {bool success = true}) {
    if (!mounted) return;
    // SnackBar bu modal sheet'in ARKASINDAKİ Scaffold'a çiziliyordu —
    // şikayet/engelleme geri bildirimi kullanıcıya hiç görünmüyordu.
    showAppToast(context, msg, success: success);
  }

  Future<void> _reportReview(dynamic rev, String reason) async {
    final reviewerId = int.tryParse(rev['user_id']?.toString() ?? '');
    if (reviewerId == null) return;
    final tr = AppLocalizations.of(context);
    try {
      await ref
          .read(apiServiceProvider)
          .reportReview(
            userId: reviewerId,
            movieId: widget.movie.id,
            isTV: widget.movie.isTV,
            reason: reason,
          );
      _showToast(
        tr?.get('review_reported') ?? 'Şikayetin alındı. Teşekkürler.',
      );
    } catch (e) {
      _showToast(
        tr?.get('error_occurred_msg').replaceAll('{}', '$e') ?? 'Hata: $e',
        success: false,
      );
    }
  }

  Future<void> _blockReviewer(dynamic rev) async {
    final reviewerId = int.tryParse(rev['user_id']?.toString() ?? '');
    if (reviewerId == null) return;
    final tr = AppLocalizations.of(context);
    try {
      await ref.read(apiServiceProvider).blockUser(reviewerId);
      _showToast(tr?.get('review_blocked') ?? 'Kullanıcı engellendi');
      // Engellenen kullanıcının yorumları listeden düşsün; arkadaşlık da
      // sunucuda koparıldığı için aktivite akışı yenilenir.
      _loadFriendsReviews();
      ref
          .read(socialProvider.notifier)
          .loadActivityFeed()
          .catchError((_) => {});
    } catch (e) {
      _showToast(
        tr?.get('error_occurred_msg').replaceAll('{}', '$e') ?? 'Hata: $e',
        success: false,
      );
    }
  }

  Future<bool> _confirmRatingDelete() async {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(
          tr?.get('rating_delete_with_comment_title') ?? 'Puan kaldırılsın mı?',
          style: TextStyle(color: c.ink, fontSize: 16),
        ),
        content: Text(
          tr?.get('rating_delete_with_comment_msg') ??
              'Puanı kaldırırsan yazdığın yorum da silinir.',
          style: TextStyle(color: c.dim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              tr?.get('profile_cancel') ?? 'İptal',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              tr?.get('remove') ?? 'Kaldır',
              style: TextStyle(color: c.rBerbat, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Yorum kartı: giriş yapmış kullanıcıya şikayet/engelleme menüsü açılır.
  Widget _buildReviewItem(dynamic rev) {
    final canModerate =
        ref.read(authProvider).isLoggedIn && rev['user_id'] != null;
    return ReviewItem(
      rev: rev,
      onReport: canModerate ? (reason) => _reportReview(rev, reason) : null,
      onBlock: canModerate ? () => _blockReviewer(rev) : null,
    );
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
    // Not: eski SnackBar (geri al butonuyla) bu modal sheet'in arkasında
    // kalıyordu — kullanıcı ne mesajı ne de geri al'ı görebiliyordu. Toast
    // her şeyin üstünde görünür; geri almak isteyen aynı butona tekrar basar.
    if (inWatchlist) {
      await ref.read(watchlistProvider.notifier).remove(movie.id, movie.isTV);
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context)
                ?.get('title_removed_from_watchlist')
                .replaceAll('{}', movie.title) ??
            '${movie.title} removed from watchlist.',
      );
    } else {
      await ref.read(watchlistProvider.notifier).add(movie);
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(
              context,
            )?.get('title_added_to_watchlist').replaceAll('{}', movie.title) ??
            '${movie.title} added to watchlist.',
      );
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

  /// Benzer/koleksiyon rayından seçilen yapım: bu sheet kapanır, yenisi açılır.
  void _openAnotherTitle(Movie m) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: m, service: widget.service),
    );
  }

  Future<void> _toggleSeason(int seasonNumber) async {
    await PrefsService.toggleSeason(widget.movie.id, seasonNumber);
    final updated = await PrefsService.getWatchedSeasons(widget.movie.id);
    if (mounted) setState(() => _watchedSeasons = updated);
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
                          DetailHeroRow(
                            movie: movie,
                            runtime: _details?['runtime'] as int? ?? 0,
                            communityScore: _communityScore,
                            onBlock: _confirmBlockMovie,
                            onRecommend: _openRecommendSheet,
                          ),
                          const SizedBox(height: 16),
                          DetailActionButtons(
                            movie: movie,
                            inWatchlist: inWatchlist,
                            hasTrailer: _trailerKey != null,
                            onToggleWatchlist: _toggleWatchlist,
                            onOpenTrailer: _openTrailer,
                          ),
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
                              const DetailSectionLabel('detail_where_to_watch'),
                              const SizedBox(height: 10),
                              DetailProvidersRow(providers: _providers),
                            ],
                            if (_cast.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const DetailSectionLabel('detail_cast'),
                              const SizedBox(height: 10),
                              DetailCastRow(
                                cast: _cast,
                                service: widget.service,
                              ),
                            ],
                            if (_keywords.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const DetailSectionLabel('detail_keywords'),
                              const SizedBox(height: 8),
                              KeywordsWrap(keywords: _keywords),
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
                            const DetailSectionLabel('detail_storyline'),
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
                            const DetailSectionLabel('detail_reviews'),
                            const SizedBox(height: 10),
                            ..._reviews
                                .take(3)
                                .map((r) => TmdbReviewCard(review: r)),
                          ],
                          if (_collection.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const DetailSectionLabel('detail_collection'),
                            const SizedBox(height: 10),
                            CollectionRow(
                              movies: _collection,
                              onMovieTap: _openAnotherTitle,
                            ),
                          ],
                          if (widget.movie.isTV && _extrasLoaded) ...[
                            const SizedBox(height: 20),
                            const DetailSectionLabel('detail_seasons'),
                            const SizedBox(height: 10),
                            SeasonsSection(
                              details: _details,
                              watchedSeasons: _watchedSeasons,
                              onToggle: _toggleSeason,
                            ),
                          ],
                          if (_similar.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const DetailSectionLabel('detail_similar'),
                            const SizedBox(height: 10),
                            SimilarTitlesRow(
                              movies: _similar,
                              onMovieTap: _openAnotherTitle,
                            ),
                          ],
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

  Widget _ratingSection(ThemePalette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionLabel('detail_rate_title'),
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
        const DetailSectionLabel('detail_your_review'),
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
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Sayaç yalnızca kendini yeniler; her tuş vuruşunda koca
                  // sheet'i setState ile yeniden çizmek gereksizdi.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _commentController,
                    builder: (_, value, _) => Text(
                      '${value.text.length} / 280',
                      style: TextStyle(color: c.dim, fontSize: 11),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _justSavedComment
                        ? null
                        : () async {
                            HapticFeedback.mediumImpact();
                            FocusScope.of(context).unfocus();
                            if (_currentRating != null) {
                              try {
                                final commentText = _commentController.text
                                    .trim();
                                await PrefsService.saveRating(
                                  movie: widget.movie,
                                  rating: _currentRating!,
                                  comment: commentText.isEmpty
                                      ? null
                                      : commentText,
                                  isSpoiler: _isSpoiler ? 1 : 0,
                                  isPrivate: _isPrivate ? 1 : 0,
                                );
                                ref
                                    .read(recommendationEngineProvider)
                                    .invalidateCache(
                                      isNegativeChange: _currentRating! <= 1,
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

                                  _showToast('$baseMsg$suffix');
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
                                  _showToast(
                                    AppLocalizations.of(context)
                                            ?.get('error_occurred_msg')
                                            .replaceAll('{}', '$e') ??
                                        'Error: $e',
                                    success: false,
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

    final canModerate = ref.read(authProvider).isLoggedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_friendsReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          const DetailSectionLabel('review_friends_title'),
          const SizedBox(height: 10),
          ..._friendsReviews.map(_buildReviewItem),
        ],
        if (_communityReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          const DetailSectionLabel('review_community_title'),
          const SizedBox(height: 10),
          ..._communityReviews.map(_buildReviewItem),
        ],
        // Uzun basma görünmez bir jest; altın vurgulu bilgi şeridi keşfettirir.
        if (canModerate) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.gold.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, color: c.gold, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr?.get('review_longpress_hint') ??
                        'Şikayet etmek veya engellemek için yoruma basılı tut',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          // Yazılmış bir yorum varken puanı sessizce kaldırmak yorumu da
          // götürür — kullanıcıdan onay al.
          if (_commentController.text.trim().isNotEmpty) {
            final confirmed = await _confirmRatingDelete();
            if (!confirmed) return;
          }
          final oldRating = _currentRating;
          await PrefsService.deleteRating(widget.movie.id, widget.movie.isTV);

          final recoSource = widget.movie.recoSource;
          if (recoSource != null && oldRating != null) {
            PrefsService.revertRecoOutcome(
              source: recoSource,
              liked: oldRating >= 2,
            ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
          }

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
          final commentText = _commentController.text.trim();
          await PrefsService.saveRating(
            movie: widget.movie,
            rating: rating,
            comment: commentText.isEmpty ? null : commentText,
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
            ).catchError((e) => debugPrint("Reco telemetry write failed: $e"));
          }

          setState(() {
            _currentRating = rating;
          });

          if (mounted && !ref.read(authProvider).isLoggedIn) {
            final tr = AppLocalizations.of(context);
            showAppToast(
              context,
              tr?.locale.languageCode == 'tr'
                  ? 'Puanınız yerel kaydedildi. Giriş yapınca eşitlenecektir.'
                  : 'Rating saved locally. Will sync when logged in.',
              success: false,
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
