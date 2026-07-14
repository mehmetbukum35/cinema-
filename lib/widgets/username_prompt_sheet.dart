import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/social_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../utils/username_helper.dart';

/// Web profili ve sosyal özellikler için kullanıcı adı belirleme sheet'i.
/// Giriş sonrası (allowSkip: true) veya halka açık profil açılırken
/// (forcePublic: true) kullanılır.
class UsernamePromptSheet extends ConsumerStatefulWidget {
  final bool forcePublic;
  final bool allowSkip;

  const UsernamePromptSheet({
    super.key,
    this.forcePublic = false,
    this.allowSkip = true,
  });

  @override
  ConsumerState<UsernamePromptSheet> createState() =>
      _UsernamePromptSheetState();
}

class _UsernamePromptSheetState extends ConsumerState<UsernamePromptSheet> {
  final _usernameCtrl = TextEditingController();
  bool _saving = false;
  late bool _isPublic = widget.forcePublic;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final tr = AppLocalizations.of(context);
    final c = context.c;
    final username = _usernameCtrl.text.trim().toLowerCase();
    final validationKey = validateUsername(username);
    if (validationKey != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr?.get(validationKey) ?? validationKey),
          backgroundColor: c.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final success = await ref
        .read(socialProvider.notifier)
        .setupProfile(username, _isPublic);
    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('profile_updated_successfully') ??
                'Profile updated successfully.',
          ),
          backgroundColor: c.gold,
        ),
      );
    } else {
      final err = ref.read(socialProvider).error ?? 'Bir hata oluştu';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: c.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

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
              tr?.get('username_prompt_title') ?? 'Choose a Username',
              style: TextStyle(
                color: c.ink,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr?.get('username_prompt_desc') ??
                  'Your web profile and social features need a unique username.',
              style: TextStyle(color: c.dim, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameCtrl,
              enabled: !_saving,
              autocorrect: false,
              style: TextStyle(color: c.ink, fontSize: 14),
              decoration: InputDecoration(
                labelText:
                    tr?.get('username_username') ?? 'Username (@username)',
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
              onFieldSubmitted: (_) => _save(),
            ),
            if (widget.forcePublic) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  title: Text(
                    tr?.get('public_profile') ?? 'Public Profile',
                    style: TextStyle(color: c.ink, fontSize: 14),
                  ),
                  value: _isPublic,
                  activeThumbColor: c.gold,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _saving
                      ? null
                      : (val) => setState(() => _isPublic = val),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.gold,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      tr?.get('social_set_username') ?? 'Set Username',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
            if (widget.allowSkip) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(
                  tr?.get('username_prompt_later') ?? 'Later',
                  style: TextStyle(color: c.dim, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
