import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_cached_image.dart';
import '../../models/movie.dart';
import '../../models/cast_member.dart';
import '../../models/watch_provider.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../person_screen.dart';

/// "Nerede izlenir" sağlayıcı logoları rayı.
class DetailProvidersRow extends StatelessWidget {
  final List<WatchProvider> providers;
  const DetailProvidersRow({super.key, required this.providers});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: providers.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final p = providers[i];
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
                    child: AppCachedNetworkImage(
                      imageUrl: p.logoUrl,
                      fit: BoxFit.cover,
                      preset: AppImageCachePreset.avatar,
                      placeholder: (context, url) => ColoredBox(color: c.card),
                      errorWidget: (context, url, error) =>
                          ColoredBox(color: c.card),
                    ),
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
}

/// Oyuncu rayı: avatara dokununca kişi ekranına gider.
class DetailCastRow extends StatelessWidget {
  final List<CastMember> cast;
  final TmdbService service;
  const DetailCastRow({super.key, required this.cast, required this.service});

  Widget _avatarPlaceholder(BuildContext context, String name) {
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: cast.length,
        itemBuilder: (ctx, i) {
          final pal = ctx.c;
          final c = cast[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonScreen(
                    personId: c.id,
                    personName: c.name,
                    service: service,
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
                      child: AppCachedNetworkImage(
                        imageUrl: c.profileUrl,
                        fit: BoxFit.cover,
                        preset: AppImageCachePreset.avatar,
                        placeholder: (context, url) =>
                            _avatarPlaceholder(ctx, c.name),
                        errorWidget: (context, url, error) =>
                            _avatarPlaceholder(ctx, c.name),
                      ),
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
}

/// Benzer yapımlar rayı: dokununca üst sayfa mevcut sheet'i kapatıp
/// yenisini açar (onMovieTap).
class SimilarTitlesRow extends StatelessWidget {
  final List<Movie> movies;
  final void Function(Movie) onMovieTap;
  const SimilarTitlesRow({
    super.key,
    required this.movies,
    required this.onMovieTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: movies.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final s = movies[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onMovieTap(s);
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppCachedNetworkImage(
                  imageUrl: s.posterUrl,
                  fit: BoxFit.cover,
                  preset: AppImageCachePreset.poster,
                  placeholder: (context, url) => ColoredBox(color: c.card),
                  errorWidget: (context, url, error) =>
                      ColoredBox(color: c.card),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Koleksiyon (seri) rayı: yıl etiketiyle; dokununca onMovieTap.
class CollectionRow extends StatelessWidget {
  final List<Movie> movies;
  final void Function(Movie) onMovieTap;
  const CollectionRow({
    super.key,
    required this.movies,
    required this.onMovieTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: movies.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final m = movies[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onMovieTap(m);
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
                      child: AppCachedNetworkImage(
                        imageUrl: m.posterUrl,
                        fit: BoxFit.cover,
                        preset: AppImageCachePreset.poster,
                        placeholder: (context, url) =>
                            ColoredBox(color: c.card),
                        errorWidget: (context, url, error) =>
                            ColoredBox(color: c.card),
                      ),
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
}
