import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SosAlarmManager {
  SosAlarmManager._();

  static final SosAlarmManager instance = SosAlarmManager._();
  static const MethodChannel _alarmChannel = MethodChannel(
    'com.example.riskradar/alarm',
  );

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  Future<void> startAlarm() async {
    if (_isPlaying) {
      return;
    }

    try {
      await _alarmChannel.invokeMethod('setAlarmVolume');
    } catch (e) {
      debugPrint('SOS alarm volume channel error: $e');
    }

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/sos_alarm.wav'));
      _isPlaying = true;
    } catch (e) {
      debugPrint('SOS alarm start error: $e');
    }
  }

  Future<void> stopAlarm() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('SOS alarm stop error: $e');
    } finally {
      _isPlaying = false;
    }
  }
}
