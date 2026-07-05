import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'spring_button.dart';

class WrappedModal extends StatefulWidget {
  final Map<String, dynamic> stats;
  final String? username;

  const WrappedModal({
    super.key,
    required this.stats,
    this.username,
  });

  @override
  State<WrappedModal> createState() => _WrappedModalState();
}

class _WrappedModalState extends State<WrappedModal> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _currentYear = DateTime.now().year;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _shareRecap() {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    final total = widget.stats['total'] as int? ?? 0;
    final topGenres = widget.stats['topGenres'] as List<dynamic>? ?? [];
    
    final genreNames = topGenres.map((id) => PrefsService.genreName(id as int)).toList();
    
    final String shareText;
    final profileUrl = widget.username != null && widget.username!.isNotEmpty
        ? '${ApiService.webProfileBaseUrl}/${widget.username}'
        : null;

    if (isTr) {
      shareText = '🎬 Ne İzlesem? $_currentYear Sinematik Özetim!\n\n'
          'Bu yıl tam $total film/dizi oyladım! 🍿\n'
          'Favori Türlerim:\n'
          '${genreNames.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\n\n'
          '${profileUrl != null ? 'Profilime ve oylarıma göz at: $profileUrl' : 'Sen de oylarını ver, özetini gör!'}\n'
          '#NeIzlesem #Wrapped$_currentYear';
    } else {
      shareText = '🎬 My $_currentYear Cinema Recap on Ne İzlesem!\n\n'
          'I rated $total movies & shows this year! 🍿\n'
          'My Top Genres:\n'
          '${genreNames.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\n\n'
          '${profileUrl != null ? 'Check out my profile: $profileUrl' : 'Rate your titles and see your recap!'}\n'
          '#NeIzlesem #Wrapped$_currentYear';
    }

    Share.share(shareText);
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
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 28),
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
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
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 36),
          Text(
            isTr ? '$_currentYear Sinema\nYolculuğun' : 'Your $_currentYear\nCinema Journey',
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
            isTr
                ? 'Geçtiğimiz yıl boyunca yaptığın değerlendirmeleri senin için derledik. Keşfetmek için kaydır!'
                : 'We compiled all your ratings from the past year. Swipe to discover your recap!',
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
                isTr ? 'Kaydır' : 'Swipe to continue',
                style: const TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white38, size: 14),
            ],
          ),
        ],
      ),
    );
  }

  // Slide 2: Rating Statistics
  Widget _buildStatsPage(ThemePalette c) {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
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
            isTr ? 'Neler İzledin?' : 'What Did You Watch?',
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            isTr ? 'Tam $total Yapım' : '$total Titles',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isTr ? 'oyladın ve puanladın!' : 'rated and reviewed!',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 40),
          _buildStatRow(isTr ? 'Harika 🌟' : 'Amazing 🌟', harika, total, c.green),
          _buildStatRow(isTr ? 'İyi 👍' : 'Good 👍', iyi, total, c.gold),
          _buildStatRow(isTr ? 'Eh 😐' : 'Meh 😐', eh, total, c.rEh),
          _buildStatRow(isTr ? 'Berbat 👎' : 'Awful 👎', berbat, total, c.rBerbat),
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
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              Text('$count', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
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
            isTr ? 'EN SEVDİĞİN TÜRLER' : 'YOUR TOP GENRES',
            style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 24),
          if (topGenres.isEmpty)
            Text(
              isTr ? 'Henüz yeterli zevk profili oluşmadı.' : 'Not enough taste data yet.',
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(Icons.local_activity_rounded, color: Colors.white70, size: 20),
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
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
            isTr ? 'EN BEĞENDİĞİN YAPIMLAR' : 'YOUR HIGHEST RATED TITLES',
            style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          Text(
            isTr ? 'Harika Puan Verdiklerin' : 'Rated as Amazing',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (favourites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                isTr ? 'Henüz hiçbir filme "Harika" dememişsin.' : 'You haven\'t rated any movie "Amazing" yet.',
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
                                    errorWidget: (context, url, error) => Container(color: Colors.white10),
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
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    final total = widget.stats['total'] as int? ?? 0;
    final topGenres = widget.stats['topGenres'] as List<dynamic>? ?? [];
    final genreNames = topGenres.map((id) => PrefsService.genreName(id as int)).toList();

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
          Container(
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
                    Icon(Icons.movie_filter_rounded, color: Color(0xFFFF2E93), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'cinema+',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  isTr ? '$_currentYear SİNEMA YOLCULUĞUM' : 'MY $_currentYear CINEMA JOURNEY',
                  style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.movie_outlined, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      isTr ? '$total yapım oyladım' : 'rated $total titles',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (genreNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 20),
                  Text(
                    isTr ? 'Favori Türlerim:' : 'My Favorite Genres:',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: genreNames.map((name) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2E93).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF2E93).withValues(alpha: 0.4), width: 1),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 40),
          // Share Button
          SpringButton(
            onTap: _shareRecap,
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
                  const Icon(Icons.share_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isTr ? 'Özetini Paylaş' : 'Share Your Recap',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
