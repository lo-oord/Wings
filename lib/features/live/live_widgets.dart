import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_image.dart';
import '../../data/models/live_channel.dart';
import '../../data/sources/live_source.dart';

/// Pulsing red «مباشر» pill used on every live surface.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key, this.compact = false});

  final bool compact;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(_pulse),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? Space.xs + 2 : Space.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: BrandColors.live,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              Tr.of(context, ar: 'مباشر', en: 'LIVE'),
              style: context.text.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: widget.compact ? 8 : 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home hero rail with the app's live channels.
///
/// The rail is placed above the news feed and never depends on it, so the
/// channels stay visible while the catalogue is loading, erroring or offline.
class LiveChannelRail extends ConsumerWidget {
  const LiveChannelRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(liveChannelsProvider).value ?? LiveSource.seeds;
    if (channels.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: Space.lg,
            end: Space.sm,
            top: Space.sm,
          ),
          child: Row(
            children: <Widget>[
              Text(
                Tr.of(context, ar: 'قنوات مباشرة', en: 'Live channels'),
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: Space.sm),
              const LiveBadge(compact: true),
              const Spacer(),
              IconButton(
                tooltip: Tr.of(context, ar: 'تحديث', en: 'Refresh'),
                onPressed: () => ref.invalidate(liveChannelsProvider),
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 106,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.xs,
            ),
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, index) {
              final channel = channels[index];
              return _LiveChannelCard(
                channel: channel,
                onTap: () =>
                    context.push(RoutePaths.live(channel.id), extra: channel),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LiveChannelCard extends StatelessWidget {
  const _LiveChannelCard({required this.channel, required this.onTap});

  final LiveChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = channel.currentProgram;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        width: 236,
        padding: const EdgeInsets.all(Space.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: palette.border),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: <Color>[palette.surfaceAlt, palette.surface],
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 62,
              height: 62,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: palette.border),
              ),
              child: WingsImage(url: channel.logoUrl, fit: BoxFit.contain),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const LiveBadge(compact: true),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    now == null
                        ? Tr.of(
                            context,
                            ar: 'بث متواصل على مدار الساعة',
                            en: 'Streaming around the clock',
                          )
                        : now.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  if (now != null && now.timeLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '${now.timeLabel} · ${Tr.of(context, ar: 'الآن', en: 'NEXT')}',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
