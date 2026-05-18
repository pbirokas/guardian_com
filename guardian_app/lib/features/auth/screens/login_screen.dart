import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

enum _Mode { main, otpPending, password }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _Mode _mode = _Mode.main;
  bool _loading = false;
  bool _isRegister = false;
  bool _obscure = true;
  String _sentEmail = '';
  String _pendingUserId = '';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();

  static final _emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[\w.\-]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await ref.read(authStateProvider.notifier).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        // Zeige den echten Fehler im Debug-Modus, damit wir ihn diagonstizieren können
        final msg = kDebugMode ? e.toString() : l.googleSignInHint;
        _showError(msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendOtp({String? overrideEmail}) async {
    final email = overrideEmail ?? _emailController.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      _showError(AppLocalizations.of(context).invalidEmailAddress);
      return;
    }
    setState(() => _loading = true);
    try {
      final userId = await ref.read(authServiceProvider).sendEmailOtp(email);
      if (mounted) {
        setState(() {
          _sentEmail = email;
          _pendingUserId = userId;
          _otpController.clear();
          _mode = _Mode.otpPending;
        });
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      _showError(AppLocalizations.of(context).invalidCode);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(authStateProvider.notifier)
          .confirmMagicLink(_pendingUserId, code);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_emailRegex.hasMatch(email) || password.isEmpty) return;
    if (_isRegister && _nameController.text.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      if (_isRegister) {
        await ref.read(authStateProvider.notifier).register(
            email, password, _nameController.text.trim());
      } else {
        await ref.read(authStateProvider.notifier).signIn(email, password);
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.chat_bubble_outline, size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                Text(l.appTitle,
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(l.appSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 48),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  _buildBody(l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) => switch (_mode) {
        _Mode.main => _buildMain(l),
        _Mode.otpPending => _buildOtpPending(l),
        _Mode.password => _buildPassword(l),
      };

  Widget _buildMain(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: _signInWithGoogle,
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('G',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(width: 10),
              Text(l.signInWithGoogle),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _orDivider(l),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendOtp(),
          decoration: InputDecoration(
            labelText: l.emailAddress,
            hintText: l.emailHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.emailLinkHint,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _sendOtp,
          child: Text(l.sendSignInLink),
        ),
        const SizedBox(height: 24),
        _orDivider(l),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _mode = _Mode.password),
          child: Text(l.signInWithPassword),
        ),
      ],
    );
  }

  Widget _buildOtpPending(AppLocalizations l) {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text(l.linkSent,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(
          l.linkSentDescription(_sentEmail),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 8),
          onSubmitted: (_) => _confirmOtp(),
          decoration: InputDecoration(
            hintText: '------',
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.outlineVariant,
                letterSpacing: 8,
                fontSize: 28),
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _confirmOtp,
            child: Text(l.verifyCode),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _sendOtp(overrideEmail: _sentEmail),
          child: Text(l.resend),
        ),
        TextButton(
          onPressed: () => setState(() {
            _mode = _Mode.main;
            _sentEmail = '';
            _pendingUserId = '';
          }),
          child: Text(l.useOtherEmail),
        ),
      ],
    );
  }

  Widget _buildPassword(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRegister) ...[
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l.displayName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.emailAddress,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitPassword(),
          decoration: InputDecoration(
            labelText: l.password,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitPassword,
          child: Text(_isRegister ? l.register : l.signIn),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _isRegister = !_isRegister),
          child: Text(_isRegister ? l.alreadyHaveAccount : l.noAccount),
        ),
        TextButton(
          onPressed: () => setState(() => _mode = _Mode.main),
          child: const Text('←'),
        ),
      ],
    );
  }

  Widget _orDivider(AppLocalizations l) => Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(l.or, style: const TextStyle(color: Colors.grey)),
          ),
          const Expanded(child: Divider()),
        ],
      );
}
