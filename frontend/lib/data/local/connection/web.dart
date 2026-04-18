import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift/web.dart';

LazyDatabase connect() {
  return LazyDatabase(() async {
    debugPrint('Opening Web Database via IndexedDB...');
    final db =
        WebDatabase.withStorage(DriftWebStorage.indexedDb('tour_cost_db'));
    debugPrint('Web Database initialized.');
    return db;
  });
}
