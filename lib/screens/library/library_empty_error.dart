import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class LibraryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const LibraryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.dim.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: c.dim, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              desc,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryEmptyWatchlist extends StatelessWidget {
  const LibraryEmptyWatchlist({super.key});

  @override
  Widget build(BuildContext context) {
    return LibraryEmptyState(
      icon: Icons.bookmark_border_rounded,
      title: AppLocalizations.of(context)?.get('watchlist_empty_title') ?? '',
      desc: AppLocalizations.of(context)?.get('watchlist_empty_desc') ?? '',
    );
  }
}

class LibraryEmptyRated extends StatelessWidget {
  const LibraryEmptyRated({super.key});

  @override
  Widget build(BuildContext context) {
    return LibraryEmptyState(
      icon: Icons.star_border_rounded,
      title:
          AppLocalizations.of(context)?.get('library_rated_empty_title') ??
          'Henüz değerlendirme yok',
      desc:
          AppLocalizations.of(context)?.get('library_rated_empty_desc') ??
          'Film ve dizileri puanladıkça geçmişin burada birikir.',
    );
  }
}

class LibraryErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const LibraryErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: c.red, size: 48),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(
                  context,
                )?.get('an_error_occurred_while_loadin') ??
                'An error occurred while loading.',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.get('browse_conn_error') ??
                'İnternet bağlantınızı kontrol edip tekrar deneyin.',
            style: TextStyle(color: c.dim, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              onRetry();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)?.get('browse_retry') ?? '',
            ),
          ),
        ],
      ),
    );
  }
}
