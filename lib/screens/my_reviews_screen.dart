import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/sync_service.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/spring_button.dart';
import 'movie_detail_sheet.dart';

/// "Yorumlarım": kullanıcının yorum yazdığı tüm yapımlar tek listede.
/// Veri tamamen yerel SQLite'tan gelir (offline çalışır); yorum silme
/// puanı korur ve updated_at üzerinden sunucuya senkronlanır.
class MyReviewsScreen extends ConsumerStatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  ConsumerState<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends ConsumerState<MyReviewsScreen> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await PrefsService.getCommentedRatings();
    if (mounted) setState(() => _items = rows);
  }

  Movie _movieOf(Map<String, dynamic> m) {
    List<int> genreIds = const [];
    final rawGenres = m['genre_ids'];
    if (rawGenres is String && rawGenres.isNotEmpty) {
      try {
        genreIds = (jsonDecode(rawGenres) as List<dynamic>)
            .whereType<int>()
            .toList();
      } catch (_) {}
    }
    return Movie(
      id: m['movie_id'] as int,
      title: m['title'] as String? ?? '',
      posterPath: m['poster_path'] as String?,
      backdropPath: m['backdrop_path'] as String?,
      overview: m['overview'] as String? ?? '',
      voteAverage: (m['vote_average'] as num? ?? 0).toDouble(),
      releaseDate: m['release_date'] as String?,
      isTV: (m['is_tv'] as int) == 1,
      genreIds: genreIds,
      popularity: (m['popularity'] as num? ?? 0).toDouble(),
    );
  }

  Future<void> _openDetail(Movie movie) async {
    HapticFeedback.lightImpact();
    final service = ref.read(tmdbServiceProvider);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: service),
    );
    // Detayda yorum düzenlenmiş/silinmiş olabilir.
    _load();
  }

  Future<void> _confirmDeleteComment(Map<String, dynamic> item) async {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(
          tr?.get('review_delete') ?? 'Yorumu sil',
          style: TextStyle(color: c.ink, fontSize: 16),
        ),
        content: Text(
          tr?.get('review_delete_confirm') ??
              'Bu yorum silinsin mi? Puanın korunacak.',
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
              tr?.get('delete') ?? 'Sil',
              style: TextStyle(color: c.rBerbat, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await PrefsService.deleteComment(
      item['movie_id'] as int,
      (item['is_tv'] as int) == 1,
    );
    ref.read(syncServiceProvider).sync().catchError((_) => {});
    if (!mounted) return;
    final c2 = context.c;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)?.get('review_deleted') ??
              'Yorum silindi',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: c2.green,
        duration: const Duration(seconds: 2),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final items = _items;

    return CinematicBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: c.ink,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: tr?.get('semantics_go_back') ?? 'Back',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr?.get('my_reviews_title') ?? 'Yorumlarım',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                tr?.get('my_reviews_subtitle') ?? 'Yazdığın tüm yorumlar tek yerde',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        body: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? _emptyState(c, tr)
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: items.length,
                itemBuilder: (_, i) => _reviewCard(items[i], c, tr),
              ),
      ),
    );
  }

  Widget _emptyState(ThemePalette c, AppLocalizations? tr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rate_review_outlined, color: c.dim, size: 42),
          const SizedBox(height: 12),
          Text(
            tr?.get('my_reviews_empty') ?? 'Henüz hiç yorum yazmadın.',
            style: TextStyle(
              color: c.dim,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(
    Map<String, dynamic> item,
    ThemePalette c,
    AppLocalizations? tr,
  ) {
    final movie = _movieOf(item);
    final rating = (item['rating'] as int?)?.clamp(0, 3) ?? 0;
    final comment = item['comment'] as String? ?? '';
    final isSpoiler = (item['is_spoiler'] as int? ?? 0) == 1;
    final isPrivate = (item['is_private'] as int? ?? 0) == 1;
    final updatedAt = item['updated_at'] as int? ?? 0;
    final date = updatedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(updatedAt)
        : null;

    final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
    final ratingKeys = [
      'profile_berbat',
      'profile_eh',
      'profile_iyi',
      'profile_harika',
    ];
    const ratingFallbacks = ['Berbat', 'Eh', 'İyi', 'Harika'];
    final badgeColor = ratingColors[rating];
    final badgeText = tr?.get(ratingKeys[rating]) ?? ratingFallbacks[rating];

    return SpringButton(
      onTap: () => _openDetail(movie),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 42,
                    height: 63,
                    child: movie.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: c.border,
                            child: Icon(
                              Icons.movie_outlined,
                              color: c.dim,
                              size: 18,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(
                            badgeText,
                            badgeColor,
                            icon: Icons.star_rounded,
                          ),
                          if (isSpoiler)
                            _chip(
                              tr?.get('review_spoiler') ?? 'Spoiler İçerir',
                              c.rBerbat,
                              icon: Icons.warning_amber_rounded,
                            ),
                          if (isPrivate)
                            _chip(
                              tr?.get('review_private') ?? 'Gizli',
                              c.gold,
                              icon: Icons.lock_rounded,
                            ),
                        ],
                      ),
                      if (date != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}',
                          style: TextStyle(color: c.dim, fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr?.get('review_delete') ?? 'Yorumu sil',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: c.dim,
                    size: 18,
                  ),
                  onPressed: () => _confirmDeleteComment(item),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.borderSoft.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                comment,
                style: TextStyle(color: c.ink, fontSize: 13, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color, {required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
