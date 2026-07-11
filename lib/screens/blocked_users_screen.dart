import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';

/// Engellenen kullanıcıların listesi ve engel kaldırma.
/// Veri sunucudan gelir (GET /social/users/blocked); engel kaldırma geri
/// alınabilir bir işlem olduğu için onay sorulmaz, tek dokunuş yeter.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<dynamic>? _blocked;
  bool _error = false;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _blocked = null;
      _error = false;
    });
    try {
      final list = await ref.read(apiServiceProvider).getBlockedUsers();
      if (mounted) setState(() => _blocked = list);
    } catch (e) {
      debugPrint('Blocked users load failed: $e');
      if (mounted) {
        setState(() {
          _blocked = const [];
          _error = true;
        });
      }
    }
  }

  Future<void> _unblock(int userId, String name) async {
    final c0 = context.c;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c0.card,
        title: Text(
          tr?.get('blocked_users_unblock_confirm_title') ??
              'Engel kaldırılsın mı?',
          style: TextStyle(color: c0.ink, fontSize: 16),
        ),
        content: Text(
          tr?.get('blocked_users_unblock_confirm_msg').replaceAll('{}', name) ??
              '$name kullanıcısının engeli kaldırılacak ve yorumları tekrar görünebilir.',
          style: TextStyle(color: c0.dim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              tr?.get('profile_cancel') ?? 'İptal',
              style: TextStyle(color: c0.dim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              tr?.get('blocked_users_unblock') ?? 'Engeli Kaldır',
              style: TextStyle(color: c0.gold, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy.add(userId));
    try {
      await ref.read(apiServiceProvider).unblockUser(userId);
      if (!mounted) return;
      final c = context.c;
      setState(() {
        _blocked = _blocked
            ?.where((u) => int.tryParse(u['id']?.toString() ?? '') != userId)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('blocked_users_unblocked') ?? 'Engel kaldırıldı',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: c.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final c = context.c;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('error_occurred_msg').replaceAll('{}', '$e') ?? 'Hata: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: c.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final blocked = _blocked;

    return CinematicBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: c.ink,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: tr?.get('semantics_go_back') ?? 'Back',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          title: Text(
            tr?.get('blocked_users_title') ?? 'Engellenen Kullanıcılar',
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: blocked == null
            ? const Center(child: CircularProgressIndicator())
            : _error
            ? _errorState(c, tr)
            : blocked.isEmpty
            ? _emptyState(c, tr)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: blocked.length,
                  itemBuilder: (_, i) => _userRow(blocked[i], c, tr),
                ),
              ),
      ),
    );
  }

  Widget _errorState(ThemePalette c, AppLocalizations? tr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, color: c.dim, size: 42),
          const SizedBox(height: 12),
          Text(
            tr?.get('blocked_users_load_error') ?? 'Engellenenler yüklenemedi.',
            style: TextStyle(
              color: c.dim,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _load,
            child: Text(
              tr?.get('retry') ?? 'Tekrar dene',
              style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemePalette c, AppLocalizations? tr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block_rounded, color: c.dim, size: 42),
          const SizedBox(height: 12),
          Text(
            tr?.get('blocked_users_empty') ?? 'Engellediğin kullanıcı yok.',
            style: TextStyle(
              color: c.dim,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _userRow(dynamic user, ThemePalette c, AppLocalizations? tr) {
    final userId = int.tryParse(user['id']?.toString() ?? '');
    final name = (user['display_name'] as String?)?.trim().isNotEmpty == true
        ? user['display_name'] as String
        : '@${user['username'] ?? '?'}';
    final username = user['username'] as String?;
    final busy = userId != null && _busy.contains(userId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.border),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: c.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (username != null && !name.startsWith('@'))
                  Text(
                    '@$username',
                    style: TextStyle(color: c.dim, fontSize: 11),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy || userId == null
                ? null
                : () => _unblock(userId, name),
            style: TextButton.styleFrom(
              backgroundColor: c.borderSoft.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.dim,
                    ),
                  )
                : Text(
                    tr?.get('blocked_users_unblock') ?? 'Engeli Kaldır',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
