import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class ResultsErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const ResultsErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.red.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.wifi_off_rounded, color: c.red, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)?.get('browse_error') ??
                  'An error occurred',
              style: TextStyle(
                color: c.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppLocalizations.of(context)?.get('browse_conn_error') ??
                    'Connection error. Please check your internet.',
                style: TextStyle(color: c.dim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
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
                AppLocalizations.of(context)?.get('browse_retry') ?? 'Retry',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
