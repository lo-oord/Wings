import 'package:dio/dio.dart';

import '../models/live_channel.dart';
import 'cartoony_crypto.dart';

/// Curated live channels published by the Carateen / Cartoony source.
///
/// The schedule endpoint returns an encrypted envelope with the playable HLS
/// URL and the day's programmes. The three channels this app ships are pinned
/// here as well, so a home-hero card never disappears when the endpoint is slow
/// or offline; the endpoint only refreshes names, logos and the schedule.
class LiveSource {
  LiveSource(this._dio);

  final Dio _dio;

  static const String baseUrl = 'https://cartoony.net';

  /// Public HLS endpoint served by the catalogue; it needs the site referer.
  static const Map<String, String> proxyHeaders = <String, String>{
    'Referer': '$baseUrl/',
    'Origin': baseUrl,
  };

  static const List<LiveChannel> seeds = <LiveChannel>[
    LiveChannel(
      id: 'spacetoon',
      name: 'سبيستون',
      description: 'قناة سبيستون — بث مباشر على مدار الساعة',
      logoUrl: '$baseUrl/assets/img/live/spacetoon.webp',
      streamUrl: 'https://live-uae-next.spacetoongo.com/ST_MENA_NEXT/hls/r9p2hjipmw2kl.m3u8',
    ),
    LiveChannel(
      id: 'mbc3',
      name: 'MBC 3',
      description: 'قناة MBC 3 للأطفال — بث مباشر',
      logoUrl: '$baseUrl/assets/img/live/mbc3.webp',
      streamUrl: 'https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-3-usa/5d58265a862a476dc7f97694addb5ded/index.m3u8',
    ),
    LiveChannel(
      id: '0c122742-f25e-462e-915a-26530068bb2b',
      name: 'شارع الأنمي الياباني',
      description: 'قناة الأنمي الياباني — حلقات متواصلة',
      logoUrl: 'https://cdn.spacetoongo.com/b9e89daf-be45-4c0b-be40-7724ebc969d7.png',
      streamUrl:
          '$baseUrl/api/sp/live/0c122742-f25e-462e-915a-26530068bb2b/master.m3u8',
      headers: proxyHeaders,
    ),
  ];

  static const Duration _ttl = Duration(minutes: 5);

  List<LiveChannel>? _cached;
  DateTime? _cachedAt;
  Future<List<LiveChannel>>? _pending;

  /// The pinned channels, always returned in a stable order.
  List<LiveChannel> get fallback => seeds;

  Future<List<LiveChannel>> channels({bool force = false}) {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _ttl) {
      return Future<List<LiveChannel>>.value(cached);
    }
    final pending = _pending;
    if (pending != null) return pending;
    final future = _load();
    _pending = future;
    return future
        .then((channels) {
          _cached = channels;
          _cachedAt = DateTime.now();
          return channels;
        })
        .whenComplete(() => _pending = null);
  }

  Future<List<LiveChannel>> _load() async {
    final byId = <String, LiveChannel>{for (final seed in seeds) seed.id: seed};
    try {
      final overview = await _request('/api/sp/live');
      if (overview is Map) {
        final channels = overview['channels'];
        if (channels is List) {
          for (final item in channels.whereType<Map>()) {
            final channel = _mapChannel(item.cast<String, dynamic>());
            if (channel != null && byId.containsKey(channel.id)) {
              final seed = byId[channel.id]!;
              byId[channel.id] = seed.copyWith(
                name: channel.name.isEmpty ? null : channel.name,
                logoUrl: channel.logoUrl,
                streamUrl: channel.streamUrl.isEmpty ? null : channel.streamUrl,
              );
            }
          }
        }
        final epg = overview['epg'];
        final current = overview['channel'];
        if (epg is List && current is Map) {
          final id = current['id']?.toString();
          final channel = id == null ? null : byId[id];
          if (channel != null) {
            byId[id!] = channel.copyWith(programs: _mapEpg(epg));
          }
        }
      }
    } on Object {
      // Keep the pinned channels when the overview is unavailable.
    }

    // A schedule per channel: the endpoint answers for the requested channel.
    for (final id in seeds.map((seed) => seed.id)) {
      final channel = byId[id];
      if (channel == null || channel.programs.isNotEmpty) continue;
      try {
        final payload = await _request('/api/sp/live?channel=$id');
        if (payload is! Map) continue;
        final epg = payload['epg'];
        if (epg is List) {
          byId[id] = channel.copyWith(programs: _mapEpg(epg));
        }
      } on Object {
        // A channel without a schedule still streams.
      }
    }
    return <LiveChannel>[
      for (final seed in seeds)
        if (byId[seed.id] != null) byId[seed.id]!,
    ];
  }

  LiveChannel? _mapChannel(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final name = json['name']?.toString() ?? '';
    final logo = json['logo']?.toString();
    final url = json['url']?.toString() ?? '';
    final resolvedUrl = url.isEmpty
        ? ''
        : (url.startsWith('http') ? url : '$baseUrl$url');
    return LiveChannel(
      id: id,
      name: name,
      streamUrl: resolvedUrl,
      logoUrl: logo == null || logo.isEmpty
          ? null
          : (logo.startsWith('http') ? logo : '$baseUrl$logo'),
      headers: url.startsWith('/api/') ? proxyHeaders : const {},
    );
  }

  List<LiveProgram> _mapEpg(List<dynamic> raw) {
    final programs = raw
        .whereType<Map>()
        .map((item) => LiveProgram.fromMap(item.cast<String, dynamic>()))
        .where((program) => program.title.isNotEmpty)
        .toList(growable: false);
    return programs;
  }

  Future<Object?> _request(String path) async {
    final response = await _dio.get<String>(
      '$baseUrl$path',
      options: Options(
        responseType: ResponseType.plain,
        headers: <String, String>{
          'Referer': '$baseUrl/',
          'Accept': 'application/json, text/plain, */*',
        },
      ),
    );
    final body = response.data;
    if (response.statusCode != 200 || body == null || body.isEmpty) {
      throw const FormatException('live endpoint unavailable');
    }
    return CartoonyCrypto.decode(body);
  }
}
