import 'package:shared_preferences/shared_preferences.dart';

/// 应用状态持久化：记住上次选择
class AppStateService {
  static const _k = {
    'leftTab': 'left_tab',
    'subcategory': 'subcategory',
    'playlistName': 'playlist_name',
    'hymnNumber': 'hymn_number',
    'audioVersion': 'audio_version',
    'displayMode': 'display_mode',
  };

  Future<void> saveAll({
    required String leftTab,
    required String subcategory,
    required String playlistName,
    required String hymnNumber,
    required String audioVersion,
    required String displayMode,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k['leftTab']!, leftTab);
    await p.setString(_k['subcategory']!, subcategory);
    await p.setString(_k['playlistName']!, playlistName);
    await p.setString(_k['hymnNumber']!, hymnNumber);
    await p.setString(_k['audioVersion']!, audioVersion);
    await p.setString(_k['displayMode']!, displayMode);
  }

  Future<AppState> load() async {
    final p = await SharedPreferences.getInstance();
    return AppState(
      leftTab: p.getString(_k['leftTab']!) ?? '',
      subcategory: p.getString(_k['subcategory']!) ?? '',
      playlistName: p.getString(_k['playlistName']!) ?? '',
      hymnNumber: p.getString(_k['hymnNumber']!) ?? '',
      audioVersion: p.getString(_k['audioVersion']!) ?? '',
      displayMode: p.getString(_k['displayMode']!) ?? '',
    );
  }
}

class AppState {
  final String leftTab;
  final String subcategory;
  final String playlistName;
  final String hymnNumber;
  final String audioVersion;
  final String displayMode;

  const AppState({
    required this.leftTab,
    required this.subcategory,
    required this.playlistName,
    required this.hymnNumber,
    required this.audioVersion,
    required this.displayMode,
  });
}
