import 'package:flutter/material.dart';

import '../core/widgets/wings_image.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';

/// The first frame the app draws while the local store, Firebase, downloads and
/// notifications are being prepared.
///
/// Before this screen existed the launch showed a bare system window (white or
/// black) until every service finished, which made the app look like it had
/// frozen. The splash is shown immediately, then replaced by [WingsApp].
class WingsSplashApp extends StatelessWidget {
  const WingsSplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wings',
      debugShowCheckedModeBanner: false,
      theme: buildWingsTheme(WingsPalette.light),
      darkTheme: buildWingsTheme(WingsPalette.dark),
      themeMode: ThemeMode.system,
      home: const WingsSplashScreen(),
    );
  }
}

class WingsSplashScreen extends StatefulWidget {
  const WingsSplashScreen({super.key});

  @override
  State<WingsSplashScreen> createState() => _WingsSplashScreenState();
}

class _WingsSplashScreenState extends State<WingsSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.92,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuint));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<WingsPalette>()!;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      backgroundColor: palette.background,
      body: Center(
        child: FadeTransition(
          opacity: reduceMotion ? kAlwaysCompleteAnimation : _fade,
          child: ScaleTransition(
            scale: reduceMotion ? kAlwaysCompleteAnimation : _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 132,
                  height: 132,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surface,
                    border: Border.all(color: palette.border),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.18),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const WingsMark(size: 84),
                ),
                const SizedBox(height: 18),
                Text(
                  'Wings',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'أنمي بلا حدود',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 92,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: palette.surfaceHigh,
                      color: palette.primary,
                    ),
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
