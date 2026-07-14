import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
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
