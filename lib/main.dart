import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'views/main_screen.dart';
import 'views/login_screen.dart';
import 'views/intro_screen.dart';
import 'controllers/app_state.dart';
import 'controllers/notification_service.dart';
import 'controllers/local_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _ensureFirebaseInitialized();

  await Hive.initFlutter();
  await LocalService.init();
  await NotificationService.init();
  await AppState.loadLocalSettings();
  // We will request permissions in IntroScreen/LoginScreen for better UX

  runApp(const SNoteApp());
}

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F7BFF),
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFFAFC6FF) : const Color(0xFF315CCB),
          onPrimary: isDark ? const Color(0xFF102653) : Colors.white,
          primaryContainer: isDark
              ? const Color(0xFF1E345F)
              : const Color(0xFFDDE6FF),
          onPrimaryContainer: isDark
              ? const Color(0xFFE6EDFF)
              : const Color(0xFF0D214B),
          secondary: isDark ? const Color(0xFF8BD7D1) : const Color(0xFF226C68),
          surface: isDark ? const Color(0xFF101418) : const Color(0xFFFBFCFF),
          surfaceContainerLow: isDark
              ? const Color(0xFF171C22)
              : const Color(0xFFFFFFFF),
          surfaceContainer: isDark
              ? const Color(0xFF1D232B)
              : const Color(0xFFF3F5FA),
          surfaceContainerHigh: isDark
              ? const Color(0xFF252C35)
              : const Color(0xFFECEFF6),
          surfaceContainerHighest: isDark
              ? const Color(0xFF303842)
              : const Color(0xFFE6EAF2),
          onSurface: isDark ? const Color(0xFFE8ECF2) : const Color(0xFF171B22),
          onSurfaceVariant: isDark
              ? const Color(0xFFC4CBD6)
              : const Color(0xFF525A66),
          outlineVariant: isDark
              ? const Color(0xFF3F4854)
              : const Color(0xFFD5DAE3),
          error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
          errorContainer: isDark
              ? const Color(0xFF5F201D)
              : const Color(0xFFFFDAD6),
          onErrorContainer: isDark
              ? const Color(0xFFFFEDEA)
              : const Color(0xFF410002),
        );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.48 : 1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurface, fontSize: 12),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF303842)
            : const Color(0xFF32363D),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'SNote',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const _AppLaunchGate(),
        );
      },
    );
  }
}

class _AppLaunchGate extends StatefulWidget {
  const _AppLaunchGate();

  @override
  State<_AppLaunchGate> createState() => _AppLaunchGateState();
}

class _AppLaunchGateState extends State<_AppLaunchGate> {
  Widget? _destination;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final showIntro = prefs.getBool('onboarding_done') != true;
    if (showIntro) {
      if (!mounted) return;
      setState(() => _destination = const IntroScreen());
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _destination = const LoginScreen());
      return;
    }

    final error = await AppState.hydrateSignedInUser(
      currentUser,
      fallbackEmail: currentUser.email,
    );
    if (error == null) {
      NotificationService.checkAndNotifyPending();
    }
    if (!mounted) return;
    setState(() {
      _destination = error == null
          ? const MainScreen()
          : LoginScreen(initialMessage: error);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_destination != null) return _destination!;
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}


