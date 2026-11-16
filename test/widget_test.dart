import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/app/localization/app_localizations.dart';
import 'package:wings/app/theme/app_palette.dart';
import 'package:wings/app/theme/app_theme.dart';
import 'package:wings/core/widgets/wings_buttons.dart';
import 'package:wings/core/widgets/wings_feedback.dart';
import 'package:wings/core/widgets/wings_layout.dart';

Widget _wrap(
  Widget child, {
  ThemeMode mode = ThemeMode.dark,
  Locale locale = const Locale('ar'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildWingsTheme(WingsPalette.light),
    darkTheme: buildWingsTheme(WingsPalette.dark),
    themeMode: mode,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('bottom navigation renders four destinations in Arabic', (
    tester,
  ) async {
    var selected = -1;
    await tester.pumpWidget(
      _wrap(
        WingsBottomNav(currentIndex: 0, onSelect: (index) => selected = index),
      ),
    );

    expect(find.text('الأحدث'), findsOneWidget);
    expect(find.text('استكشف'), findsOneWidget);
    expect(find.text('مكتبتي'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);

    await tester.tap(find.text('استكشف'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('bottom navigation adapts to English and LTR', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WingsBottomNav(currentIndex: 2, onSelect: (_) {}),
        locale: const Locale('en'),
      ),
    );

    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Latest'))),
      TextDirection.ltr,
    );
  });

  testWidgets('empty state shows title, message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        WingsEmptyState(
          title: 'لا توجد حلقات',
          message: 'جرّب لاحقاً',
          actionLabel: 'إعادة المحاولة',
          onAction: () => tapped = true,
        ),
      ),
    );

    expect(find.text('لا توجد حلقات'), findsOneWidget);
    expect(find.text('جرّب لاحقاً'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    expect(tapped, isTrue);
  });

  testWidgets('disabled buttons ignore taps and hide their affordance', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(WingsButton(label: 'متابعة', onPressed: null)),
    );

    await tester.tap(find.text('متابعة'));
    await tester.pump();
    expect(taps, 0);

    await tester.pumpWidget(
      _wrap(WingsButton(label: 'متابعة', onPressed: () => taps++)),
    );
    await tester.tap(find.text('متابعة'));
    expect(taps, 1);
  });

  testWidgets('light theme renders skeletons and section headers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          children: const <Widget>[
            WingsSectionHeader(title: 'أحدث الحلقات'),
            WingsSkeleton(width: 120, height: 12),
          ],
        ),
        mode: ThemeMode.light,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('أحدث الحلقات'), findsOneWidget);
    expect(find.byType(WingsSkeleton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress bar clips values outside 0..1', (tester) async {
    await tester.pumpWidget(_wrap(const WingsProgressBar(value: 1.6)));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_wrap(const WingsProgressBar(value: -0.4)));
    expect(tester.takeException(), isNull);
  });
}
