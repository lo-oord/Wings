import 'package:share_plus/share_plus.dart';

import '../../data/models/anime.dart';
import '../constants/app_links.dart';

class ShareService {
  /// Shares arbitrary text (episode titles, invite copy) through the platform
  /// share sheet. Cancellation is handled by the platform and needs no action.
  Future<void> shareText(String text, {String? subject}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: trimmed, subject: subject),
    );
  }

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
    buffer
      ..writeln()
      ..writeln(AppLinks.anime(anime.id));
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
