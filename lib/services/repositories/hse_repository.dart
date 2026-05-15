import 'sqlite_cache_store.dart';

class HseRepository {
  HseRepository._();

  static final HseRepository instance = HseRepository._();

  static const _teamMembersKey = 'rr_hse_team_members';

  final SqliteCacheStore _cacheStore = SqliteCacheStore.instance;

  Future<void> saveHseTeamMembers(List<dynamic> rows) =>
      _cacheStore.writeJson(_teamMembersKey, rows);

  List<Map<String, dynamic>>? getHseTeamMembers() =>
      _cacheStore.readMapList(_teamMembersKey);
}
