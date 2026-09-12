import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_main.dart';

Widget selectMindMateRoot({required bool isWeb, required Widget mobileApp}) {
  return isWeb ? const MindMateAdminApp() : mobileApp;
}

typedef AppInitializer = Future<void> Function();

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.initializer,
    required this.child,
    this.timeout = const Duration(seconds: 15),
  });

  final AppInitializer initializer;
  final Widget child;
  final Duration timeout;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Object? _error;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _ready = false;
      _error = null;
    });
    try {
      await widget.initializer().timeout(widget.timeout);
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    if (_error != null) {
      return _StartupFailure(error: _error!, onRetry: _initialize);
    }
    return const _StartupLoading();
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      backgroundColor: Color(0xFFFFFCF4),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Starting MindMate…'),
          ],
        ),
      ),
    ),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFFFFFCF4),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'MindMate could not start',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your connection and app configuration, then try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Startup code: ${_codeFor(error)}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    ),
  );

  static String _codeFor(Object error) {
    if (error is TimeoutException) return 'startup-timeout';
    final value = RegExp(
      r'\b[a-z]+(?:-[a-z]+)+\b',
    ).firstMatch(error.toString())?.group(0);
    return value ?? 'startup-failed';
  }
}
