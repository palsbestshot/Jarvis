// DishImageService — resolves a free, CC-licensed thumbnail URL for an
// Indian dish name. Used by the Dish Picker grid (Rakhi) and the
// backfill script.
//
// Strategy (first hit wins):
//   1. Openverse — api.openverse.org/v1/images/ (keyless, 100 req/hr
//      anon, CC0/PDM/BY/BY-SA only). Returns results[0].url.
//   2. Wikipedia — /api/rest_v1/page/summary/<Dish> — returns
//      thumbnail.source if the dish has a Wiki page.
//
// Returns null if both fail. Caller falls back to an emoji placeholder.

import 'dart:convert';
import 'package:http/http.dart' as http;

class DishImageService {
  static const _openverseBase = 'https://api.openverse.org/v1/images/';
  static const _wikiBase = 'https://en.wikipedia.org/api/rest_v1/page/summary/';
  static const _timeout = Duration(seconds: 5);

  /// Returns a usable thumbnail URL for the given dish, or null.
  /// [dishNameHindi] is accepted for future use; currently unused in
  /// queries since Openverse tags are English-dominant.
  static Future<String?> findImageUrl(
    String dishName, {
    String? dishNameHindi,
  }) async {
    final name = dishName.trim();
    if (name.isEmpty) return null;

    // 1) Openverse
    try {
      final q = Uri.encodeQueryComponent('$name indian food');
      final uri = Uri.parse(
        '$_openverseBase?q=$q&page_size=1&license=cc0,pdm,by,by-sa',
      );
      final r = await http
          .get(uri, headers: {'User-Agent': 'JarvisApp/1.0 (personal use)'})
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final results = (body is Map ? body['results'] : null) as List?;
        if (results != null && results.isNotEmpty) {
          final url = results[0]['url']?.toString();
          if (url != null && url.isNotEmpty) return url;
        }
      }
    } catch (_) {
      // fall through to Wikipedia
    }

    // 2) Wikipedia — try the dish name as-is (capitalised).
    try {
      final title = Uri.encodeComponent(name.replaceAll(' ', '_'));
      final uri = Uri.parse('$_wikiBase$title');
      final r = await http
          .get(uri, headers: {'User-Agent': 'JarvisApp/1.0 (personal use)'})
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map && body['thumbnail'] is Map) {
          final source = (body['thumbnail'] as Map)['source']?.toString();
          if (source != null && source.isNotEmpty) return source;
        }
      }
    } catch (_) {
      // fall through
    }

    return null;
  }
}
