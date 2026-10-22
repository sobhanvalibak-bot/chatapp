import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'utils.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (d) => Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Text(d.exceptionAsString(),
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ),
      );
  // مدیا سشن: نوتیفیکیشن پخش، کنترل لاک‌اسکرین و دکمه‌های هدفون
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.chat_app.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  try {
    await Api.init();
    if (Api.loggedIn) Api.connectWs();
  } catch (_) {}
  Api.onUnauthorized = () {
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => Api.loggedIn ? const HomePage() : const LoginPage()),
      (r) => false,
    );
  };
  runApp(const MyApp());
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF0E1621) : Colors.white;
  final bar = dark ? const Color(0xFF17212B) : Colors.white;
  final fg = dark ? Colors.white : Colors.black;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: tgBlue, primary: tgBlue, brightness: b),
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bar,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: fg),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xFF223040) : const Color(0xFFE3E5E8),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    }),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // وقتی اپ بسته/بک‌گراند میشه آفلاین حساب میشیم و «آخرین بازدید» ثبت میشه
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Api.loggedIn) Api.connectWs();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      Api.disconnectWs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Api.themeMode,
      builder: (_, mode, __) => MaterialApp(
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        title: 'Chat',
        scrollBehavior: const CupertinoScrollBehavior(),
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: Api.loggedIn ? const HomePage() : const LoginPage(),
      ),
    );
  }
}
