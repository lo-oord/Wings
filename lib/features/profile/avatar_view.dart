import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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
