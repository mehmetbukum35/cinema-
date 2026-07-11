import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/sync_service.dart';

void initAppFlowTestBinding() {
  // Under FLUTTER_TEST, DatabaseHelper uses in-memory mock lists (no SQLite FFI).
}

Future<void> setUpAppFlowTestCase() async {
  DatabaseHelper.databaseInstance = null;
  SharedPreferences.setMockInitialValues({
    'selected_language': 'en',
    'swipe_guide_shown': true,
  });
  PrefsService.activeLanguageCode = 'en';
  await DatabaseHelper().clearAllData();
}

Future<void> tearDownAppFlowTestCase() async {
  await DatabaseHelper().clearAllData();
  DatabaseHelper.databaseInstance = null;
}

/// VM app-flow tests call mocked push/pull without full SQLite sync pipeline.
class AppFlowSyncService extends SyncService {
  final ApiService _api;

  AppFlowSyncService(this._api) : super(_api, null);

  @override
  Future<void> sync() async {
    await _api.push({
      'ratings': [],
      'watchlist': [],
      'favorites': [],
      'watched_seasons': [],
      'search_history': [],
    });
    await _api.pull(0);
  }
}
