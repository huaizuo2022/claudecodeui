import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/cache_database.dart';
import 'core/storage/prefs_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final cacheDb = CacheDatabase();
  try {
    await cacheDb.init();
  } catch (e) {
    debugPrint('Failed to initialize CacheDatabase: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
        cacheDatabaseProvider.overrideWithValue(cacheDb),
      ],
      child: const CloudCliApp(),
    ),
  );
}
