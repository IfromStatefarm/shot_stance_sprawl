import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'features/onboarding/onboarding.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/workout_reminder_notifications.dart';
import 'home_screen.dart';

const _startupPosterAsset = 'assets/images/snap_and_go_background.png';

// 1. Define the Global Key once at the top level
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await WorkoutReminderNotifications.instance.initialize();
  await _precacheStartupPoster();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
  binding.allowFirstFrame();
}

Future<void> _precacheStartupPoster() {
  final completer = Completer<void>();
  const provider = AssetImage(_startupPosterAsset);
  final stream = provider.resolve(ImageConfiguration(bundle: rootBundle));
  late final ImageStreamListener listener;

  void complete() {
    stream.removeListener(listener);
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  listener = ImageStreamListener(
    (_, __) => complete(),
    onError: (_, __) => complete(),
  );
  stream.addListener(listener);

  return completer.future.timeout(
    const Duration(seconds: 3),
    onTimeout: complete,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Snap & Go',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const StartupPosterScreen(),
    );
  }
}

class StartupPosterScreen extends ConsumerStatefulWidget {
  const StartupPosterScreen({super.key});

  @override
  ConsumerState<StartupPosterScreen> createState() =>
      _StartupPosterScreenState();
}

class _StartupPosterScreenState extends ConsumerState<StartupPosterScreen> {
  static const _minimumDisplayTime = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_minimumDisplayTime, _showHomeScreen);
  }

  Future<void> _showHomeScreen() async {
    if (!mounted) {
      return;
    }

    final onboarding =
        await ref.read(onboardingProvider.notifier).ensureLoaded();
    if (!mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    final destination = onboarding.completed
        ? const HomeScreen()
        : OnboardingScreen(
            onFinished: () => navigator.pushReplacement(
              _fadeRoute(const HomeScreen()),
            ),
          );

    navigator.pushReplacement(_fadeRoute(destination));
  }

  PageRouteBuilder<void> _fadeRoute(Widget screen) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => screen,
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090000),
      body: SizedBox.expand(
        child: Image(
          image: AssetImage(_startupPosterAsset),
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
