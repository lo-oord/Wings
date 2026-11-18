import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import 'admin_widgets.dart';

/// Moderation queue: review, resolve or dismiss reports.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() =>
      _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  String? _status = 'open';
  List<AdminReport> _reports = const <AdminReport>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(adminRepositoryProvider)
          .reports(status: _status);
      if (!mounted) return;
      setState(() {
        _reports = items;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل البلاغات. انشر القواعد المحدّثة وتحقق من الاتصال.';
      });
    }
  }

  Future<void> _review(AdminReport report, String status) async {
    final draft = await showAdminActionDialog(
      context,
      title: status == 'resolved'
          ? 'حل البلاغ'
          : status == 'dismissed'
          ? 'رفض البلاغ'
          : 'وسم البلاغ كمراجَع',
      reasonLabel: 'ملاحظة المراجعة',
      description: 'تُحفظ الملاحظة في البلاغ وتظهر في سجل الإدارة.',
    );
    if (draft == null) return;
    final actor = adminActorOf(ref);
    if (actor == null) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .reviewReport(
            actor: actor,
            report: report,
            status: status,
            note: draft.reason,
          );
      if (!mounted) return;
      context.showSnack('حُدّث البلاغ.');
      await _load();
    } on Object {
      if (mounted) {
        context.showSnack('تعذّر تحديث البلاغ.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OwnerGate(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text('البلاغات', style: context.text.titleMedium),
          actions: <Widget>[
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _load,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                children: <Widget>[
                  for (final entry in const <String?, String>{
                    'open': 'معلّقة',
                    'reviewed': 'تمت مراجعتها',
                    'resolved': 'محلولة',
                    'dismissed': 'مرفوضة',
                    null: 'الكل',
                  }.entries) ...<Widget>[
                    WingsFilterChip(
                      label: entry.value,
                      selected: _status == entry.key,
                      onTap: () {
                        setState(() => _status = entry.key);
                        _load();
                      },
                    ),
                    const SizedBox(width: Space.xs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    )
                  : _reports.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد بلاغات في هذا التصنيف.',
                        style: context.text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Space.lg,
                        0,
                        Space.lg,
                        Space.huge,
                      ),
                      itemCount: _reports.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, index) =>
                          _ReportCard(report: _reports[index], onReview: _review),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onReview});

  final AdminReport report;
  final Future<void> Function(AdminReport report, String status) onReview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.flag_rounded,
                size: 16,
                color: report.isOpen ? palette.warning : palette.textMuted,
              ),
              const SizedBox(width: Space.xs + 2),
              Expanded(
                child: Text(
                  '${report.targetType.isEmpty ? 'بلاغ' : report.targetType} · ${report.status}',
                  style: context.text.titleSmall?.copyWith(fontSize: 13.5),
                ),
              ),
              Text(
                adminMoment(report.createdAt),
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(report.reason, style: context.text.bodySmall),
          if (report.reviewNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.xs),
            Text(
              'ملاحظة: ${report.reviewNote}',
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: <Widget>[
              if (report.targetUid.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.person_search_rounded, size: 14),
                  label: const Text('الحساب'),
                  onPressed: () =>
                      context.push(RoutePaths.developerUser(report.targetUid)),
                ),
              if (report.isOpen)
                ActionChip(
                  avatar: const Icon(Icons.visibility_rounded, size: 14),
                  label: const Text('مراجَع'),
                  onPressed: () => onReview(report, 'reviewed'),
                ),
              if (report.isOpen)
                ActionChip(
                  avatar: const Icon(Icons.task_alt_rounded, size: 14),
                  label: const Text('حل'),
                  onPressed: () => onReview(report, 'resolved'),
                ),
              if (report.isOpen)
                ActionChip(
                  avatar: const Icon(Icons.block_rounded, size: 14),
                  label: const Text('رفض'),
                  onPressed: () => onReview(report, 'dismissed'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
