import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_state_provider.dart';
import '../providers/local_store.dart';
import '../theme/app_theme.dart';

/// Export / import of the on-device data as JSON text (copy to clipboard, paste
/// to restore). Only shown when the active store is the local one.
class LocalBackupButton extends ConsumerWidget {
  const LocalBackupButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(githubServiceProvider);
    if (store is! LocalStore) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Copia de seguridad',
      icon: const Icon(Icons.save_alt, color: kTextMuted, size: 18),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _BackupDialog(store: store, ref: ref),
      ),
    );
  }
}

class _BackupDialog extends StatefulWidget {
  final LocalStore store;
  final WidgetRef ref;
  const _BackupDialog({required this.store, required this.ref});

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final _ctrl = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: widget.store.exportJson()));
    setState(() => _msg = 'Copiado al portapapeles');
  }

  Future<void> _import() async {
    try {
      await widget.store.importJson(_ctrl.text.trim());
      widget.ref.invalidate(playersProvider);
      widget.ref.invalidate(currentMatchdayProvider);
      widget.ref.invalidate(currentMatchdayNumberProvider);
      widget.ref.invalidate(pastMatchdaysProvider);
      if (mounted) Navigator.pop(context);
    } on FormatException {
      setState(() => _msg = 'Archivo no valido');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: kSurface,
    title: const Text('COPIA DE SEGURIDAD'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Datos solo en este dispositivo. Exporta y pega el JSON '
            'para moverlos a otro.'),
        TextField(
          controller: _ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Pega aqui para importar'),
        ),
        if (_msg != null) Text(_msg!),
      ],
    ),
    actions: [
      TextButton(onPressed: _export, child: const Text('EXPORTAR')),
      TextButton(onPressed: _import, child: const Text('IMPORTAR')),
    ],
  );
}
