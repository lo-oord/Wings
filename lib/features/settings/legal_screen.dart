import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_layout.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});

  final String kind;

  bool get _isPrivacy => kind == 'privacy';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final sections = _isPrivacy ? _privacy(context) : _terms(context);

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(
          _isPrivacy ? l10n.settingsPrivacyPolicy : l10n.settingsTerms,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xxxl,
        ),
        children: <Widget>[
          Text(
            _isPrivacy ? l10n.settingsPrivacyPolicy : l10n.settingsTerms,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'آخر تحديث: نوفمبر 2026',
            style: context.text.labelSmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: Space.lg),
          for (final section in sections) ...<Widget>[
            Text(
              section.$1,
              style: context.text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              section.$2,
              style: context.text.bodyMedium?.copyWith(
                color: palette.textSecondary,
                height: 1.8,
              ),
            ),
            const SizedBox(height: Space.lg),
          ],
        ],
      ),
    );
  }

  List<(String, String)> _privacy(BuildContext context) => <(String, String)>[
    (
      'البيانات على جهازك',
      'تُحفظ مكتبتك ومفضلتك وسجل المشاهدة وإعدادات التنزيلات على جهازك فقط. '
          'لا تُرسل هذه البيانات إلى أي خادم تابع لـ Wings.',
    ),
    (
      'لا جمع للبيانات الشخصية',
      'لا يطلب التطبيق بريدك أو اسمك لاستخدامه كزائر، ولا يتضمن أدوات تتبع أو إعلانات.',
    ),
    (
      'الحساب',
      'واجهات الحساب معروضة للاستخدام المستقبلي. عند ربط خدمة مصادقة، ستُوضَّح '
          'البيانات التي تُزامن قبل تفعيلها.',
    ),
    (
      'الخدمات الخارجية',
      'تُحمَّل بيانات الأعمال والصور من كتالوج عام، ولذلك يصل عنوان IP الخاص بك '
          'إلى تلك الخدمة كأي طلب ويب عادي.',
    ),
    (
      'حذف بياناتك',
      'يمكنك مسح ذاكرة التخزين المؤقت وسجل البحث وسجل المشاهدة من صفحة الخصوصية '
          'في الإعدادات، وحذف ملفات التنزيل من مدير التنزيلات.',
    ),
  ];

  List<(String, String)> _terms(BuildContext context) => <(String, String)>[
    (
      'طبيعة التطبيق',
      'Wings واجهة لعرض بيانات أعمال الأنمي وتنظيم متابعتك. جميع حقوق الأعمال '
          'والحلقات محفوظة لأصحابها.',
    ),
    (
      'الاستخدام الشخصي',
      'يُستخدم التطبيق للاستخدام الشخصي غير التجاري. لا يجوز إعادة نشر المحتوى أو '
          'بيعه.',
    ),
    (
      'توفر المصادر',
      'يعتمد العرض على كتالوج عام قد يتغير أو يتوقف جزئياً. لا نضمن استمرار توفر '
          'أي عمل أو حلقة أو سيرفر.',
    ),
    (
      'التنزيلات',
      'عند تفعيل التنزيل، أنت مسؤول عن الالتزام بقوانين بلدك وبحقوق أصحاب الأعمال.',
    ),
    (
      'الضمان',
      'يُقدَّم التطبيق «كما هو» دون ضمانات صريحة أو ضمنية تتعلق بالتوفر أو '
          'الملاءمة لغرض معين.',
    ),
    (
      'التغييرات',
      'قد تُحدَّث هذه الشروط مع تطور التطبيق، وسيظهر تاريخ آخر تحديث في أعلى الصفحة.',
    ),
  ];
}
