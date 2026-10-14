import 'package:flutter/material.dart';

import '../services/license_service.dart';
import 'intro_screen.dart';

/// Программа ачылганда биринчи көрүнүүчү катмар.
///
/// Ачкыч мурда киргизилип, сакталган болсо — токтоосуз [IntroScreen]гe
/// (андан соң башкы экранга) өтөт, эч нерсе сурабайт.
/// Ачкыч жокто же туура эместе — программанын өзү ачылбайт, ушул жерде
/// токтоп, ачкыч сурайт.
class LicenseGateScreen extends StatefulWidget {
  const LicenseGateScreen({super.key});

  @override
  State<LicenseGateScreen> createState() => _LicenseGateScreenState();
}

class _LicenseGateScreenState extends State<LicenseGateScreen> {
  bool? _unlocked;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await LicenseService.isActivated();
    if (!mounted) return;
    setState(() => _unlocked = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked == true) return const IntroScreen();
    if (_unlocked == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1228),
        body: SizedBox.shrink(),
      );
    }
    return _KeyEntryScreen(onUnlocked: () => setState(() => _unlocked = true));
  }
}

class _KeyEntryScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const _KeyEntryScreen({required this.onUnlocked});

  @override
  State<_KeyEntryScreen> createState() => _KeyEntryScreenState();
}

class _KeyEntryScreenState extends State<_KeyEntryScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await LicenseService.activate(key);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _checking = false;
        _error = 'Ачкыч туура эмес';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1228),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.vpn_key_rounded,
                    color: Color(0xFF38BDF8), size: 40),
                const SizedBox(height: 18),
                const Text(
                  'СРС Генератор',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Программаны активдештирүү үчүн ачкычты киргизиңиз',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 13.5),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(
                      color: Colors.white, letterSpacing: 1.4, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    hintStyle: const TextStyle(color: Color(0x80BAE6FD)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    errorText: _error,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _checking ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0B1228),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Color(0xFF0B1228)),
                          )
                        : const Text('Активдештирүү',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
