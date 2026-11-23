import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/calcetto_logo.dart';
import '../widgets/pixel_button.dart';
import 'home_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final _ctrl = TextEditingController();
  String? _err;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(String v) {
    if (v.length < 2 || v.length > 20) return 'Must be 2–20 characters';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
      return 'Letters, numbers and underscore only';
    }
    return null;
  }

  Future<void> _confirm() async {
    final name = _ctrl.text.trim();
    final err = _validate(name);
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      await ref.read(userProvider.notifier).setUsername(name);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = 'Connection error — check your network';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CalcettoLogo(wordSize: 30),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder, width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ELIGE TU NOMBRE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: kFontUI,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Con este nombre entrarás al juego',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: kFontUI,
                        fontSize: 13,
                        color: kTextMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _ctrl,
                      autofocus: true,
                      maxLength: 20,
                      style: const TextStyle(
                        fontFamily: kFontUI,
                        fontSize: 15,
                        color: kTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Tu nombre',
                        counterText: '',
                        errorText: _err,
                      ),
                      onSubmitted: (_) => _confirm(),
                    ),
                    const SizedBox(height: 16),
                    _loading
                        ? const Center(child: CircularProgressIndicator(color: kAccentGreen))
                        : PixelButton(
                            label: 'ENTRAR',
                            onTap: _confirm,
                            color: kAccentGreen,
                            fontSize: 14,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
