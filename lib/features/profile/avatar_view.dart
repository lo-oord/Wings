import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';

/// Profile picture with a local-first cache.
///
/// Pictures are stored as bytes inside Firestore (`users/{uid}/private/avatar`)
/// because Firebase Storage is unavailable on the free plan. Each version is
/// cached on the device, so a rebuild never downloads the same image again.
class UserAvatar extends ConsumerStatefulWidget {
  const UserAvatar({
    super.key,
    required this.uid,
    this.photoVersion = 0,
    this.size = 44,
    this.name = '',
    this.localPath,
  });

  final String uid;
  final int photoVersion;
  final double size;
  final String name;
  final String? localPath;

  @override
  ConsumerState<UserAvatar> createState() => _UserAvatarState();
}

/// Wide profile banner.
///
/// Covers are stored as Firestore bytes (`users/{uid}/private/cover`) exactly
/// like avatars and are cached per `coverVersion`. When the owner has not set
/// one, the app's own gradient is drawn instead of an empty box.
class UserCover extends ConsumerStatefulWidget {
  const UserCover({
    super.key,
    required this.uid,
    this.coverVersion = 0,
    this.height = 150,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.md)),
  });

  final String uid;
  final int coverVersion;
  final double height;
  final BorderRadius borderRadius;

  @override
  ConsumerState<UserCover> createState() => _UserCoverState();
}

class _UserCoverState extends ConsumerState<UserCover> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UserCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.coverVersion != widget.coverVersion) {
      _load();
    }
  }

  void _load() {
    if (widget.uid.isEmpty) {
      _bytes = null;
      return;
    }
    _bytes = ref
        .read(coverRepositoryProvider)
        .fetch(uid: widget.uid, version: widget.coverVersion);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            palette.primary.withValues(alpha: 0.85),
            palette.primary.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: _bytes == null
            ? fallback
            : FutureBuilder<Uint8List?>(
                future: _bytes,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) return fallback;
                  return Image.memory(
                    data,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              ),
      ),
    );
  }
}

class _UserAvatarState extends ConsumerState<UserAvatar> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.photoVersion != widget.photoVersion) {
      _load();
    }
  }

  void _load() {
    final local = widget.localPath;
    if (local != null && File(local).existsSync()) {
      _bytes = null;
      return;
    }
    if (widget.uid.isEmpty) {
      _bytes = null;
      return;
    }
    _bytes = ref
        .read(avatarRepositoryProvider)
        .fetch(uid: widget.uid, version: widget.photoVersion);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final local = widget.localPath;
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: palette.surfaceAlt,
      border: Border.all(color: palette.border),
    );

    Widget child;
    if (local != null && File(local).existsSync()) {
      child = Image.file(File(local), fit: BoxFit.cover);
    } else if (_bytes == null) {
      child = _initials(context);
    } else {
      child = FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return _initials(context);
          return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
        },
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _initials(BuildContext context) {
    final source = widget.name.trim();
    final letter = source.isEmpty ? '?' : source.characters.first.toUpperCase();
    return Text(
      letter,
      style: context.text.titleMedium?.copyWith(
        color: context.palette.textSecondary,
      ),
    );
  }
}
