import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import 'admin_widgets.dart';

/// Append-only audit log of every administrative action.
class AdminLogScreen extends ConsumerStatefulWidget {
  const AdminLogScreen({super.key});

  @override
  ConsumerState<AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends ConsumerState<AdminLogScreen> {
  List<AdminActionRecord> _items = const <AdminActionRecord>[];
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
      final items = await ref.read(adminRepositoryProvider).recentActions();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل السجل.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OwnerGate(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text('سجل الإجراءات', style: context.text.titleMedium),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _load,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              )
            : _items.isEmpty
            ? Center(
                child: Text(
                  'لا توجد إجراءات مسجّلة بعد.',
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.huge,
                ),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                itemBuilder: (context, index) {
                  final action = _items[index];
                  return AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                action.action,
                                style: context.text.titleSmall?.copyWith(
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              adminMoment(action.createdAt),
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${action.actorName.isEmpty ? action.actorUid : action.actorName}'
                          ' ← ${action.targetUsername.isEmpty ? action.targetUid : '@${action.targetUsername}'}',
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                        if (action.reason.isNotEmpty) ...<Widget>[
                          const SizedBox(height: Space.xs),
                          Text(
                            action.reason,
                            style: context.text.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
