import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import 'admin_actions.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../core/errors/user_facing_error.dart';

/// Lightweight health view of the public sources the app depends on.
///
/// Nothing is probed automatically: a check runs only when the Owner taps it,
/// one tiny request per source, and the result is stored in `systemMonitor`.
class AdminMonitorScreen extends ConsumerStatefulWidget {
  const AdminMonitorScreen({super.key});

  @override
  ConsumerState<AdminMonitorScreen> createState() => _AdminMonitorScreenState();
}

class _AdminMonitorScreenState extends ConsumerState<AdminMonitorScreen> {
  bool _running = false;
  List<SourceHealth>? _lastRun;
  String _error = '';

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = '';
    });
    final actor = AdminActor.of(ref);
    try {
      final results = await ref
          .read(adminRepositoryProvider)
          .runMonitorChecks(actorUid: actor.uid, actorName: actor.name);
      ref.invalidate(monitorProvider);
      if (mounted) {
        setState(() {
          _running = false;
          _lastRun = results;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = userFacingError(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorProvider);
    return AdminGuard(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(
            Tr.of(context, ar: 'مراقبة النظام', en: 'System monitor'),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => ref.invalidate(monitorProvider),
            ),
          ],
        ),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => WingsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: Tr.of(context, ar: 'تعذّر التحميل', en: 'Failed to load'),
            message: loadFailedText(context),
            actionLabel: Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
            onAction: () => ref.invalidate(monitorProvider),
          ),
          data: (items) {
            final shown = _lastRun ?? items;
            return ListView(
              padding: const EdgeInsets.only(bottom: Space.xxxl),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.xs,
                  ),
                  child: WingsButton(
                    label: _running
                        ? Tr.of(context, ar: 'جارٍ الفحص…', en: 'Checking…')
                        : Tr.of(
                            context,
                            ar: 'فحص المصادر الآن',
                            en: 'Check sources now',
                          ),
                    icon: Icons.network_check_rounded,
                    expand: true,
                    loading: _running,
                    onPressed: _running ? null : _run,
                  ),
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.xs,
                    ),
                    child: Text(
                      _error,
                      style: context.text.labelSmall?.copyWith(
                        color: context.palette.danger,
                      ),
                    ),
                  ),
                for (final item in shown)
                  AdminCard(
                    title: item.label,
                    trailing: _StatusDot(health: item),
                    children: <Widget>[
                      if (item.neverChecked)
                        Text(
                          Tr.of(
                            context,
                            ar: 'لم يُنفَّذ أي فحص بعد. لا تُعرض حالة صحية دون فحص حقيقي.',
                            en: 'No check has run yet. Health is never assumed without a real probe.',
                          ),
                          style: context.text.bodySmall?.copyWith(
                            color: context.palette.textMuted,
                          ),
                        )
                      else ...<Widget>[
                        AdminKeyValue(
                          label: Tr.of(context, ar: 'الرابط', en: 'Endpoint'),
                          value: item.url,
                          mono: true,
                        ),
                        AdminKeyValue(
                          label: Tr.of(context, ar: 'الكود', en: 'HTTP'),
                          value: item.httpStatus == 0
                              ? '—'
                              : '${item.httpStatus}',
                        ),
                        AdminKeyValue(
                          label: Tr.of(context, ar: 'الاستجابة', en: 'Latency'),
                          value: '${item.latencyMs} ms',
                        ),
                        AdminKeyValue(
                          label: Tr.of(context, ar: 'آخر فحص', en: 'Checked'),
                          value: adminDate(item.checkedAt),
                        ),
                        AdminKeyValue(
                          label: Tr.of(
                            context,
                            ar: 'آخر نجاح',
                            en: 'Last success',
                          ),
                          value: adminDate(item.lastSuccessAt),
                        ),
                        AdminKeyValue(
                          label: Tr.of(
                            context,
                            ar: 'آخر فشل',
                            en: 'Last failure',
                          ),
                          value: adminDate(item.lastFailureAt),
                        ),
                        if (item.error.isNotEmpty)
                          AdminKeyValue(
                            label: Tr.of(context, ar: 'الخطأ', en: 'Error'),
                            value: item.error,
                            valueColor: context.palette.danger,
                          ),
                      ],
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.lg,
                    0,
                  ),
                  child: Text(
                    Tr.of(
                      context,
                      ar: 'الفحص يرسل طلبًا واحدًا صغيرًا لكل مصدر عند الضغط فقط، ويُخزَّن آخر نتيجة في Firestore. لا شيء من هذه المعلومات يظهر لأي عضو عادي.',
                      en: 'A check sends one small request per source on demand and stores the last result in Firestore. None of it is visible to ordinary members.',
                    ),
                    style: context.text.labelSmall?.copyWith(
                      color: context.palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.health});

  final SourceHealth health;

  @override
  Widget build(BuildContext context) {
    final color = health.neverChecked
        ? context.palette.textMuted
        : health.ok
        ? context.palette.success
        : context.palette.danger;
    final label = health.neverChecked
        ? Tr.of(context, ar: 'لم يُفحص', en: 'Not checked')
        : health.ok
        ? Tr.of(context, ar: 'متاح', en: 'Available')
        : Tr.of(context, ar: 'غير متاح', en: 'Unavailable');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: context.text.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}
