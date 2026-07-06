import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../providers/social_provider.dart';
import '../../theme/app_theme.dart';

class RecommendSheet extends StatefulWidget {
  final Movie movie;
  final List<dynamic> friends;
  final WidgetRef ref;
  final BuildContext parentContext;

  const RecommendSheet({
    super.key,
    required this.movie,
    required this.friends,
    required this.ref,
    required this.parentContext,
  });

  @override
  State<RecommendSheet> createState() => RecommendSheetState();
}

class RecommendSheetState extends State<RecommendSheet> {
  final _noteCtrl = TextEditingController();
  int? _sendingToFriendId;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr?.get('recommend_pick_friend') ?? 'Kime önerelim?',
            style: TextStyle(
              color: c.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.movie.title,
            style: TextStyle(color: c.dim, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteCtrl,
            maxLength: 280,
            enabled: _sendingToFriendId == null,
            style: TextStyle(color: c.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  tr?.get('recommend_note_hint') ?? 'Not ekle (isteğe bağlı)',
              hintStyle: TextStyle(color: c.dim, fontSize: 13),
              counterText: '',
              filled: true,
              fillColor: c.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.friends.length,
              itemBuilder: (listCtx, idx) {
                final f = widget.friends[idx];
                final name = f['display_name'] ?? f['username'] ?? 'User';
                final friendId = int.tryParse(f['id'].toString()) ?? 0;
                final isSending = _sendingToFriendId == friendId;
                final isAnySending = _sendingToFriendId != null;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: CinemaGradients.crimson,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.toString().isNotEmpty
                          ? name.toString()[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    name.toString(),
                    style: TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                  ),
                  trailing: isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.gold,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: isAnySending ? c.dim : c.gold,
                          size: 20,
                        ),
                  onTap: isAnySending
                      ? null
                      : () async {
                          final parentSm = ScaffoldMessenger.of(
                            widget.parentContext,
                          );
                          final nav = Navigator.of(context);

                          setState(() {
                            _sendingToFriendId = friendId;
                          });

                          final ok = await widget.ref
                              .read(socialProvider.notifier)
                              .recommendToFriend(
                                friendId: friendId,
                                movie: widget.movie,
                                note: _noteCtrl.text.trim(),
                              );

                          if (ok) {
                            nav.pop();
                            parentSm.clearSnackBars();
                            parentSm.showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.green,
                                content: Text(
                                  tr?.get('recommend_sent') ??
                                      'Öneri gönderildi!',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          } else {
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (dialogCtx) => AlertDialog(
                                  backgroundColor: c.surface,
                                  title: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        color: c.red,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        tr?.get('error') ?? 'Hata',
                                        style: TextStyle(color: c.ink),
                                      ),
                                    ],
                                  ),
                                  content: Text(
                                    widget.ref.read(socialProvider).error ??
                                        'Öneri gönderilemedi.',
                                    style: TextStyle(color: c.dim),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogCtx),
                                      child: Text(
                                        tr?.get('ok') ?? 'Tamam',
                                        style: TextStyle(
                                          color: c.gold,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              setState(() {
                                _sendingToFriendId = null;
                              });
                            }
                          }
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
