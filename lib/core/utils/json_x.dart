/// Defensive JSON accessors. The upstream documents are loosely typed, so every
/// read is tolerant and falls back instead of throwing.
extension JsonMapX on Map<String, dynamic>? {
  Map<String, dynamic>? obj(String key) {
    final value = this?[key];
    return value is Map<String, dynamic> ? value : null;
  }

  String? str(String key) {
    final value = this?[key];
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num) return value.toString();
    return null;
  }

  double? dbl(String key) {
    final value = this?[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  int? integer(String key) {
    final value = this?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool? boolean(String key) {
    final value = this?[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return null;
  }

  List<dynamic> list(String key) {
    final value = this?[key];
    return value is List ? value : const <dynamic>[];
  }
}

extension JsonListX on List<dynamic> {
  List<String> asStringList() =>
      map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
}

final RegExp _tags = RegExp(r'<[^>]*>');
final RegExp _entities = RegExp(r'&(nbsp|amp|quot|#39|lt|gt);');

/// Removes markup from upstream story fields.
String? cleanHtml(String? value) {
  if (value == null) return null;
  final text = value
      .replaceAll(_tags, ' ')
      .replaceAllMapped(_entities, (m) {
        return switch (m.group(1)) {
          'nbsp' => ' ',
          'amp' => '&',
          'quot' => '"',
          '#39' => "'",
          'lt' => '<',
          'gt' => '>',
          _ => ' ',
        };
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}
