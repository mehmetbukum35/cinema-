import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

/// "Cinema+ Hakkında" alt sayfası. Global menüden açılır; eskiden Keşfet ve
/// Profil başlıklarında birer kopyası vardı, tek kaynağa indirildi.
void showAboutSheet(BuildContext context) {
  final c = context.c;
  final tr = AppLocalizations.of(context);
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: c.isLight ? c.border : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.dim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: CinemaShadows.redGlow,
                  border: Border.all(color: c.goldSoft, width: 2),
                  image: const DecorationImage(
                    image: AssetImage('assets/logo.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                tr?.get('profile_about_title') ?? 'Cinema+ Hakkında',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr?.get('profile_about_content') ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 24),
            Divider(
              color: c.isLight
                  ? c.border
                  : Colors.white.withValues(alpha: 0.08),
              height: 1,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr?.get('profile_about_author') ?? 'Yazar',
                  style: TextStyle(
                    color: c.dim,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Muhammet Taha Büküm',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr?.get('profile_about_version') ?? 'Sürüm',
                  style: TextStyle(
                    color: c.dim,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '1.0.0 (Build 1)',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // TMDB kullanım şartı gereği zorunlu atıf metni.
            Text(
              tr?.get('tmdb_attribution') ??
                  'Bu ürün TMDB API\'sini kullanır ancak TMDB tarafından '
                      'onaylanmış veya sertifikalandırılmış değildir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.isLight
                    ? c.card
                    : Colors.white.withValues(alpha: 0.06),
                foregroundColor: c.ink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: c.isLight
                        ? c.border
                        : Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                tr?.get('ok') ?? 'Tamam',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
