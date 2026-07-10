import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

/// Tam sayfa hata/çevrimdışı durumu: ağ, 401 ve genel hata mesajlarını
/// ayırt eder, yeniden dene butonu sunar.
class BrowseErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const BrowseErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final errorStr = error.toString();
    final isNetworkError =
        errorStr.contains('No internet connection') ||
        errorStr.contains('SocketException') ||
        errorStr.contains('Failed host lookup') ||
        errorStr.contains('timed out') ||
        errorStr.contains('TimeoutException');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isNetworkError
                ? Icons.cloud_off_rounded
                : Icons.error_outline_rounded,
            color: c.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            isNetworkError
                ? (AppLocalizations.of(
                        context,
                      )?.get('browse_offline_title') ??
                      'You are Offline')
                : (errorStr.contains('401')
                      ? (AppLocalizations.of(
                              context,
                            )?.get('browse_api_unauthorized') ??
                            'Service Unauthorized')
                      : (AppLocalizations.of(context)?.get('browse_error') ??
                            'An error occurred while loading content.')),
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              isNetworkError
                  ? (AppLocalizations.of(
                          context,
                        )?.get('browse_offline_desc') ??
                        'Please check your internet connection and try again.')
                  : (errorStr.contains('401')
                        ? (AppLocalizations.of(
                                context,
                              )?.get('browse_api_unauthorized_desc') ??
                              'The server is unable to authenticate with the movie service. Please contact support.')
                        : (AppLocalizations.of(
                                context,
                              )?.get('browse_conn_error') ??
                              'Check your internet connection and try again.')),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13),
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
              AppLocalizations.of(context)?.get('browse_retry') ??
                  'Yeniden Dene',
            ),
          ),
        ],
      ),
    );
  }
}
