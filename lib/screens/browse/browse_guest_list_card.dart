import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie.dart';
import '../../services/db_helper.dart';
import '../../services/localization_service.dart';
import '../../services/prefs/signup_attribution.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_cached_image.dart';
import '../login_screen.dart';

/// Misafirin kendi beğendiği yapımların önizlemesi.
///
/// Sunucudaki genel profil kartlarıyla AYNI ölçüt kullanılır (rating >= 2,
/// gizli değil) — kart yan yana durduğu gerçek listelerle aynı şeyi
/// göstermezse kıyas yalan olur.
class GuestListPreview {
  final List<Movie> posters;
  final int likedCount;

  const GuestListPreview({required this.posters, required this.likedCount});

  /// Gösterilecek bir şey yoksa `null` döner — ve o zaman davet de yoktur.
  static Future<GuestListPreview?> load() async {
    final ratings = await DatabaseHelper().getRatings();

    // Sayım ve afiş listesi KASITLI olarak iki ayrı süzgeçten geçer.
    // Sunucudaki `liked_titles` alt sorgusu (rating >= 2, gizli değil) afiş
    // aramaz — afişi eksik bir yapım (tamamlanmamış TMDB verisi) yine de
    // "beğenilmiş" sayılır. Sayımı afiş şartına bağlarsak misafirin sayısı
    // sunucununkinden daha katı olur ve yan yana durduğu gerçek kartlarla
    // kıyas dürüst kalmaz. Bu yüzden: eşiği ve `likedCount`'u afişsiz
    // `qualifying` listesi belirler; `posters` ondan türeyen alt kümedir.
    // Bu iki listeyi tek süzgeçte "sadeleştirmeyin" — o an bu yorum haklı
    // çıkan hatayı geri getirir.
    final qualifying = <Movie>[];
    for (final row in ratings) {
      final rating = row['rating'];
      final isPrivate = row['is_private'];
      if (rating is! int || rating < 2) continue;
      if (isPrivate is int && isPrivate == 1) continue;
      final movie = row['movie'];
      if (movie is! Movie) continue;
      qualifying.add(movie);
    }
    if (qualifying.length < 3) return null;

    final posters = qualifying
        .where((movie) => (movie.posterPath ?? '').isNotEmpty)
        .take(4)
        .toList();
    // Eşik geçildi ama gösterecek tek bir afiş yoksa: boş afiş sırasıyla
    // kart göstermek, kart hiç göstermemekten daha kötü bir davettir.
    if (posters.isEmpty) return null;

    return GuestListPreview(posters: posters, likedCount: qualifying.length);
  }
}

/// "Popüler Listeler" rayının ilk kartı: kullanıcının kendi listesi, henüz
/// yayında değil. Sıra numarası yok; altın tonlu kenarlık onu sıralamanın
/// bir parçası değil, bir davet yapar.
class BrowseGuestListCard extends StatelessWidget {
  const BrowseGuestListCard({super.key, required this.preview});

  final GuestListPreview preview;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        // Atıf dokunuşta yazılır: kayıt buradan saatler sonra tamamlanabilir.
        PrefsSignupAttribution.remember('ghost_card');
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      },
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.gold.withValues(alpha: 0.45), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.radio_button_unchecked, size: 16, color: c.dim),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr?.get('browse_guest_list_title') ?? 'Senin Listen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        tr?.get('browse_guest_list_unpublished') ??
                            'yayında değil',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (final movie in preview.posters) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: AppCachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        width: 38,
                        height: 58,
                        fit: BoxFit.cover,
                        preset: AppImageCachePreset.avatar,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr?.get('browse_guest_list_cta') ?? 'Giriş yap ve yayınla',
              style: TextStyle(
                color: c.gold,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
