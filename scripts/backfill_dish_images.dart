// One-shot utility: fill in `image_url` for every seed dish in the
// catalog by querying Openverse + Wikipedia via DishImageService.
//
// Usage:
//   dart run scripts/backfill_dish_images.dart
//
// Output:
//   scripts/_seed_image_overrides.json   →   { "seed_id": "https://..." }
//
// After the run, manually merge the overrides into
// `lib/data/indian_dish_seed.dart` by adding
// `imageUrl: '...'` to each Dish() constructor (or keep the JSON and
// wire a loader later if that scales better).
//
// Rate-limit notes: Openverse gives ~100 req/hr anonymous. The loop
// sleeps 1s between calls → ~3600 req/hr ceiling, but Wikipedia is
// the backup so actual Openverse calls are less. If it 429s, sleep
// longer and re-run — partial progress is saved every 10 dishes.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _openverseBase = 'https://api.openverse.org/v1/images/';
const _wikiBase = 'https://en.wikipedia.org/api/rest_v1/page/summary/';
const _timeout = Duration(seconds: 8);

Future<String?> findImageUrl(String dishName) async {
  final name = dishName.trim();
  if (name.isEmpty) return null;

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
    } else if (r.statusCode == 429) {
      stderr.writeln('  ! Openverse rate-limited, backing off 60s');
      await Future.delayed(const Duration(seconds: 60));
    }
  } catch (e) {
    stderr.writeln('  ! Openverse error: $e');
  }

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
  } catch (e) {
    stderr.writeln('  ! Wikipedia error: $e');
  }

  return null;
}

/// Parse seed file to extract (id, name) pairs. Stays lightweight —
/// regex, not full Dart analysis. Every seed Dish() has `id: 'seed_...'`
/// and `name: '...'` on adjacent lines.
Future<List<MapEntry<String, String>>> loadSeedDishes(String path) async {
  final content = await File(path).readAsString();
  final entries = <MapEntry<String, String>>[];
  final dishRegex = RegExp(
    r"id:\s*'(seed_[^']+)'\s*,\s*\n\s*name:\s*'([^']+)'",
    multiLine: true,
  );
  for (final m in dishRegex.allMatches(content)) {
    entries.add(MapEntry(m.group(1)!, m.group(2)!));
  }
  return entries;
}

Future<void> main(List<String> args) async {
  const seedPath = 'lib/data/indian_dish_seed.dart';
  const outPath = 'scripts/_seed_image_overrides.json';

  final dishes = await loadSeedDishes(seedPath);
  stdout.writeln('Found ${dishes.length} seed dishes');

  final overrides = <String, String>{};
  final existing = File(outPath);
  if (existing.existsSync()) {
    final prev = jsonDecode(existing.readAsStringSync()) as Map<String, dynamic>;
    for (final e in prev.entries) {
      overrides[e.key] = e.value.toString();
    }
    stdout.writeln('Resuming from ${overrides.length} previous hits');
  }

  var i = 0;
  for (final entry in dishes) {
    i++;
    if (overrides.containsKey(entry.key)) continue;
    stdout.writeln('[$i/${dishes.length}] ${entry.value} (${entry.key})');
    final url = await findImageUrl(entry.value);
    if (url != null) {
      overrides[entry.key] = url;
      stdout.writeln('  ✓ $url');
    } else {
      stdout.writeln('  · no match');
    }
    await Future.delayed(const Duration(milliseconds: 1100));
    if (i % 10 == 0) {
      await File(outPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(overrides),
      );
      stdout.writeln('  (saved progress · ${overrides.length} hits)');
    }
  }

  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(overrides),
  );
  stdout.writeln('\nDone — wrote $outPath with ${overrides.length} URLs');
  stdout.writeln(
    'Next step: manually merge imageUrl into indian_dish_seed.dart '
    'or add a loader that reads this JSON at seed time.',
  );
}
