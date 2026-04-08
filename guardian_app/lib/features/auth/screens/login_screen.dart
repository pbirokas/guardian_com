import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  bool _emailLinkSent = false;
  final _emailController = TextEditingController();
  bool _emailValid = false;

  static final _emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[\w.\-]+$');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Anmeldung fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendEmailLink() async {
    final email = _emailController.text.trim();
    if (!_emailRegex.hasMatch(email)) return;

    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).sendSignInLink(email);
      if (mounted) {
        setState(() => _emailLinkSent = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Guardian Com',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sichere Kommunikation für Organisationen',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 48),

              if (_loading)
                const CircularProgressIndicator()
              else if (_emailLinkSent)
                _EmailLinkSentInfo(
                  email: _emailController.text.trim(),
                  onBack: () => setState(() => _emailLinkSent = false),
                  onResend: _sendEmailLink,
                )
              else ...[
                // ── Google Sign-In ──
                FilledButton.icon(
                  onPressed: _signInWithGoogle,
                  icon: const Icon(Icons.login),
                  label: const Text('Mit Google anmelden'),
                ),

                const SizedBox(height: 24),

                // ── Trennlinie ──
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('oder',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 24),

                // ── E-Mail-Link Login ──
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _emailValid ? _sendEmailLink() : null,
                  onChanged: (v) => setState(() {
                    _emailValid = _emailRegex.hasMatch(v.trim());
                  }),
                  decoration: InputDecoration(
                    labelText: 'E-Mail-Adresse',
                    hintText: 'name@beispiel.de',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email_outlined),
                    errorText:
                        _emailController.text.isNotEmpty && !_emailValid
                            ? 'Ungültige E-Mail-Adresse'
                            : null,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _emailValid ? _sendEmailLink : null,
                    icon: const Icon(Icons.link),
                    label: const Text('Anmeldelink senden'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wir senden dir einen Link per E-Mail.\n'
                  'Kein Passwort nötig.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Info-Widget das nach dem Versand des Links angezeigt wird.
class _EmailLinkSentInfo extends StatelessWidget {
  final String email;
  final VoidCallback onBack;
  final VoidCallback onResend;

  const _EmailLinkSentInfo({
    required this.email,
    required this.onBack,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 56, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Link gesendet!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Wir haben einen Anmeldelink an\n$email gesendet.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),
        Text(
          'Öffne die E-Mail und tippe auf den Link um dich anzumelden.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: onResend,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut senden'),
        ),
        TextButton(
          onPressed: onBack,
          child: const Text('Andere E-Mail verwenden'),
        ),
      ],
    );
  }
}
