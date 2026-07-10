import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/share_helper.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'spring_button.dart';

class WrappedModal extends StatefulWidget {
  final Map<String, dynamic> stats;
  final String? username;

  const WrappedModal({super.key, required this.stats, this.username});

  @override
  State<WrappedModal> createState() => _WrappedModalState();
}

class _WrappedModalState extends State<WrappedModal> {
  final PageController _pageController = PageController();
  final GlobalKey _shareCardKey = GlobalKey();
  int _currentPage = 0;
  final int _currentYear = DateTime.now().year;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _shareRecap(BuildContext anchorContext) async {
    final l10n = AppLocalizations.of(context);
    final failureMessage = l10n?.get('profile_share_failed') ??
        'Paylaşım açılamadı. Lütfen tekrar deneyin.';
    final total = widget.stats['total'] as int? ?? 0;
    final topGenres = widget.stats['topGenres'] as List<dynamic>? ?? [];

    final genreNames = topGenres
        .map((id) => PrefsService.genreName(id as int))
        .toList();

    final profileUrl = widget.username != null && widget.username!.isNotEmpty
        ? ApiService.webProfileUrl(
            widget.username!,
            lang: l10n?.locale.languageCode ?? 'tr',
          )
        : null;

    final genresText = genreNames
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    final linkSection = profileUrl != null
        ? (l10n?.get('recap_share_link_yes') ?? 'Check out my profile: {url}')
              .replaceAll('{url}', profileUrl)
        : (l10n?.get('recap_share_link_no') ??
              'Rate your titles and see your recap!');

    final shareText =
        (l10n?.get('recap_share_template') ??
                '🎬 My {year} Cinema Recap on Ne İzlesem!\n\nI rated {total} movies & shows this year! 🍿\nMy Top Genres:\n{genres}\n\n{link_section}\n#NeIzlesem #Wrapped{year}')
            .replaceAll('{year}', _currentYear.toString())
            .replaceAll('{total}', total.toString())
            .replaceAll('{genres}', genresText)
            .replaceAll('{link_section}', linkSection);

    final shareOrigin = sharePositionOriginFrom(anchorContext);

    try {
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final png = XFile.fromData(
            byteData.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'cinema_recap_$_currentYear.png',
          );
          if (!mounted) return;
          await shareFiles(
            context: context,
            sharePositionOrigin: shareOrigin,
            files: [png],
            text: shareText,
            failureMessage: failureMessage,
          );
          return;
        }
      }
    } catch (e, st) {
      debugPrint('PNG recap share failed, falling back to text: $e\n$st');
    }

    if (!mounted) return;
    await shareMessage(
      context: context,
      sharePositionOrigin: shareOrigin,
      message: shareText,
      failureMessage: failureMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // PageView content
            PageView(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                _buildIntroPage(c),
                _buildStatsPage(c),
                _buildGenresPage(c),
                _buildFavouritesPage(c),
                _buildSharePage(c),
              ],
            ),
            // Progress indicators at top
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Row(
                children: List.generate(5, (index) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: _currentPage >= index
                            ? const Color(0xFFFF2E93)
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Close button at top right
            Positioned(
              top: 30,
              right: 12,
              child: Semantics(
                label: 'Kapat',
                button: true,
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 28,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Slide 1: Welcome Intro
  Widget _buildIntroPage(ThemePalette c) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F0C20), Color(0xFF15102A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF2E93), Color(0xFFFF8A00)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2E93).withValues(alpha: 0.4),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 36),
          Text(
            (AppLocalizations.of(context)?.get('recap_journey_title') ??
                    'Your {}\nCinema Journey')
                .replaceAll('{}', _currentYear.toString()),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.get('recap_journey_desc') ??
                'We compiled all your ratings from the past year. Swipe to discover your recap!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)?.get('recap_swipe_continue') ??
                    'Swipe to continue',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white38,
                size: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Slide 2: Rating Statistics
  Widget _buildStatsPage(ThemePalette c) {
    final total = widget.stats['total'] as int? ?? 0;

    final berbat = widget.stats['berbat'] as int? ?? 0;
    final eh = widget.stats['eh'] as int? ?? 0;
    final iyi = widget.stats['iyi'] as int? ?? 0;
    final harika = widget.stats['harika'] as int? ?? 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF15102A), Color(0xFF0C1D2A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)?.get('recap_what_watched') ??
                'What Did You Watch?',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            (AppLocalizations.of(context)?.get('recap_total_titles') ??
                    '{} Titles')
                .replaceAll('{}', total.toString()),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)?.get('recap_rated_sub') ??
                'rated and reviewed!',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 40),
          _buildStatRow(
            AppLocalizations.of(context)?.get('recap_stat_amazing') ??
                'Amazing 🌟',
            harika,
            total,
            c.green,
          ),
          _buildStatRow(
            AppLocalizations.of(context)?.get('recap_stat_good') ?? 'Good 👍',
            iyi,
            total,
            c.gold,
          ),
          _buildStatRow(
            AppLocalizations.of(context)?.get('recap_stat_meh') ?? 'Meh 😐',
            eh,
            total,
            c.rEh,
          ),
          _buildStatRow(
            AppLocalizations.of(context)?.get('recap_stat_awful') ?? 'Awful 👎',
            berbat,
            total,
            c.rBerbat,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int count, int total, Color color) {
    final double percent = total > 0 ? count / total : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // Slide 3: Top Genres
  Widget _buildGenresPage(ThemePalette c) {
    final topGenres = widget.stats['topGenres'] as List<dynamic>? ?? [];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0C1D2A), Color(0xFF1D0E1A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)?.get('recap_top_genres') ??
                'YOUR TOP GENRES',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
          if (topGenres.isEmpty)
            Text(
              AppLocalizations.of(context)?.get('recap_no_taste_data') ??
                  'Not enough taste data yet.',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            )
          else
            ...topGenres.asMap().entries.map((entry) {
              final index = entry.key;
              final genreId = entry.value as int;
              final name = PrefsService.genreName(genreId);

              final gradients = [
                const [Color(0xFFFF2E93), Color(0xFFFF8A00)],
                const [Color(0xFF8A2387), Color(0xFFE94057)],
                const [Color(0xFF2193B0), Color(0xFF6DD5ED)],
              ];

              final colorGrad = gradients[index % gradients.length];

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colorGrad),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colorGrad[0].withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      '#${index + 1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.local_activity_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // Slide 4: Favorite Movies
  Widget _buildFavouritesPage(ThemePalette c) {
    final ratedMovies = widget.stats['ratedMovies'] as List<dynamic>? ?? [];
    final favourites = ratedMovies
        .where((item) => item['rating'] == 3)
        .map((item) => item['movie'] as Movie)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1D0E1A), Color(0xFF0F0C20)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)?.get('recap_highest_rated') ??
                'YOUR HIGHEST RATED TITLES',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)?.get('recap_rated_amazing') ??
                'Rated as Amazing',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          if (favourites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                AppLocalizations.of(context)?.get('recap_no_amazing_yet') ??
                    "You haven't rated any title \"Amazing\" yet.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: favourites.length,
                itemBuilder: (context, index) {
                  final movie = favourites[index];
                  return Container(
                    width: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: movie.posterUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: movie.posterUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) =>
                                        Container(color: Colors.white10),
                                  )
                                : Container(color: Colors.white10),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          movie.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // Slide 5: Share Summary Card
  Widget _buildSharePage(ThemePalette c) {
    final total = widget.stats['total'] as int? ?? 0;
    final topGenres = widget.stats['topGenres'] as List<dynamic>? ?? [];
    final genreNames = topGenres
        .map((id) => PrefsService.genreName(id as int))
        .toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F0C20), Color(0xFFFF2E93)],
          begin: Alignment.topCenter,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Graphic wrapped visual card
          RepaintBoundary(
            key: _shareCardKey,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFFF2E93).withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF2E93).withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.movie_filter_rounded,
                        color: Color(0xFFFF2E93),
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'cinema+',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    (AppLocalizations.of(context)?.get('recap_share_title') ??
                            'MY {} CINEMA JOURNEY')
                        .replaceAll('{}', _currentYear.toString()),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.movie_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (AppLocalizations.of(context)?.get('recap_share_sub') ??
                                'rated {} titles')
                            .replaceAll('{}', total.toString()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (genreNames.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10, height: 20),
                    Text(
                      AppLocalizations.of(context)?.get('recap_share_genres') ??
                          'My Favorite Genres:',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: genreNames.map((name) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF2E93,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFFFF2E93,
                              ).withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          // Share Button
          Builder(
            builder: (shareBtnContext) => SpringButton(
              onTap: () => _shareRecap(shareBtnContext),
              child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF2E93), Color(0xFFFF8A00)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF2E93).withValues(alpha: 0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.share_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)?.get('recap_share_button') ??
                        'Share Your Recap',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}
