import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../data/models/app_update.dart';
import '../../features/settings/settings_screen.dart' show appInfoProvider;
import '../constants/app_links.dart';
import '../services/app_update_service.dart';
import '../services/app_feedback.dart';
import '../storage/local_store.dart';
import '../utils/tr.dart';
import 'wings_buttons.dart';
import 'wings_feedback.dart';
import 'wings_image.dart';

/// Key holding the release the user already answered, so the prompt is shown
/// once per published version and never on every launch.
const String _seenKey = 'update_prompt_seen';

/// Checks the website manifest and offers the release when it is newer.
///
/// [manual] changes only the feedback: an explicit check that finds nothing
/// confirms the app is up to date instead of staying silent.
Future<void> checkForUpdates(
  BuildContext context,
  WidgetRef ref, {
  bool manual = false,
}) async {
  final store = ref.read(localStoreProvider);
  final info = await ref.read(appInfoProvider.future);
  final service = ref.read(appUpdateServiceProvider);
  AppUpdate? update;
  try {
    update = await service.fetchLatest();
  } on Object {
    if (manual && context.mounted) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'تعذّر التحقق من التحديثات. تحقق من اتصالك وحاول مجددًا.',
          en: 'Could not check for updates. Check your connection and retry.',
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (update == null ||
      !update.isNewerThan(
        currentVersion: info.version,
        currentBuild: int.tryParse(info.buildNumber) ?? 0,
      )) {
    if (manual) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'أنت على أحدث إصدار من Wings. 🎉',
          en: 'You are on the latest version of Wings. 🎉',
        ),
      );
    }
    return;
  }
  final seen = store.getString(LocalStore.cacheBox, _seenKey);
  if (!manual && seen == update.id) return;
  await showUpdatePrompt(context, update: update, service: service);
  await store.setString(LocalStore.cacheBox, _seenKey, update.id);
}

Future<void> showUpdatePrompt(
  BuildContext context, {
  required AppUpdate update,
  required AppUpdateService service,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: true,
    barrierDismissible: !update.mandatory,
    builder: (dialogContext) =>
        UpdatePromptDialog(update: update, service: service),
  );
}

class UpdatePromptDialog extends StatefulWidget {
  const UpdatePromptDialog({
    super.key,
    required this.update,
    required this.service,
  });

  final AppUpdate update;
  final AppUpdateService service;

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

enum _Stage { intro, downloading, installing, failed }

class _UpdatePromptDialogState extends State<UpdatePromptDialog> {
  _Stage _stage = _Stage.intro;
  double _progress = 0;
  String? _error;
  CancelToken? _token;

  Future<void> _start() async {
    if (_stage == _Stage.downloading) return;
    unawaited(AppFeedback.tap());
    final token = CancelToken();
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = null;
      _token = token;
    });
    try {
      final file = await widget.service.download(
        widget.update,
        cancelToken: token,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() => _stage = _Stage.installing);
      final result = await widget.service.install(file);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        setState(() {
          _stage = _Stage.failed;
          _error = Tr.of(
            context,
            ar: 'تم تنزيل التحديث لكن لم يُفتح المثبّت. اسمح بتثبيت التطبيقات من هذا المصدر ثم أعد المحاولة.',
            en: 'The update downloaded but the installer did not open. Allow installs from this source and retry.',
          );
        });
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (!mounted) return;
      if (error is DioException && CancelToken.isCancel(error)) return;
      setState(() {
        _stage = _Stage.failed;
        _error = Tr.of(
          context,
          ar: 'تعذّر تنزيل التحديث. تحقق من اتصالك وحاول مجددًا.',
          en: 'The update could not be downloaded. Check your connection and try again.',
        );
      });
    }
  }

  Future<void> _openPage() async {
    final target = widget.update.pageUrl.isEmpty
        ? AppLinks.download
        : widget.update.pageUrl;
    await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
  }

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  List<String> get _notes => _isArabic
      ? (widget.update.notesAr.isNotEmpty
            ? widget.update.notesAr
            : widget.update.notesEn)
      : (widget.update.notesEn.isNotEmpty
            ? widget.update.notesEn
            : widget.update.notesAr);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final downloading = _stage == _Stage.downloading;
    final busy = downloading || _stage == _Stage.installing;
    final percent = (_progress * 100).clamp(0, 100).round();
    final width = MediaQuery.sizeOf(context).width;

    return PopScope(
      canPop: !widget.update.mandatory && !busy,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Space.xl,
          vertical: Space.xxl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: palette.border),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: palette.isDark ? 0.5 : 0.14,
                  ),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(context, palette, width),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      Space.md,
                      Space.xl,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (_notes.isNotEmpty) ...<Widget>[
                          Text(
                            Tr.of(
                              context,
                              ar: 'ما الجديد في هذا الإصدار',
                              en: "What's new in this release",
                            ),
                            style: context.text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: Space.sm),
                          for (final note in _notes)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: Space.sm - 2,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 15,
                                      color: palette.primary,
                                    ),
                                  ),
                                  const SizedBox(width: Space.sm),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: context.text.bodySmall?.copyWith(
                                        color: palette.textSecondary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: Space.md),
                        ],
                        if (_stage == _Stage.failed &&
                            _error != null) ...<Widget>[
                          Container(
                            padding: const EdgeInsets.all(Space.md),
                            decoration: BoxDecoration(
                              color: palette.danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(Radii.sm),
                              border: Border.all(
                                color: palette.danger.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: context.text.bodySmall?.copyWith(
                                color: palette.danger,
                                height: 1.5,
                              ),
                            ),
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _openPage,
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                              ),
                              label: Text(
                                Tr.of(
                                  context,
                                  ar: 'فتح صفحة التحديث',
                                  en: 'Open the update page',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.md),
                        ],
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      Space.md,
                      Space.xl,
                      Space.lg,
                    ),
                    child: busy
                        ? _progressArea(context, palette, percent, downloading)
                        : _actions(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, WingsPalette palette, double width) {
    final compact = width < 360;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.lg,
          Space.xl,
          Space.lg,
        ),
        decoration: BoxDecoration(gradient: palette.brandGradient),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: WingsMark(size: compact ? 30 : 36),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.update.mandatory
                        ? Tr.of(
                            context,
                            ar: 'تحديث مطلوب',
                            en: 'Update required',
                          )
                        : Tr.of(
                            context,
                            ar: 'تحديث جديد متاح',
                            en: 'A new update is available',
                          ),
                    style: context.text.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${Tr.of(context, ar: 'الإصدار', en: 'Version')} '
                    '${widget.update.version} · '
                    '${Tr.of(context, ar: 'حجم صغير', en: 'small download')}',
                    style: context.text.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressArea(
    BuildContext context,
    WingsPalette palette,
    int percent,
    bool downloading,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              downloading
                  ? Tr.of(context, ar: 'جارٍ التنزيل…', en: 'Downloading…')
                  : Tr.of(context, ar: 'جارٍ التثبيت…', en: 'Installing…'),
              style: context.text.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (downloading)
              Text(
                '$percent%',
                style: context.text.labelMedium?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        WingsProgressBar(value: downloading ? _progress : 1, height: 8),
        const SizedBox(height: Space.xs),
        Text(
          downloading
              ? Tr.of(
                  context,
                  ar: 'يُرجى إبقاء التطبيق مفتوحًا حتى ينتهي التنزيل.',
                  en: 'Keep Wings open until the download finishes.',
                )
              : Tr.of(
                  context,
                  ar: 'اتبع خطوات المثبّت لإكمال التحديث.',
                  en: 'Follow the installer steps to finish updating.',
                ),
          style: context.text.labelSmall?.copyWith(color: palette.textMuted),
        ),
        if (downloading) ...<Widget>[
          const SizedBox(height: Space.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () {
                _token?.cancel();
                setState(() => _stage = _Stage.intro);
              },
              child: Text(
                Tr.of(context, ar: 'إلغاء', en: 'Cancel'),
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _actions(BuildContext context) {
    return Row(
      children: <Widget>[
        if (!widget.update.mandatory) ...<Widget>[
          Expanded(
            child: WingsButton(
              label: Tr.of(context, ar: 'لاحقًا', en: 'Later'),
              variant: WingsButtonVariant.ghost,
              height: 44,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
        Expanded(
          flex: 2,
          child: WingsButton(
            label: Tr.of(
              context,
              ar: _stage == _Stage.failed ? 'إعادة المحاولة' : 'تحديث الآن',
              en: _stage == _Stage.failed ? 'Try again' : 'Update now',
            ),
            icon: _stage == _Stage.failed
                ? Icons.refresh_rounded
                : Icons.system_update_alt_rounded,
            height: 44,
            onPressed: _start,
          ),
        ),
      ],
    );
  }
}

/// Runs the update check once the first usable frame is on screen.
///
/// It never blocks start-up and never repeats the same release: the answered
/// version is remembered on the device.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Let the shell settle before a dialog can appear.
      Future<void>.delayed(const Duration(milliseconds: 1800), () async {
        if (!mounted || !Platform.isAndroid) return;
        if (!ref.read(settingsProvider).onboardingDone) return;
        await checkForUpdates(context, ref);
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
