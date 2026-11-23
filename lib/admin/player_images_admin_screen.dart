import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/player.dart';
import '../providers/game_state_provider.dart';
import '../services/player_images.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/player_avatar.dart';

/// Admin UI to set a global custom image per player. Upload replaces, and the
/// change is visible to everyone everywhere the player appears.
class PlayerImagesAdminScreen extends ConsumerStatefulWidget {
  const PlayerImagesAdminScreen({super.key});

  @override
  ConsumerState<PlayerImagesAdminScreen> createState() =>
      _PlayerImagesAdminScreenState();
}

class _PlayerImagesAdminScreenState
    extends ConsumerState<PlayerImagesAdminScreen> {
  String _query = '';
  String? _busyId;

  final _picker = ImagePicker();

  Future<void> _upload(Player p) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
    } catch (e) {
      _toast('No se pudo abrir la galería: $e');
      return;
    }
    if (picked == null) return; // user cancelled
    setState(() => _busyId = p.id);
    try {
      final bytes = await picked.readAsBytes();
      await ref.read(playerImageServiceProvider).upload(p.id, bytes);
      ref.invalidate(playerImagesProvider);
      _toast('Imagen actualizada: ${p.name}');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(Player p) async {
    setState(() => _busyId = p.id);
    try {
      await ref.read(playerImageServiceProvider).remove(p.id);
      ref.invalidate(playerImagesProvider);
      _toast('Imagen eliminada: ${p.name}');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playersAsync = ref.watch(playersProvider);
    final manifest = ref.watch(playerImagesProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text(
          'PLAYER IMAGES',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 14,
            color: kAccentYellow,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: kAccentYellow, height: 2),
        ),
      ),
      body: playersAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(playersProvider)),
        data: (players) {
          final q = _query.trim().toLowerCase();
          final list = q.isEmpty
              ? players
              : players.where((p) => p.name.toLowerCase().contains(q)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 12,
                    color: kTextPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'BUSCAR JUGADOR',
                    prefixIcon: Icon(Icons.search, color: kTextMuted, size: 16),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) =>
                      _row(list[i], manifest.containsKey(list[i].id)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(Player p, bool hasImage) {
    final busy = _busyId == p.id;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kAccentBlue.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          PlayerAvatar(player: p, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kTextPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  hasImage ? 'CUSTOM' : 'PIXEL',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 5,
                    color: hasImage ? kAccentGreen : kTextMuted,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kAccentYellow,
              ),
            )
          else ...[
            _btn('SUBIR', kAccentGreen, () => _upload(p)),
            if (hasImage) _btn('QUITAR', kAccentRed, () => _remove(p)),
          ],
        ],
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: color.withValues(alpha: 0.2),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 5,
            color: color,
          ),
        ),
      ),
    ),
  );
}
