import 'package:flutter/foundation.dart';

/// One entry of a channel's published schedule.
@immutable
class LiveProgram {
  const LiveProgram({
    required this.title,
    this.startsAt,
    this.endsAt,
    this.posterUrl,
    this.description,
    this.episodeNumber,
  });

  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? posterUrl;
  final String? description;
  final int? episodeNumber;

  bool covers(DateTime moment) {
    final start = startsAt;
    final end = endsAt;
    if (start == null || end == null) return false;
    return !moment.isBefore(start) && moment.isBefore(end);
  }

  bool get upcoming {
    final start = startsAt;
    return start == null || start.isAfter(DateTime.now());
  }

  /// Local Arabic time label, e.g. `21:30`.
  String get timeLabel {
    final start = startsAt?.toLocal();
    if (start == null) return '';
    final hour = start.hour.toString().padLeft(2, '0');
    final minute = start.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  factory LiveProgram.fromMap(Map<String, dynamic> json) {
    DateTime? readTime(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return LiveProgram(
      title: (json['title'] as String?)?.trim() ?? '',
      startsAt: readTime(json['from']),
      endsAt: readTime(json['to']),
      posterUrl: json['product_poster'] as String?,
      description: json['description'] as String?,
      episodeNumber: (json['episode_number'] as num?)?.toInt(),
    );
  }
}

/// A live television channel with its playable stream and schedule.
///
/// Channels are curated in the app (see `LiveSource.seeds`), so they are always
/// present even when the schedule endpoint is unreachable — the card never
/// disappears from the home hero.
@immutable
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.description = '',
    this.headers = const <String, String>{},
    this.programs = const <LiveProgram>[],
    this.featured = true,
  });

  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String description;

  /// Request headers the stream host requires (referer/origin).
  final Map<String, String> headers;
  final List<LiveProgram> programs;
  final bool featured;

  bool get isLive => true;

  bool get hasStream => streamUrl.isNotEmpty;

  LiveProgram? get currentProgram {
    final now = DateTime.now();
    for (final program in programs) {
      if (program.covers(now)) return program;
    }
    return null;
  }

  LiveProgram? get nextProgram {
    final now = DateTime.now();
    for (final program in programs) {
      final start = program.startsAt;
      if (start != null && start.isAfter(now)) return program;
    }
    return null;
  }

  /// Upcoming schedule after the current programme.
  List<LiveProgram> get upcoming {
    final now = DateTime.now();
    return programs
        .where((program) {
          final end = program.endsAt;
          final start = program.startsAt;
          if (start == null) return false;
          if (end != null && !end.isAfter(now)) return false;
          return true;
        })
        .take(12)
        .toList(growable: false);
  }

  LiveChannel copyWith({
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? description,
    Map<String, String>? headers,
    List<LiveProgram>? programs,
    bool? featured,
  }) => LiveChannel(
    id: id,
    name: name ?? this.name,
    streamUrl: streamUrl ?? this.streamUrl,
    logoUrl: logoUrl ?? this.logoUrl,
    description: description ?? this.description,
    headers: headers ?? this.headers,
    programs: programs ?? this.programs,
    featured: featured ?? this.featured,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'streamUrl': streamUrl,
    'logoUrl': logoUrl,
    'description': description,
  };

  factory LiveChannel.fromJson(Map<String, dynamic> json) => LiveChannel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    streamUrl: json['streamUrl'] as String? ?? '',
    logoUrl: json['logoUrl'] as String?,
    description: json['description'] as String? ?? '',
  );
}
