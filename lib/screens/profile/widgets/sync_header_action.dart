import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/prefs_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

class SyncHeaderAction extends ConsumerStatefulWidget {
  const SyncHeaderAction({super.key});

  @override
  ConsumerState<SyncHeaderAction> createState() => _SyncHeaderActionState();
}

class _SyncHeaderActionState extends ConsumerState<SyncHeaderAction> {
  bool _syncing = false;
  String? _syncTimeStr;

  @override
  void initState() {
    super.initState();
    _loadSyncTime();
  }

  Future<void> _loadSyncTime() async {
    final timestamp = await PrefsService.getLastSyncTime();
    if (timestamp == 0) {
      if (mounted) setState(() => _syncTimeStr = null);
      return;
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    if (mounted) {
      setState(() => _syncTimeStr = "$day.$month $hour:$min");
    }
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    HapticFeedback.lightImpact();
    try {
      await ref.read(syncServiceProvider).sync();
      await _loadSyncTime();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('sync_success') ??
                  'Successfully synced',
            ),
            backgroundColor: context.c.gold,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('auth_err_generic') ??
                  'Bir hata oluştu: $e',
            ),
            backgroundColor: context.c.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return Column(
      children: [
        Divider(
          color: c.isLight
              ? c.borderSoft
              : Colors.white.withValues(alpha: 0.08),
          height: 1,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _syncTimeStr != null
                    ? "${tr?.get('sync_last') ?? 'Last synced: '}$_syncTimeStr"
                    : (tr?.get('sync_desc') ?? 'Cloud sync active'),
                style: TextStyle(color: c.dim, fontSize: 11.5),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _runSync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: _syncing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 14),
                label: Text(
                  tr?.get('sync_now') ?? 'Sync Now',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
