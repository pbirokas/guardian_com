import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  bool _emailLinkSent = false;
  final _emailController = TextEditingController();
  final _linkController = TextEditingController();
  bool _emailValid = false;

  static final _emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[\w.\-]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.signInFailed(e.toString()))),
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
      if (mounted) setState(() => _emailLinkSent = true);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithPastedLink() async {
    final url = _linkController.text.trim();
    if (url.isEmpty) return;

    setState(() => _loading = true);
    try {
      final result = await ref
          .read(authServiceProvider)
          .handleEmailLink(Uri.parse(url));
      if (result == null && mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.invalidLink)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                const Icon(Icons.chat_bubble_outline,
                    size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                Text(
                  l.appTitle,
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  l.appSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),

                if (_loading)
                  const CircularProgressIndicator()
                else if (_emailLinkSent)
                  _EmailLinkSentWidget(
                    email: _emailController.text.trim(),
                    isDesktop: _isDesktop,
                    linkController: _linkController,
                    onBack: () => setState(() {
                      _emailLinkSent = false;
                      _linkController.clear();
                    }),
                    onResend: _sendEmailLink,
                    onSignInWithLink: _signInWithPastedLink,
                  )
                else ...[
                  // ── Google Sign-In (nur mobil) ──
                  if (!_isDesktop) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: Text(l.signInWithGoogle),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(l.or,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── E-Mail-Link ──
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        _emailValid ? _sendEmailLink() : null,
                    onChanged: (v) => setState(() {
                      _emailValid = _emailRegex.hasMatch(v.trim());
                    }),
                    decoration: InputDecoration(
                      labelText: l.emailAddress,
                      hintText: l.emailHint,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email_outlined),
                      errorText:
                          _emailController.text.isNotEmpty && !_emailValid
                              ? l.invalidEmailAddress
                              : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _emailValid ? _sendEmailLink : null,
                      icon: const Icon(Icons.link),
                      label: Text(l.sendSignInLink),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.emailLinkHint,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailLinkSentWidget extends StatelessWidget {
  final String email;
  final bool isDesktop;
  final TextEditingController linkController;
  final VoidCallback onBack;
  final VoidCallback onResend;
  final VoidCallback onSignInWithLink;

  const _EmailLinkSentWidget({
    required this.email,
    required this.isDesktop,
    required this.linkController,
    required this.onBack,
    required this.onResend,
    required this.onSignInWithLink,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 56, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          l.linkSent,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l.linkSentDescription(email),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),

        if (isDesktop) ...[
          Text(
            l.desktopLinkInstructions,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: linkController,
            decoration: InputDecoration(
              labelText: l.pasteLinkLabel,
              hintText: 'https://guardian-app-b0f6c.firebaseapp.com/...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.open_in_browser),
            ),
            onSubmitted: (_) => onSignInWithLink(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSignInWithLink,
              icon: const Icon(Icons.login),
              label: Text(l.signIn),
            ),
          ),
        ] else ...[
          Text(
            l.mobileLinkInstructions,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],

        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onResend,
          icon: const Icon(Icons.refresh),
          label: Text(l.resend),
        ),
        TextButton(
          onPressed: onBack,
          child: Text(l.useOtherEmail),
        ),
      ],
    );
  }
}
