import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/social_provider.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

/// Profil özelleştirme alt sayfası: kullanıcı adı + herkese açık anahtarı.
/// Controller ve isPublic durumu üst ekranda yaşar (sheet kapansa da
/// korunur); anahtar değişimi [onPublicChanged] ile üste bildirilir.
class ProfileSettingsSheet extends ConsumerStatefulWidget {
  final TextEditingController usernameCtrl;
  final bool isPublic;
  final ValueChanged<bool> onPublicChanged;

  const ProfileSettingsSheet({
    super.key,
    required this.usernameCtrl,
    required this.isPublic,
    required this.onPublicChanged,
  });

  @override
  ConsumerState<ProfileSettingsSheet> createState() =>
      _ProfileSettingsSheetState();
}

class _ProfileSettingsSheetState extends ConsumerState<ProfileSettingsSheet> {
  late bool _isPublic = widget.isPublic;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)?.get('customize_profile') ??
                  'Customize Profile',
              style: TextStyle(
                color: c.ink,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: widget.usernameCtrl,
              style: TextStyle(color: c.ink, fontSize: 14),
              decoration: InputDecoration(
                labelText:
                    AppLocalizations.of(context)?.get('username_username') ??
                    'Username (@username)',
                labelStyle: TextStyle(color: c.dim, fontSize: 13),
                prefixText: '@',
                prefixStyle: TextStyle(
                  color: c.gold,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: c.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                title: Text(
                  AppLocalizations.of(context)?.get('public_profile') ??
                      'Public Profile',
                  style: TextStyle(color: c.ink, fontSize: 14),
                ),
                subtitle: Text(
                  AppLocalizations.of(
                        context,
                      )?.get('when_disabled_your_profile_can') ??
                      'When disabled, your profile cannot be viewed on the web.',
                  style: TextStyle(color: c.dim, fontSize: 11),
                ),
                value: _isPublic,
                activeThumbColor: c.gold,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) {
                  setState(() => _isPublic = val);
                  widget.onPublicChanged(val); // sync with parent
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final username = widget.usernameCtrl.text.trim().toLowerCase();
                if (username.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                              context,
                            )?.get('please_enter_a_username') ??
                            'Please enter a username.',
                      ),
                    ),
                  );
                  return;
                }

                final success = await ref
                    .read(socialProvider.notifier)
                    .setupProfile(username, _isPublic);
                if (success && context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                              context,
                            )?.get('profile_updated_successfully') ??
                            'Profile updated successfully.',
                      ),
                      backgroundColor: c.gold,
                    ),
                  );
                } else if (context.mounted) {
                  final err =
                      ref.read(socialProvider).error ?? 'Bir hata oluştu';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err), backgroundColor: c.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.gold,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                AppLocalizations.of(context)?.get('save_settings') ??
                    'Save Settings',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
