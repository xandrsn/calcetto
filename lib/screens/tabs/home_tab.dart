import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin/admin_screen.dart';
import '../../config.dart';
import '../../models/match.dart';
import '../../models/user_data.dart';
import '../../providers/data_repository.dart';
import '../../providers/game_state_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_utils.dart';
import '../../widgets/async_states.dart';
import '../../widgets/calcetto_logo.dart';
import '../../widgets/leaderboard_widget.dart';
import '../../widgets/local_backup_button.dart';
import '../../widgets/pitch_widget.dart';
import '../../widgets/pixel_button.dart';

// ── Feed item union ────────────────────────────────────────────────────────

class _FeedItem {
  final String timestamp;
  final bool isChat;
  final ActivityEvent? event;
  final ChatMessage? message;

  _FeedItem.event(ActivityEvent e)
    : timestamp = e.timestamp,
      isChat = false,
      event = e,
      message = null;

  _FeedItem.chat(ChatMessage m)
    : timestamp = m.timestamp,
      isChat = true,
      event = null,
      message = m;
}

// ── HomeTab ────────────────────────────────────────────────────────────────

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBackground,
      appBar: _HomeAppBar(),
      body: Column(
        children: [
          _ClasificacionButton(),
          Expanded(child: _UnifiedFeed()),
          _ChatInput(),
        ],
      ),
    );
  }
}

// ── App bar ────────────────────────────────────────────────────────────────

class _HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(usernameProvider) ?? '';
    return AppBar(
      backgroundColor: kSurface,
      elevation: 0,
      title: const CalcettoLogo.bar(wordSize: 15),
      actions: [
        const LocalBackupButton(),
        if (isAdminUser(username))
          IconButton(
            tooltip: 'Admin',
            icon: const Icon(
              Icons.admin_panel_settings,
              color: kTextMuted,
              size: 18,
            ),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AdminScreen())),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: Text(
              username.toUpperCase(),
              style: const TextStyle(
                fontFamily: kFontUI,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kAccentYellow,
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: kBorder, height: 1),
      ),
    );
  }
}

// ── CLASIFICACION button ───────────────────────────────────────────────────

class _ClasificacionButton extends StatelessWidget {
  const _ClasificacionButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: kSurface,
          builder: (_) => const _ClasificacionModal(),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: kAccentYellow, width: 2),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, color: kAccentYellow, size: 18),
              SizedBox(width: 10),
              Text(
                'CLASIFICACION',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 13,
                  color: kAccentYellow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CLASIFICACION modal ────────────────────────────────────────────────────

class _ClasificacionModal extends ConsumerWidget {
  const _ClasificacionModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(allUsersProvider);
    final username = ref.watch(usernameProvider);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kBorder, width: 1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.emoji_events, color: kAccentYellow, size: 16),
                SizedBox(width: 8),
                Text(
                  'CLASIFICACION',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kAccentYellow,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: allAsync.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.read(allUsersProvider.notifier).refresh(),
              ),
              data: (users) {
                final playersAsync = ref.watch(playersProvider);
                final playerNames = <String, String>{
                  for (final p in (playersAsync.value ?? [])) p.id: p.name,
                };
                return LeaderboardWidget(
                  allUsers: users,
                  currentUser: username,
                  playerNames: playerNames,
                  onViewTeam: (rivalUsername) {
                    final rivalData = users[rivalUsername];
                    if (rivalData == null) return;
                    final rivalUser = UserData.fromJson(
                      rivalData as Map<String, dynamic>,
                    );
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: kSurface,
                      builder: (_) => _RivalTeamSheet(rivalUser: rivalUser),
                    );
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

// ── Rival team sheet ───────────────────────────────────────────────────────

class _RivalTeamSheet extends ConsumerWidget {
  final UserData rivalUser;

  const _RivalTeamSheet({required this.rivalUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersAsync = ref.watch(playersProvider);
    final matchdayDate = ref.watch(currentMatchdayProvider).value?.date;
    final captain = rivalUser.captainFor(
      today: todayString(),
      matchdayDate: matchdayDate,
    );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kBorder, width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.grass, color: kAccentGreen, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rivalUser.name.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 14,
                      color: kAccentGreen,
                    ),
                  ),
                ),
                Text(
                  rivalUser.formation,
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 12,
                    color: kTextMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: playersAsync.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(playersProvider),
              ),
              data: (players) => PitchWidget(
                user: rivalUser,
                players: players,
                todayCaptain: captain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unified feed ───────────────────────────────────────────────────────────

class _UnifiedFeed extends ConsumerStatefulWidget {
  const _UnifiedFeed();

  @override
  ConsumerState<_UnifiedFeed> createState() => _UnifiedFeedState();
}

class _UnifiedFeedState extends ConsumerState<_UnifiedFeed> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      // Clear BOTH cached paths, else the providers re-read stale cache and the
      // activity feed never updates on poll.
      final gh = ref.read(githubServiceProvider);
      gh.clearPath('chat.json');
      gh.clearPath('data/activity_log.json');
      ref.invalidate(chatProvider);
      ref.invalidate(activityLogProvider);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatProvider);
    final logAsync = ref.watch(activityLogProvider);

    final items = <_FeedItem>[];
    if (logAsync.hasValue) {
      for (final e in logAsync.value!) {
        items.add(_FeedItem.event(e));
      }
    }
    if (chatAsync.hasValue) {
      for (final m in chatAsync.value!) {
        items.add(_FeedItem.chat(m));
      }
    }
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final loading = chatAsync.isLoading && logAsync.isLoading;

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(githubServiceProvider).clearCache();
        ref.invalidate(activityLogProvider);
        ref.invalidate(chatProvider);
        ref.invalidate(allUsersProvider);
      },
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Text(
                    'SIN ACTIVIDAD',
                    style: TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 12,
                      color: kTextMuted,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: kBorder),
              itemBuilder: (ctx, i) {
                final item = items[i];
                if (item.isChat) {
                  return _ChatBubble(message: item.message!);
                }
                return _EventRow(event: item.event!);
              },
            ),
    );
  }
}

// ── Feed renderers ─────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chat_bubble_outline, color: kTextMuted, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.user.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kAccentYellow,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTimestamp(message.timestamp),
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kTextMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.text,
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kTextPrimary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ActivityEvent event;

  const _EventRow({required this.event});

  IconData get _icon {
    switch (event.type) {
      case 'sub':
        return Icons.swap_horiz;
      case 'bet_resolved':
        return Icons.monetization_on;
      case 'round_change':
        return Icons.emoji_events;
      case 'join':
        return Icons.star;
      case 'card_played':
        return Icons.style;
      default:
        return Icons.info_outline;
    }
  }

  Color get _color {
    switch (event.type) {
      case 'bet_resolved':
        return kAccentGreen;
      case 'round_change':
        return kAccentYellow;
      case 'join':
        return kAccentGreen;
      case 'card_played':
        return kAccentRed;
      default:
        return kAccentBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kTextPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatTimestamp(event.timestamp),
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat input ─────────────────────────────────────────────────────────────

class _ChatInput extends ConsumerStatefulWidget {
  const _ChatInput();

  @override
  ConsumerState<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<_ChatInput> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || text.length > 280) return;
    final username = ref.read(usernameProvider);
    if (username == null) return;

    setState(() => _sending = true);
    try {
      await ref.read(dataRepositoryProvider).appendChatMessage(
        ChatMessage(
          user: username,
          timestamp: DateTime.now().toIso8601String(),
          text: text,
        ),
      );
      _ctrl.clear();
      ref.invalidate(chatProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NO SE PUDO ENVIAR — VERIFICA CONEXION'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLength: 280,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: kTextPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'mensaje...',
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PixelButton(label: 'SEND', onTap: _send, fontSize: 11),
        ],
      ),
    );
  }
}
