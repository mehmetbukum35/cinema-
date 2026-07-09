import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

class BlockedUsersSheet extends ConsumerStatefulWidget {
  final BuildContext parentContext;

  const BlockedUsersSheet({super.key, required this.parentContext});

  @override
  ConsumerState<BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends ConsumerState<BlockedUsersSheet> {
  List<Map<String, dynamic>> _blocked = [];
  bool _loading = true;
  String? _error;
  int? _unblockingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref.read(apiServiceProvider).getBlockedUsers();
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) {
        setState(() {
          _blocked = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _displayName(Map<String, dynamic> user) {
    final name = (user['display_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final username = (user['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) return '@$username';
    return '#${user['id']}';
  }

  Future<void> _confirmUnblock(Map<String, dynamic> user) async {
    final tr = AppLocalizations.of(context);
    final c = context.c;
    final userId = user['id'] as int;
    final name = _displayName(user);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          tr?.get('blocked_users_unblock_confirm_title') ??
              'Engeli kaldırılsın mı?',
          style: TextStyle(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          (tr?.get('blocked_users_unblock_confirm_msg') ??
                  '$name kullanıcısının engeli kaldırılacak.')
              .replaceAll('{}', name),
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              tr?.get('profile_cancel') ?? 'Vazgeç',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr?.get('blocked_users_unblock') ?? 'Engeli Kaldır',
              style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _unblock(userId);
  }

  Future<void> _unblock(int userId) async {
    HapticFeedback.lightImpact();
    setState(() => _unblockingId = userId);
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(widget.parentContext);

    try {
      await ref.read(apiServiceProvider).unblockUser(userId);
      if (!mounted) return;
      setState(() {
        _blocked.removeWhere((u) => u['id'] == userId);
        _unblockingId = null;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('blocked_users_unblocked') ?? 'Engel kaldırıldı',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _unblockingId = null);
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.dim.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr?.get('blocked_users_title') ??
                              'Engellenen Kullanıcılar',
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr?.get('blocked_users_subtitle') ??
                              'Yorumlarını ve aktivitelerini gizlediğin kişiler',
                          style: TextStyle(color: c.dim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: c.dim),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      tr?.get('blocked_users_load_error') ??
                          'Liste yüklenemedi.',
                      style: TextStyle(color: c.dim),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _load,
                      child: Text(
                        tr?.get('retry') ?? 'Tekrar dene',
                        style: TextStyle(color: c.gold),
                      ),
                    ),
                  ],
                ),
              )
            else if (_blocked.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text(
                  tr?.get('blocked_users_empty') ??
                      'Engellediğin kullanıcı yok.',
                  style: TextStyle(color: c.dim, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _blocked.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final user = _blocked[index];
                    final userId = user['id'] as int;
                    final busy = _unblockingId == userId;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: c.isLight
                            ? Border.all(color: c.border, width: 1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: c.gold.withValues(alpha: 0.15),
                            child: Text(
                              _displayName(user)
                                  .replaceAll('@', '')
                                  .isNotEmpty
                                  ? _displayName(user)
                                      .replaceAll('@', '')
                                      .substring(0, 1)
                                      .toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: c.gold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayName(user),
                                  style: TextStyle(
                                    color: c.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((user['username'] as String?)?.isNotEmpty ==
                                    true)
                                  Text(
                                    '@${user['username']}',
                                    style: TextStyle(
                                      color: c.dim,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => _confirmUnblock(user),
                            child: busy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.gold,
                                    ),
                                  )
                                : Text(
                                    tr?.get('blocked_users_unblock') ??
                                        'Engeli Kaldır',
                                    style: TextStyle(
                                      color: c.gold,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
