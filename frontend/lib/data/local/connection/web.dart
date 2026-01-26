import 'package:drift/drift.dart';
import 'package:drift/web.dart';

LazyDatabase connect() {
  return LazyDatabase(() async {
    print('Opening Web Database via IndexedDB...');
    final db = WebDatabase.withStorage(DriftWebStorage.indexedDb('tour_cost_db'));
    print('Web Database initialized.');
    return db;
  });
}
