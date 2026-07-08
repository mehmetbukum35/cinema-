import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/movie.dart';
import '../models/taste_dna.dart';
import '../services/api_service.dart';
import '../services/localization_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/taste_dna_presenter.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/entrance.dart';
import 'movie_detail_sheet.dart';

/// "Sinema DNA'n" — gizli öneri motorunu kullanıcının görebileceği, kişisel ve
/// paylaşılabilir bir kimliğe çeviren görsel eser. Uygulamanın "seni tanıyorum"
/// tezinin duygusal doruğu.
class TasteDnaScreen extends ConsumerStatefulWidget {
  const TasteDnaScreen({super.key});

  @override
  ConsumerState<TasteDnaScreen> createState() => _TasteDnaScreenState();
}

class _TasteDnaScreenState extends ConsumerState<TasteDnaScreen> {
  TasteDna? _dna;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = ref.read(authProvider).user?['id']?.toString();
      final dna = await ref
          .read(tasteDnaServiceProvider)
          .generate(userId: userId);
      // Snapshot'ı arka planda backend'e yayınla (public web kartı için).
      // Best-effort: başarısızsa ekran yine de görünür.
      if (ref.read(authProvider).isAuthenticated) {
        final cachedData = await PrefsService.getCachedDna();
        final currentHash = cachedData?['hash'];
        final lastPublishedHash = await PrefsService.getLastPublishedDnaHash();

        if (currentHash != null && currentHash != lastPublishedHash) {
          ref
              .read(apiServiceProvider)
              .publishTasteDna(dna.toJson())
              .then((_) => PrefsService.setLastPublishedDnaHash(currentHash))
              .catchError((e) => debugPrint('DNA publish failed: $e'));
        }
      }
      if (!mounted) return;
      setState(() {
        _dna = dna;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _share(TasteDnaPresenter p) {
    HapticFeedback.mediumImpact();
    final username = ref.read(authProvider).user?['username'] as String?;
    final lang = ref.read(localeProvider).languageCode;
    final profileUrl = (username != null && username.isNotEmpty)
        ? ApiService.webProfileUrl(username, lang: lang)
        : null;
    Share.share(p.shareText(profileUrl));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: CinematicBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(c, tr),
              Expanded(child: _body(c, tr)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemePalette c, AppLocalizations? tr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: c.ink),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: tr?.get('back') ?? 'Geri',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          const SizedBox(width: 4),
          Text(
            tr?.get('dna_title') ?? 'Sinema DNA\'n',
            style: TextStyle(
              color: c.ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (_dna != null && _dna!.isReady)
            IconButton(
              icon: Icon(Icons.ios_share_rounded, color: c.gold, size: 20),
              onPressed: () => _share(TasteDnaPresenter(tr, _dna!)),
              tooltip: tr?.get('dna_share') ?? 'Paylaş',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
        ],
      ),
    );
  }

  Widget _body(ThemePalette c, AppLocalizations? tr) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: c.gold, strokeWidth: 2.5),
            const SizedBox(height: 18),
            Text(
              tr?.get('dna_analyzing') ?? 'Zevkin analiz ediliyor…',
              style: TextStyle(color: c.dim, fontSize: 13.5),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return _centered(
        c,
        icon: Icons.error_outline_rounded,
        title: tr?.get('dna_error') ?? 'DNA oluşturulamadı',
        subtitle: tr?.get('browse_conn_error') ?? 'Bağlantı hatası.',
        action: _retryButton(c, tr),
      );
    }
    final dna = _dna!;
    if (!dna.isReady) {
      return _centered(
        c,
        icon: Icons.auto_awesome_rounded,
        title: tr?.get('dna_not_ready') ?? 'DNA\'n henüz oluşuyor',
        subtitle:
            tr?.get('dna_not_ready_desc') ??
            'Birkaç film daha oyla, zevk kimliğin ortaya çıksın.',
      );
    }

    final p = TasteDnaPresenter(tr, dna);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        EntranceFade(child: _archetypeCard(c, p)),
        if (p.themeChips.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel(c, tr?.get('dna_themes') ?? 'Tekrar eden temaların'),
          const SizedBox(height: 10),
          if (dna.themeEvidence.isNotEmpty)
            ...dna.themes.asMap().entries.map((entry) {
              final idx = entry.key;
              final t = entry.value;
              if (idx >= p.themeChips.length) return const SizedBox.shrink();
              final localizedTheme = p.themeChips[idx];
              final movies = dna.themeEvidence[t] ?? [];
              if (movies.isEmpty) return const SizedBox.shrink();
              return _themeEvidenceRow(c, localizedTheme, movies);
            })
          else
            _chips(c, p.themeChips, accent: true),
        ],
        if (p.genreChips.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel(c, tr?.get('dna_top_genres') ?? 'Zirvedeki türlerin'),
          const SizedBox(height: 10),
          _chips(c, p.genreChips),
        ],
        const SizedBox(height: 20),
        _sectionLabel(c, tr?.get('dna_signals') ?? 'Zevkinin imzası'),
        const SizedBox(height: 8),
        ...p.signals.map((s) => _signalRow(c, s)),
        if (p.accuracyText != null) ...[
          const SizedBox(height: 20),
          _accuracyCard(c, tr, p.accuracyText!),
        ],
        const SizedBox(height: 24),
        _shareButton(c, tr, p),
      ],
    );
  }

  Widget _archetypeCard(ThemePalette c, TasteDnaPresenter p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: c.isLight
              ? [
                  Color.lerp(c.card, c.gold, 0.12)!,
                  Color.lerp(c.card, c.crimson, 0.08)!,
                ]
              : [
                  c.gold.withValues(alpha: 0.18),
                  c.crimson.withValues(alpha: 0.14),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: c.gold.withValues(alpha: c.isLight ? 0.20 : 0.35),
        ),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        children: [
          Text(p.archetypeEmoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(
            (AppLocalizations.of(context)?.get('dna_you_are') ?? 'SEN')
                .toUpperCase(),
            style: TextStyle(
              color: c.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.archetypeName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.ink,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            p.archetypeEssence,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.dim, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemePalette c, String text) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            gradient: CinemaGradients.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          text,
          style: TextStyle(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _chips(ThemePalette c, List<String> items, {bool accent = false}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: accent ? c.gold.withValues(alpha: 0.12) : c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent ? c.gold.withValues(alpha: 0.4) : c.border,
            ),
          ),
          child: Text(
            t,
            style: TextStyle(
              color: accent ? c.goldDeep : c.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  static const _signalIcons = {
    'era': Icons.schedule_rounded,
    'depth': Icons.travel_explore_rounded,
    'critic': Icons.star_half_rounded,
    'blind': Icons.visibility_off_rounded,
    'shift': Icons.trending_up_rounded,
  };

  Widget _signalRow(ThemePalette c, TasteDnaSignal s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.isLight ? c.gold.withValues(alpha: 0.08) : c.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: c.isLight ? c.gold.withValues(alpha: 0.20) : c.border,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              _signalIcons[s.icon] ?? Icons.circle,
              size: 17,
              color: c.gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.text,
                style: TextStyle(color: c.ink, fontSize: 14, height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accuracyCard(ThemePalette c, AppLocalizations? tr, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.green.withValues(alpha: c.isLight ? 0.25 : 0.40),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: c.green, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareButton(
    ThemePalette c,
    AppLocalizations? tr,
    TasteDnaPresenter p,
  ) {
    return GestureDetector(
      onTap: () => _share(p),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: CinemaGradients.gold,
          borderRadius: BorderRadius.circular(16),
          boxShadow: c.isLight
              ? [
                  BoxShadow(
                    color: c.gold.withValues(alpha: 0.24),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 6),
                  ),
                ]
              : CinemaShadows.card,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.ios_share_rounded, color: Colors.black, size: 19),
            const SizedBox(width: 10),
            Text(
              tr?.get('dna_share_button') ?? 'DNA\'nı paylaş',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMovieDetail(BuildContext context, DnaMovieRef movieRef) {
    final movie = Movie(
      id: movieRef.id,
      title: movieRef.title,
      posterPath: movieRef.posterPath,
      isTV: movieRef.isTV,
      overview: '',
      voteAverage: 0,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(
        movie: movie,
        service: ref.read(tmdbServiceProvider),
      ),
    );
  }

  Widget _themeEvidenceRow(
    ThemePalette c,
    String theme,
    List<DnaMovieRef> movies,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  theme,
                  style: TextStyle(
                    color: c.goldDeep,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              itemBuilder: (context, index) {
                final m = movies[index];
                return GestureDetector(
                  onTap: () => _openMovieDetail(context, m),
                  child: Container(
                    width: 60,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: m.posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: m.posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (ctx, url) =>
                                  ColoredBox(color: c.surface),
                              errorWidget: (ctx, url, err) =>
                                  ColoredBox(color: c.surface),
                            )
                          : ColoredBox(color: c.surface),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _retryButton(ThemePalette c, AppLocalizations? tr) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextButton(
        onPressed: _generate,
        child: Text(
          tr?.get('retry') ?? 'Tekrar dene',
          style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _centered(
    ThemePalette c, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.gold, size: 44),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.4),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
