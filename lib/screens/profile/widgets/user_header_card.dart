import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import '../../../services/app_config.dart';
import '../../../providers/watchlist_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import '../../../utils/username_helper.dart';
import '../../../widgets/logout_confirm_dialog.dart';
import '../../../widgets/auth_conflict_dialog.dart';
import '../../login_screen.dart';
import 'sync_header_action.dart';

/// Kimlik kartı: kullanıcı bilgisi, giriş/çıkış, Google/Apple ile giriş ve
/// (girişliyse) manuel eşitleme eylemi.
class UserHeaderCard extends ConsumerWidget {
  const UserHeaderCard({super.key});

  /// App Store 4.8: üçüncü taraf giriş sunulan platformda (iOS) Sign in with
  /// Apple da sunulmalı. Android'de gösterilmez (web akışı yapılandırılmadı).
  static bool get _appleSignInAvailable => !kIsWeb && Platform.isIOS;

  /// Google ve Apple girişlerinin ortak sonuç işleyicisi.
  Future<void> _handleSignIn(
    BuildContext context,
    WidgetRef ref,
    Future<AuthResult> Function() signIn,
  ) async {
    final c = context.c;
    try {
      final result = await signIn();
      if (!context.mounted) return;

      if (result.status == AuthStatus.success) {
        ref.invalidate(watchlistProvider);
        ref.invalidate(statsProvider);
        if (context.mounted) {
          await showUsernamePromptIfNeeded(context, ref);
        }
      } else if (result.status == AuthStatus.conflict) {
        final resolution = await showAuthConflictDialog(context);
        if (resolution != null && context.mounted) {
          await ref
              .read(authProvider.notifier)
              .completeLogin(
                user: result.user!,
                tokens: result.tokens!,
                resolution: resolution,
              );
          ref.invalidate(watchlistProvider);
          ref.invalidate(statsProvider);
          if (context.mounted) {
            await showUsernamePromptIfNeeded(context, ref);
          }
        } else {
          // İptal: sunucunun çoktan verdiği token çifti kullanılmayacak →
          // sunucuda iptal et ki yetim refresh token kalmasın.
          await ref
              .read(authProvider.notifier)
              .cancelPendingLogin(result.tokens);
        }
      } else if (result.status == AuthStatus.error) {
        final errKey = result.errorMessage ?? 'auth_err_login_failed';
        final message = AppLocalizations.of(context)?.get(errKey) ?? errKey;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: c.red),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final tr = AppLocalizations.of(context);
        final formatString = tr?.get('error_occurred_msg') ?? 'Error: {}';
        final message = formatString.replaceFirst('{}', e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: c.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final auth = ref.watch(authProvider);
    final isLoggedIn = auth.isLoggedIn;
    final user = auth.user;

    final String displayName =
        user?['display_name'] as String? ??
        user?['username'] as String? ??
        user?['email'] as String? ??
        '';
    final String email = user?['email'] as String? ?? '';
    final String initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    final tr = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: c.isLight ? Border.all(color: c.border, width: 1) : null,
          boxShadow: c.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isLoggedIn ? CinemaGradients.gold : null,
                    color: isLoggedIn
                        ? null
                        : (c.isLight ? c.borderSoft : c.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isLoggedIn ? initial : '👤',
                    style: TextStyle(
                      fontSize: isLoggedIn ? 20 : 18,
                      fontWeight: FontWeight.w800,
                      color: isLoggedIn ? Colors.black : c.dim,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn
                            ? displayName
                            : (tr?.get('profile_guest') ?? 'Misafir Kullanıcı'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoggedIn
                            ? email
                            : (tr?.get('profile_not_logged_in') ??
                                  'Bulut eşitleme aktif değil'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (isLoggedIn)
                  IconButton(
                    icon: Icon(Icons.logout_rounded, color: c.red, size: 20),
                    onPressed: () => showLogoutConfirmDialog(context, ref),
                    tooltip: tr?.get('auth_logout') ?? 'Çıkış Yap',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  )
                else
                  ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      tr?.get('auth_title_login') ?? 'Giriş Yap',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (!isLoggedIn &&
                (AppConfig.googleSignInConfigured ||
                    _appleSignInAvailable)) ...[
              const SizedBox(height: 16),
              Divider(
                color: c.isLight
                    ? c.borderSoft
                    : Colors.white.withValues(alpha: 0.08),
                height: 1,
              ),
              const SizedBox(height: 14),
            ],
            if (!isLoggedIn && AppConfig.googleSignInConfigured)
              SpringButton(
                onTap: auth.loading
                    ? null
                    : () => _handleSignIn(
                        context,
                        ref,
                        () =>
                            ref.read(authProvider.notifier).signInWithGoogle(),
                      ),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.isLight
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: c.isLight
                          ? c.border
                          : Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: auth.loading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.dim,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tr?.get('auth_signing_in') ??
                                    'Giriş yapılıyor...',
                                style: TextStyle(
                                  color: c.dim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tr?.get('auth_google_button') ??
                                  'Google ile devam et',
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            if (!isLoggedIn && _appleSignInAvailable) ...[
              if (AppConfig.googleSignInConfigured) const SizedBox(height: 10),
              SpringButton(
                onTap: auth.loading
                    ? null
                    : () => _handleSignIn(
                        context,
                        ref,
                        () => ref.read(authProvider.notifier).signInWithApple(),
                      ),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.isLight
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: c.isLight
                          ? c.border
                          : Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.apple, size: 20, color: c.ink),
                      const SizedBox(width: 10),
                      Text(
                        tr?.get('auth_apple_button') ?? 'Apple ile devam et',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (isLoggedIn) ...[
              const SizedBox(height: 12),
              const SyncHeaderAction(),
            ],
          ],
        ),
      ),
    );
  }
}
