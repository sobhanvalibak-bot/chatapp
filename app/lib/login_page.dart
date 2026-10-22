import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'home_page.dart';
import 'utils.dart';

/// دیالوگ تغییر آدرس سرور (برای زمانی که سرور از Termux به هاست منتقل شد)
Future<bool> showServerDialog(BuildContext context) async {
  final c = TextEditingController(text: Api.baseUrl);
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('Server address'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: c,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          placeholder: 'http://127.0.0.1:3000',
        ),
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await Api.setBaseUrl(c.text);
    if (Api.loggedIn) Api.connectWs();
    return true;
  }
  return false;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  final _p2 = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = Api.notice;
    Api.notice = null;
  }

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final u = _u.text.trim();
    final p = _p.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Enter username and password');
      return;
    }
    if (_register && p != _p2.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.auth(_register ? '/register' : '/login', u, p);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (r) => false,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF1F3F5),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Server address',
                icon: const Icon(CupertinoIcons.gear, color: Colors.grey),
                onPressed: () async {
                  if (await showServerDialog(context)) setState(() {});
                },
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF5BB5F5), tgBlue],
                        ),
                      ),
                      child: const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 52),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _register ? 'Create account' : 'Sign in',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Api.baseUrl,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _u,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: _dec('Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _p,
                      obscureText: _hide,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_register) _submit();
                      },
                      decoration: _dec(
                        'Password',
                        suffix: IconButton(
                          icon: Icon(_hide ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                              size: 20, color: Colors.grey),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _p2,
                        obscureText: _hide,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: _dec('Repeat password'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tgBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(_register ? 'Sign up' : 'Sign in',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(_register ? 'Have an account? Sign in' : "Don't have an account? Sign up"),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
