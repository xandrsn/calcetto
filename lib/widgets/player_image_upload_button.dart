import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/player.dart';
import '../services/player_images.dart';
import '../theme/app_theme.dart';

/// Lets ANY user set/replace a player's global photo — from the gallery on
/// Android, a file dialog on Windows. Images are shared by everyone, so this is
/// intentionally not gated to admins.
class PlayerImageUploadButton extends ConsumerStatefulWidget {
  final Player player;
  final String label;

  const PlayerImageUploadButton({
    super.key,
    required this.player,
    this.label = 'SUBIR FOTO',
  });

  @override
  ConsumerState<PlayerImageUploadButton> createState() =>
      _PlayerImageUploadButtonState();
}

class _PlayerImageUploadButtonState
    extends ConsumerState<PlayerImageUploadButton> {
  bool _busy = false;

  Future<void> _pick() async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
    } catch (e) {
      _toast('No se pudo abrir la galería');
      return;
    }
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      await ref
          .read(playerImageServiceProvider)
          .upload(widget.player.id, bytes);
      ref.invalidate(playerImagesProvider);
      _toast('Foto actualizada');
    } catch (e) {
      _toast('Error al subir la foto');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    return GestureDetector(
      onTap: _busy ? null : _pick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kSurface2,
          border: Border.all(color: kAccentBlue, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kAccentBlue,
                ),
              )
            else
              const Icon(Icons.photo_camera, size: 14, color: kAccentBlue),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 11,
                color: kAccentBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
