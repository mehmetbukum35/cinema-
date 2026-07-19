import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'movie_detail/comment_editor.dart';
import 'movie_detail/detail_actions.dart';
import 'movie_detail/detail_section_label.dart';
import 'movie_detail/detail_sheet_shell.dart';
import 'movie_detail/detail_hero_row.dart';
import 'movie_detail/detail_action_buttons.dart';
import 'movie_detail/detail_media_rows.dart';
import 'movie_detail/detail_text_sections.dart';
import 'movie_detail/friends_reviews_section.dart';
import 'movie_detail/rating_section.dart';
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

  /// "Arkadaşına Öner" akışı (bkz. movie_detail/detail_actions.dart).
  /// Statik delege: browse/swipe/search kartları da buradan çağırır.
  static Future<void> showRecommendSheet({
    required BuildContext context,
    required WidgetRef ref,
    required Movie movie,
  }) => showRecommendSheetFor(context: context, ref: ref, movie: movie);

  /// Yapımı gizleme onayı (bkz. movie_detail/detail_actions.dart).
  static void confirmBlockMovie({
    required BuildContext context,
    required WidgetRef ref,
    required Movie movie,
    required VoidCallback onBlocked,
  }) => confirmBlockMovieDialog(
    context: context,
    ref: ref,
    movie: movie,
    onBlocked: onBlocked,
  );

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

  // ─── Veri yükleme fazları ─────────────────────────────────────────────────

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

  // ─── Moderasyon ───────────────────────────────────────────────────────────

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

  // ─── Aksiyonlar ───────────────────────────────────────────────────────────

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
      final added =
          AppLocalizations.of(
            context,
          )?.get('title_added_to_watchlist').replaceAll('{}', movie.title) ??
          '${movie.title} added to watchlist.';
      // Henüz çıkmamış yapım için çıkış günü hatırlatıcısı sessizce
      // planlanıyordu (WatchlistNotifier.add → scheduleReleaseReminder) ama
      // kullanıcıya hiç söylenmiyordu. Koşul, NotificationService'in
      // planlama kuralıyla aynı: çıkış günü 10:00 hâlâ gelecekteyse.
      final release = DateTime.tryParse(movie.releaseDate ?? '');
      final upcoming =
          release != null &&
          DateTime(
            release.year,
            release.month,
            release.day,
            10,
          ).isAfter(DateTime.now());
      final reminderNote = upcoming
          ? ' ${AppLocalizations.of(context)?.get('watchlist_release_reminder_note') ?? 'Çıktığı gün sana haber vereceğiz 🔔'}'
          : '';
      showAppToast(context, '$added$reminderNote');
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
    confirmBlockMovieDialog(
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

  Future<void> _openRecommendSheet() async {
    await showRecommendSheetFor(
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

  // ─── Puan / yorum iş mantığı ──────────────────────────────────────────────

  /// Puan butonuna dokunuş: aktif puana tekrar basmak puanı (ve yorumu,
  /// onayla) kaldırır; yeni puan kaydedilir, telemetri ve sync tetiklenir.
  Future<void> _handleRatingTap(int rating) async {
    HapticFeedback.lightImpact();
    final active = _currentRating == rating;
    if (active) {
      // Yazılmış bir yorum varken puanı sessizce kaldırmak yorumu da
      // götürür — kullanıcıdan onay al.
      if (_commentController.text.trim().isNotEmpty) {
        final confirmed = await confirmRatingDelete(context);
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
  }

  /// Yorumu (mevcut puanla birlikte) kaydeder; başarıda 2 sn "kaydedildi"
  /// durumu gösterilir, misafir kullanıcı yerel-kayıt notuyla bilgilendirilir.
  Future<void> _saveComment() async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    if (_currentRating == null) return;
    try {
      final commentText = _commentController.text.trim();
      await PrefsService.saveRating(
        movie: widget.movie,
        rating: _currentRating!,
        comment: commentText.isEmpty ? null : commentText,
        isSpoiler: _isSpoiler ? 1 : 0,
        isPrivate: _isPrivate ? 1 : 0,
      );
      if (!mounted) return;
      ref
          .read(recommendationEngineProvider)
          .invalidateCache(isNegativeChange: _currentRating! <= 1)
          .catchError((_) => {});
      ref.invalidate(statsProvider);
      ref.read(syncServiceProvider).sync().catchError((_) => {});
      ref
          .read(socialProvider.notifier)
          .loadActivityFeed()
          .catchError((_) => {});

      if (mounted) {
        setState(() {
          _justSavedComment = true;
        });
        final isGuest = !ref.read(authProvider).isLoggedIn;
        final baseMsg =
            AppLocalizations.of(context)?.get('review_saved_successfully') ??
            'Review saved successfully';
        final suffix = isGuest
            ? (AppLocalizations.of(context)?.locale.languageCode == 'tr'
                  ? ' (Yerel kaydedildi, giriş yapınca eşitlenecektir.)'
                  : ' (Saved locally, will sync when logged in.)')
            : '';

        _showToast('$baseMsg$suffix');
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
        _showToast(
          AppLocalizations.of(
                context,
              )?.get('error_occurred_msg').replaceAll('{}', '$e') ??
              'Error: $e',
          success: false,
        );
      }
    }
  }

  // ─── Kompozisyon ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final watchlistState = ref.watch(watchlistProvider);
    final inWatchlist = watchlistState.maybeWhen(
      data: (list) => list.any((m) => m.id == movie.id && m.isTV == movie.isTV),
      orElse: () => false,
    );
    final tagline = _details?['tagline'] as String? ?? '';

    return DetailSheetShell(
      contentBuilder: (ctx, ctrl) {
        final c = ctx.c;
        return SingleChildScrollView(
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
              RatingSection(
                currentRating: _currentRating,
                onTap: _handleRatingTap,
              ),
              if (_currentRating != null)
                CommentEditor(
                  controller: _commentController,
                  isSpoiler: _isSpoiler,
                  isPrivate: _isPrivate,
                  justSaved: _justSavedComment,
                  onToggleSpoiler: () =>
                      setState(() => _isSpoiler = !_isSpoiler),
                  onTogglePrivate: () =>
                      setState(() => _isPrivate = !_isPrivate),
                  onSave: _saveComment,
                ),
              FriendsReviewsSection(
                loading: _loadingFriendsReviews,
                friendsReviews: _friendsReviews,
                communityReviews: _communityReviews,
                hasUserRated: _currentRating != null,
                canModerate: ref.read(authProvider).isLoggedIn,
                onReport: _reportReview,
                onBlock: _blockReviewer,
              ),
              if (tagline.isNotEmpty) ...[
                const SizedBox(height: 12),
                TaglineText(tagline: tagline),
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
                  DetailCastRow(cast: _cast, service: widget.service),
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
                StorylineCard(overview: movie.overview),
              ],
              if (_reviews.isNotEmpty) ...[
                const SizedBox(height: 20),
                const DetailSectionLabel('detail_reviews'),
                const SizedBox(height: 10),
                ..._reviews.take(3).map((r) => TmdbReviewCard(review: r)),
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
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            ],
          ),
        );
      },
    );
  }
}
