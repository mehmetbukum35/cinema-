import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Profil bölüm başlığı: kırmızı dikey çizgi + büyük harfli başlık.
class ProfileSectionHeader extends StatelessWidget {
  final String text;

  const ProfileSectionHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: CinemaGradients.crimson,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: c.dim,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
