import 'package:flutter/material.dart';
import '../widgets/app_cached_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_sheet.dart';

class PersonScreen extends StatefulWidget {
  final int personId;
  final String personName;
  final TmdbService service;

  const PersonScreen({
    super.key,
    required this.personId,
    required this.personName,
    required this.service,
  });

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Map<String, dynamic>? _personDetails;
  List<Movie> _movies = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait([
        widget.service.getPersonMovies(widget.personId),
        widget.service.getPersonDetails(widget.personId),
      ]);
      if (!mounted) return;
      setState(() {
        _movies = results[0] as List<Movie>;
        _personDetails = results[1] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Widget _bioSection() {
    final c = context.c;
    final d = _personDetails!;
    final birthday = d['birthday'] as String? ?? '';
    final place = d['place_of_birth'] as String? ?? '';
    final bio = d['biography'] as String? ?? '';
    if (birthday.isEmpty && place.isEmpty && bio.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (birthday.isNotEmpty || place.isNotEmpty) ...[
            Row(
              children: [
                if (birthday.isNotEmpty) ...[
                  Icon(Icons.cake_outlined, color: c.dim, size: 13),
                  const SizedBox(width: 4),
                  Text(birthday, style: TextStyle(color: c.dim, fontSize: 12)),
                ],
                if (birthday.isNotEmpty && place.isNotEmpty)
                  const SizedBox(width: 12),
                if (place.isNotEmpty) ...[
                  Icon(Icons.location_on_outlined, color: c.dim, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (bio.isNotEmpty) ...[
            Text(
              bio.length > 500 ? '${bio.substring(0, 500)}…' : bio,
              style: TextStyle(
                color: c.isLight ? const Color(0xFF3A352E) : Colors.white70,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Divider(color: c.border, height: 1),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              return Text(
                AppLocalizations.of(context)?.get('filmography') ??
                    'FILMOGRAPHY',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _openDetail(Movie movie) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: widget.service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        title: Text(
          widget.personName,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.dim),
              ),
            )
          : _loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, color: c.dim, size: 34),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)?.get('browse_conn_error') ??
                        'Bağlantınızı kontrol edip tekrar deneyin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.dim, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _load,
                    child: Text(
                      AppLocalizations.of(context)?.get('retry') ??
                          'Tekrar dene',
                    ),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                if (_personDetails != null)
                  SliverToBoxAdapter(child: _bioSection()),
                if (_movies.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        AppLocalizations.of(
                              context,
                            )?.get('search_no_results') ??
                            'İçerik bulunamadı',
                        style: TextStyle(color: c.dim, fontSize: 14),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.62,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _MovieCard(
                          movie: _movies[i],
                          onTap: () => _openDetail(_movies[i]),
                        ),
                        childCount: _movies.length,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const _MovieCard({required this.movie, required this.onTap});

  // Poster üstü (koyu degrade) renkleri — her iki temada sabit kalır.
  static const _gold = AppColors.gold;
  static const _overlayDim = Color(0xFFB9B9C2);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppCachedNetworkImage(
              imageUrl: movie.posterUrl,
              fit: BoxFit.cover,
              preset: AppImageCachePreset.poster,
              placeholder: (ctx, url) => _placeholder(context),
              errorWidget: (ctx, url, err) => _placeholder(context),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: _gold, size: 10),
                      const SizedBox(width: 2),
                      Text(
                        movie.voteAverage.toStringAsFixed(1),
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        movie.isTV
                            ? (AppLocalizations.of(
                                        context,
                                      )?.locale.languageCode ==
                                      'tr'
                                  ? 'D'
                                  : 'TV')
                            : (AppLocalizations.of(
                                        context,
                                      )?.locale.languageCode ==
                                      'tr'
                                  ? 'F'
                                  : 'M'),
                        style: const TextStyle(
                          color: _overlayDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.card,
      child: Center(
        child: Icon(Icons.movie_rounded, color: c.textFaint, size: 24),
      ),
    );
  }
}
