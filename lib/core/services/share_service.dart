import 'package:share_plus/share_plus.dart';

import '../../data/models/anime.dart';

class ShareService {
  Future<void> shareAnime(Anime anime, {String? footer}) async {
    final buffer = StringBuffer()
      ..writeln(anime.title)
      ..writeln(
        anime.englishTitle != null && anime.englishTitle != anime.title
            ? anime.englishTitle
            : '',
      );
    if (anime.genres.isNotEmpty) {
      buffer.writeln(anime.genres.take(3).join(' • '));
    }
    if (anime.rating != null) {
      buffer.writeln('★ ${anime.rating!.toStringAsFixed(1)}');
    }
    if (footer != null) {
      buffer
        ..writeln()
        ..writeln(footer);
    }
    await SharePlus.instance.share(
      ShareParams(text: buffer.toString().trim(), subject: anime.title),
    );
  }
}
