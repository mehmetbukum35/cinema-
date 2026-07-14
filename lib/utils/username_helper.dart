import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/social/profile_settings_sheet.dart';
import '../widgets/username_prompt_sheet.dart';

/// Kullanıcının web/sosyal özellikler için kullanıcı adı belirlemesi gerekip
/// gerekmediğini kontrol eder.
bool needsUsername(Map<String, dynamic>? user) {
  if (user == null) return false;
  final username = (user['username'] as String?)?.trim();
  return username == null || username.isEmpty;
}

/// Backend ile aynı kurallar: 3-30 karakter, yalnızca a-z, 0-9, alt çizgi.
String? validateUsername(String raw) {
  final username = raw.trim().toLowerCase();
  if (username.isEmpty) return 'please_enter_a_username';
  if (!RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(username)) {
    return 'username_invalid_format';
  }
  return null;
}

/// Giriş sonrası veya halka açık profil açılırken kullanıcı adı iste.
/// İlk girişte doğrudan "Profilini Özelleştir" sheet'ini açar.
Future<void> showUsernamePromptIfNeeded(
  BuildContext context,
  WidgetRef ref, {
  bool forcePublic = false,
  bool allowSkip = true,
}) {
  final auth = ref.read(authProvider);
  if (!auth.isAuthenticated || !needsUsername(auth.user)) {
    return Future.value();
  }

  if (forcePublic) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: allowSkip,
      enableDrag: allowSkip,
      builder: (_) =>
          UsernamePromptSheet(forcePublic: forcePublic, allowSkip: allowSkip),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: allowSkip,
    enableDrag: allowSkip,
    builder: (_) => _ProfileCustomizationPrompt(allowSkip: allowSkip),
  );
}

/// İlk giriş akışı: kullanıcı adı + herkese açık profil ayarları.
class _ProfileCustomizationPrompt extends ConsumerStatefulWidget {
  final bool allowSkip;

  const _ProfileCustomizationPrompt({required this.allowSkip});

  @override
  ConsumerState<_ProfileCustomizationPrompt> createState() =>
      _ProfileCustomizationPromptState();
}

class _ProfileCustomizationPromptState
    extends ConsumerState<_ProfileCustomizationPrompt> {
  late final TextEditingController _usernameCtrl;
  late bool _isPublic;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _usernameCtrl = TextEditingController(
      text: (auth.user?['username'] as String?) ?? '',
    );
    _isPublic = (auth.user?['is_public'] ?? 1) == 1;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfileSettingsSheet(
      usernameCtrl: _usernameCtrl,
      isPublic: _isPublic,
      allowSkip: widget.allowSkip,
      onPublicChanged: (val) => setState(() => _isPublic = val),
    );
  }
}
