import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'core/firebase_bootstrap.dart';
import 'features/account/account.dart';
import 'features/badges/badges.dart';
import 'features/compliance/compliance.dart';
import 'features/onboarding/onboarding_feature.dart';
import 'features/social/social.dart';
import 'home_screen.dart';

const _startupPosterAsset = 'assets/images/snap_and_go_background.png';

// 1. Define the Global Key once at the top level
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  final storedAgeEligibility = await AgeEligibilityStorage.load();
  if (storedAgeEligibility?.allowsConnectedFeatures == true) {
    await FirebaseBootstrap.initialize();
  }
  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );
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

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<String>? _localReminderTapSubscription;
  final Set<String> _handledLinks = {};
  final Set<String> _handledMessageIds = {};
  bool _enablingConnectedServices = false;

  @override
  void initState() {
    super.initState();
    final appLinks = AppLinks();
    try {
      _linkSubscription = appLinks.uriLinkStream.listen(
        _openAppLink,
        onError: (Object error) => debugPrint('App link stream failed: $error'),
      );
      unawaited(_openInitialLink(appLinks));
    } catch (error) {
      debugPrint('App links are unavailable: $error');
    }
    _localReminderTapSubscription = WorkoutReminderNotifications
        .instance.friendWorkoutNotificationTaps
        .listen((shareId) => unawaited(_openWorkoutShare(shareId)));
    if (FirebaseBootstrap.isAvailable) {
      unawaited(_enableConnectedServices());
    }
  }

  Future<void> _enableConnectedServices() async {
    if (_openedMessageSubscription != null ||
        _enablingConnectedServices ||
        !FirebaseBootstrap.isAvailable) {
      return;
    }
    _enablingConnectedServices = true;
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      _openedMessageSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_openPushNotification);
      _foregroundMessageSubscription =
          FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      await _openInitialNotifications();
    } finally {
      _enablingConnectedServices = false;
    }
  }

  Future<void> _openInitialLink(AppLinks appLinks) async {
    try {
      final uri = await appLinks.getInitialLink();
      if (uri == null) return;
      // Let the startup poster choose the local onboarding/home destination
      // before placing the social invite above it.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      _openAppLink(uri);
    } catch (error) {
      debugPrint('Could not read the initial app link: $error');
    }
  }

  Future<void> _openInitialNotifications() async {
    RemoteMessage? initialMessage;
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    } catch (error) {
      debugPrint('Could not read the initial notification: $error');
    }
    // Allow onboarding/home to replace the startup poster before placing a
    // deep-linked workout above it.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (initialMessage != null) _openPushNotification(initialMessage);
    final localShareId =
        WorkoutReminderNotifications.instance.takeInitialFriendWorkoutShareId();
    if (localShareId != null) await _openWorkoutShare(localShareId);
  }

  void _openAppLink(Uri uri) {
    final workout = SocialPushNotification.fromUri(uri);
    if (workout != null) {
      if (!_handledLinks.add(uri.toString())) return;
      unawaited(_openWorkoutShare(workout.shareId));
      return;
    }
  }

  void _openPushNotification(RemoteMessage message) {
    final notification = SocialPushNotification.fromData(message.data);
    if (notification == null) return;
    final messageKey = message.messageId ??
        '${notification.type.wireName}:${notification.shareId}:'
            '${message.sentTime?.millisecondsSinceEpoch ?? 0}';
    if (!_handledMessageIds.add(messageKey)) return;
    unawaited(_openWorkoutShare(notification.shareId));
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = SocialPushNotification.fromData(message.data);
    if (notification == null) return;
    final title = message.notification?.title ?? 'Friend workout update';
    final body = message.notification?.body ?? 'Open the workout for details.';
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$title\n$body'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => unawaited(
              _openWorkoutShare(notification.shareId),
            ),
          ),
        ),
      );
  }

  Future<void> _openWorkoutShare(String shareId) async {
    var navigator = navigatorKey.currentState;
    for (var attempt = 0; navigator == null && attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      navigator = navigatorKey.currentState;
    }
    if (navigator == null || !mounted) return;

    final eligibility =
        await ref.read(ageEligibilityProvider.notifier).ensureLoaded();
    if (!eligibility.allowsConnectedFeatures) return;

    if (FirebaseAuth.instance.currentUser == null) {
      await navigator.push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const AccountScreen(closeAfterSignIn: true),
        ),
      );
      if (FirebaseAuth.instance.currentUser == null) return;
    }
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => SharedWorkoutInboxScreen(initialShareId: shareId),
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _openedMessageSubscription?.cancel();
    _localReminderTapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ageEligibility = ref.watch(ageEligibilityProvider);
    final firebaseAvailable = ref.watch(firebaseAvailabilityProvider);
    if (ageEligibility.allowsConnectedFeatures && firebaseAvailable) {
      unawaited(_enableConnectedServices());
      ref.watch(deviceRegistrationProvider);
      // Keep legacy workout sender profiles readable for older shares.
      ref.watch(friendAccessSyncProvider);
      ref.watch(socialBadgeSyncProvider);
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
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
    final ageEligibility =
        await ref.read(ageEligibilityProvider.notifier).ensureLoaded();
    if (!mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    final destination = ageEligibility.selection == null
        ? AgeEligibilityScreen(
            onFinished: (selection) async {
              if (selection.allowsConnectedFeatures) {
                await ref
                    .read(firebaseAvailabilityProvider.notifier)
                    .retry();
              }
              if (!mounted) return;
              final next = onboarding.completed
                  ? const HomeScreen()
                  : OnboardingScreen(
                      onFinished: () => navigator.pushReplacement(
                        _fadeRoute(const HomeScreen()),
                      ),
                    );
              navigator.pushReplacement(_fadeRoute(next));
            },
          )
        : onboarding.completed
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
