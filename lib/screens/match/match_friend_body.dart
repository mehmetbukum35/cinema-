import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';
import '../../models/social.dart';
import '../../providers/auth_provider.dart';
import '../../providers/social_provider.dart';
import '../../services/localization_service.dart';
import '../../services/tmdb_service.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../login_screen.dart';
import '../movie_detail_sheet.dart';
import '../results_screen.dart';
import '../social_screen.dart';
import 'match_widgets.dart';

/// Arkadaş eşleştir modu: arkadaş seçimi ve ortak izleme listesi.
class MatchFriendBody extends ConsumerWidget {
  final Friend? selectedFriend;
  final ValueChanged<Friend> onSelectFriend;
  final VoidCallback onDeselectFriend;

  const MatchFriendBody({
    super.key,
    required this.selectedFriend,
    required this.onSelectFriend,
    required this.onDeselectFriend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final authState = ref.watch(authProvider);

    if (!authState.isAuthenticated) {
      return _AuthRequiredView(palette: c);
    }

    final socialState = ref.watch(socialProvider);

    if (selectedFriend == null) {
      return _FriendPickerView(
        palette: c,
        socialState: socialState,
        onSelectFriend: onSelectFriend,
      );
    }

    return _FriendIntersectionView(
      palette: c,
      socialState: socialState,
      selectedFriend: selectedFriend!,
      onDeselectFriend: onDeselectFriend,
      service: ref.read(tmdbServiceProvider),
    );
  }
}

class _AuthRequiredView extends StatelessWidget {
  final ThemePalette palette;

  const _AuthRequiredView({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surface,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                color: palette.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)?.get('authentication_required') ??
                  'Authentication Required',
              style: TextStyle(
                color: palette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(
                    context,
                  )?.get('please_sign_in_to_view_watchli') ??
                  'Please sign in to view watchlist intersections with your friends.',
              style: TextStyle(color: palette.dim, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                AppLocalizations.of(context)?.get('auth_title_login') ??
                    'Sign In',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendPickerView extends StatelessWidget {
  final ThemePalette palette;
  final SocialState socialState;
  final ValueChanged<Friend> onSelectFriend;

  const _FriendPickerView({
    required this.palette,
    required this.socialState,
    required this.onSelectFriend,
  });

  @override
  Widget build(BuildContext context) {
    if (socialState.loading) {
      return Center(child: CircularProgressIndicator(color: palette.gold));
    }

    final friends = socialState.friends;
    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surface,
                ),
                child: Icon(
                  Icons.people_alt_rounded,
                  color: palette.gold,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)?.get('no_friends_yet') ??
                    'No Friends Yet',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                      context,
                    )?.get('you_must_add_friends_first_to_') ??
                    'You must add friends first to match with them.',
                style: TextStyle(color: palette.dim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SocialScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)?.get('add_manage_friends') ??
                      'Add / Manage Friends',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatchIntroBanner(
          palette: palette,
          icon: Icons.group_add_rounded,
          title:
              AppLocalizations.of(context)?.get('online_friend_match') ??
              'Online Friend Match',
          description:
              AppLocalizations.of(
                context,
              )?.get('select_a_friend_to_find_common') ??
              'Select a friend to find common titles in your watchlists and get joint recommendations based on your shared interests.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(
                        context,
                      )?.get('select_a_friend_to_match_with') ??
                      'Select a friend to match with:',
                  style: TextStyle(
                    color: palette.dim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SocialScreen(initialTab: 0),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.manage_accounts_rounded,
                      color: palette.red,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context)?.get('manage') ?? 'Manage',
                      style: TextStyle(
                        color: palette.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: friends.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, idx) {
              final f = friends[idx];
              final name = f.displayName ?? f.username;
              final handle = f.username;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.borderSoft),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: palette.border,
                    foregroundColor: palette.ink,
                    child: Text(name[0].toUpperCase()),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: handle.isNotEmpty
                      ? Text(
                          '@$handle',
                          style: TextStyle(color: palette.dim, fontSize: 12),
                        )
                      : null,
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: palette.dim,
                    size: 14,
                  ),
                  onTap: () => onSelectFriend(f),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FriendIntersectionView extends StatelessWidget {
  final ThemePalette palette;
  final SocialState socialState;
  final Friend selectedFriend;
  final VoidCallback onDeselectFriend;
  final TmdbService service;

  const _FriendIntersectionView({
    required this.palette,
    required this.socialState,
    required this.selectedFriend,
    required this.onDeselectFriend,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final friendName = selectedFriend.displayName ?? selectedFriend.username;
    final intersection = socialState.intersection;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: palette.ink),
                onPressed: onDeselectFriend,
              ),
              CircleAvatar(
                radius: 16,
                backgroundColor: palette.border,
                foregroundColor: palette.ink,
                child: Text(
                  friendName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  friendName,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: socialState.loading
              ? Center(child: CircularProgressIndicator(color: palette.gold))
              : socialState.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: palette.red,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          socialState.error!,
                          style: TextStyle(
                            color: palette.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : intersection.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('no_common_movies') ??
                              'No Common Movies',
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('neither_of_you_have_added_the_') ??
                              'Neither of you have added the same movies to your watchlists.',
                          style: TextStyle(color: palette.dim, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Text(
                        AppLocalizations.of(context)
                                ?.get('your_common_watchlist_intersec')
                                .replaceAll('{}', '${intersection.length}') ??
                            'Your Common Watchlist (${intersection.length} Titles)',
                        style: TextStyle(
                          color: palette.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2 / 3.4,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: intersection.length,
                        itemBuilder: (context, idx) {
                          final m = intersection[idx];
                          return _IntersectionPoster(
                            movie: m,
                            palette: palette,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) => MovieDetailSheet(
                                  movie: m,
                                  service: service,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: () {
                          final genres = intersection
                              .expand((m) => m.genreIds)
                              .toSet()
                              .toList();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultsScreen(
                                genreStr: genres.isNotEmpty
                                    ? genres.join(',')
                                    : null,
                                sortBy: 'vote_average.desc',
                                jointGenres: genres,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          AppLocalizations.of(
                                context,
                              )?.get('find_joint_recommendations') ??
                              'Find Joint Recommendations',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _IntersectionPoster extends StatelessWidget {
  final Movie movie;
  final ThemePalette palette;
  final VoidCallback onTap;

  const _IntersectionPoster({
    required this.movie,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: movie.posterUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: movie.posterUrl,
                      fit: BoxFit.cover,
                      placeholder: (ctx, url) =>
                          ColoredBox(color: palette.card),
                      errorWidget: (ctx, url, err) =>
                          ColoredBox(color: palette.card),
                    )
                  : ColoredBox(color: palette.card),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
