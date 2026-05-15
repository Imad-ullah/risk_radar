// lib/shared/hazards/voice_note_recorder.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

// Callback definitions
typedef RecordingStateChanged = void Function(bool isRecording);
typedef PlaybackStateChanged = void Function(bool isPlaying);

class VoiceNote {
  final String id;
  final File file;
  final Duration duration;
  final List<double> waveformData;
  final DateTime createdAt;

  VoiceNote({
    required this.id,
    required this.file,
    required this.duration,
    required this.waveformData,
    required this.createdAt,
  });
}

class VoiceNoteRecorder extends StatefulWidget {
  final RecordingStateChanged onRecordingStateChanged;
  final PlaybackStateChanged? onPlaybackStateChanged;

  const VoiceNoteRecorder({
    super.key,
    required this.onRecordingStateChanged,
    this.onPlaybackStateChanged,
  });

  @override
  State<VoiceNoteRecorder> createState() => VoiceNoteRecorderState();
}

class VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _isRecorderReady = false;
  bool _isRecording = false;
  bool _playerReady = false;

  StreamSubscription? _recorderSubscription;
  StreamSubscription? _playerSubscription;

  final List<VoiceNote> _voiceNotes = [];
  String? _currentPlayingId;
  Duration _currentPlayPosition = Duration.zero;

  final List<double> _currentWaveformData = [];
  Duration _currentRecordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
  }

  Future<void> _initRecorder() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;
    await Permission.storage.request();
    await _recorder.openRecorder();
    _isRecorderReady = true;

    _recorderSubscription = _recorder.onProgress?.listen((event) {
      if (event.decibels != null && mounted && _isRecording) {
        double amplitude = (event.decibels!.abs() / 80).clamp(0.0, 1.0);
        setState(() {
          _currentWaveformData.add(amplitude);
          _currentRecordingDuration = event.duration;
          if (_currentWaveformData.length > 100) {
            _currentWaveformData.removeAt(0);
          }
        });
      }
    });
    _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    setState(() => _playerReady = true);
    _playerSubscription = _player.onProgress?.listen((event) {
      if (mounted && _currentPlayingId != null) {
        setState(() => _currentPlayPosition = event.position);
      }
    });
    _player.setSubscriptionDuration(const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _playerSubscription?.cancel();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> startRecording() async {
    if (!_isRecorderReady || _currentPlayingId != null) return;

    final dir = await getTemporaryDirectory();
    final path = "${dir.path}/${const Uuid().v4()}.m4a";
    setState(() {
      _currentWaveformData.clear();
      _currentRecordingDuration = Duration.zero;
    });
    await _recorder.startRecorder(toFile: path, codec: Codec.aacMP4);
    setState(() => _isRecording = true);
    widget.onRecordingStateChanged(true);
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    final recordedPath = await _recorder.stopRecorder();
    if (recordedPath != null && _currentRecordingDuration > const Duration(milliseconds: 500)) {
      final voiceNote = VoiceNote(
        id: const Uuid().v4(),
        file: File(recordedPath),
        duration: _currentRecordingDuration,
        waveformData: List.from(_currentWaveformData),
        createdAt: DateTime.now(),
      );
      setState(() {
        _voiceNotes.add(voiceNote);
      });
    }
    setState(() {
      _isRecording = false;
      _currentWaveformData.clear();
      _currentRecordingDuration = Duration.zero;
    });
    widget.onRecordingStateChanged(false);
  }

  Future<void> _playVoiceNote(String voiceNoteId) async {
    if (!_playerReady || _isRecording) return;

    final voiceNote = _voiceNotes.firstWhere((note) => note.id == voiceNoteId);
    if (_currentPlayingId != null && _currentPlayingId != voiceNoteId) {
      await _player.stopPlayer();
    }
    if (_currentPlayingId == voiceNoteId) {
      await _player.stopPlayer();
      setState(() {
        _currentPlayingId = null;
        _currentPlayPosition = Duration.zero;
      });
      widget.onPlaybackStateChanged?.call(false);
    } else {
      await _player.startPlayer(
        fromURI: voiceNote.file.path,
        codec: Codec.aacMP4,
        whenFinished: () {
          if (mounted) {
            setState(() {
              _currentPlayingId = null;
              _currentPlayPosition = Duration.zero;
            });
            widget.onPlaybackStateChanged?.call(false);
          }
        },
      );
      setState(() {
        _currentPlayingId = voiceNoteId;
        _currentPlayPosition = Duration.zero;
      });
      widget.onPlaybackStateChanged?.call(true);
    }
  }

  Future<void> _seekInVoiceNote(String voiceNoteId, double positionFraction) async {
    if (!_playerReady || _currentPlayingId != voiceNoteId) return;

    final voiceNote = _voiceNotes.firstWhere((note) => note.id == voiceNoteId);
    final seekPosition = Duration(
      milliseconds: (voiceNote.duration.inMilliseconds * positionFraction).round(),
    );

    await _player.seekToPlayer(seekPosition);

    setState(() {
      _currentPlayPosition = seekPosition;
    });
  }

  void _deleteVoiceNote(String voiceNoteId) {
    setState(() {
      if (_currentPlayingId == voiceNoteId) {
        _player.stopPlayer();
        _currentPlayingId = null;
        _currentPlayPosition = Duration.zero;
        widget.onPlaybackStateChanged?.call(false);
      }
      _voiceNotes.removeWhere((note) => note.id == voiceNoteId);
    });
  }

  List<File> getAllRecordedFiles() {
    return _voiceNotes.map((note) => note.file).toList();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRecording && _voiceNotes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_voiceNotes.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _voiceNotes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildVoiceNoteItem(_voiceNotes[index]);
            },
          ),

        if (_voiceNotes.isNotEmpty && _isRecording)
          const SizedBox(height: 16),

        if (_isRecording) _buildCurrentRecording(),
      ],
    );
  }

  /// ## MODIFIED WIDGET: Glassy black (light theme) and white (dark theme)
  Widget _buildVoiceNoteItem(VoiceNote voiceNote) {
    final isPlaying = _currentPlayingId == voiceNote.id;
    final progress = isPlaying && voiceNote.duration.inMilliseconds > 0
        ? (_currentPlayPosition.inMilliseconds / voiceNote.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final isLightTheme = Theme.of(context).brightness == Brightness.light;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.0),
            // **CHANGE**: Glassy black for light theme, glassy white for dark theme
            color: isLightTheme ? Colors.black.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: isLightTheme ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _isRecording ? null : () => _playVoiceNote(voiceNote.id),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.grey.withValues(alpha: 0.5) : (isPlaying ? Colors.orange : Colors.green),
                  ),
                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      child: Builder(
                          builder: (context) {
                            return CustomPaint(
                              painter: VoiceNoteWaveformPainter(
                                waveformData: voiceNote.waveformData,
                                progress: progress,
                                isLightTheme: isLightTheme,
                              ),
                              size: const Size(double.infinity, 30),
                            );
                          }
                      ),
                      onTapDown: (details) {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final positionFraction = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
                        _seekInVoiceNote(voiceNote.id, positionFraction);
                      },
                      onHorizontalDragUpdate: (details) {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final positionFraction = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
                        _seekInVoiceNote(voiceNote.id, positionFraction);
                      },
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(isPlaying ? _currentPlayPosition : Duration.zero),
                          style: TextStyle(
                              fontSize: 10,
                              // **CHANGE**: Light text color for both themes for contrast
                              color: isLightTheme ? Colors.white.withValues(alpha: 0.8) : Colors.white70,
                              fontWeight: FontWeight.w500
                          ),
                        ),
                        Text(
                          _formatDuration(voiceNote.duration),
                          style: TextStyle(fontSize: 10, color: isLightTheme ? Colors.white.withValues(alpha: 0.8) : Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _deleteVoiceNote(voiceNote.id),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLightTheme ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                  ),
                  child: Icon(Icons.delete_outline, color: isLightTheme ? Colors.white : Colors.red.shade300, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentRecording() {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isLightTheme ? Colors.red.shade50 : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: stopRecording,
            child: Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
              child: const Icon(Icons.stop, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 30,
                  child: CustomPaint(
                    painter: VoiceNoteWaveformPainter(
                      waveformData: _currentWaveformData,
                      progress: 0.0,
                      isRecording: true,
                      isLightTheme: isLightTheme,
                    ),
                    size: const Size(double.infinity, 30),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(_currentRecordingDuration),
                      style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceNoteWaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final bool isRecording;
  final bool isLightTheme;

  VoiceNoteWaveformPainter({
    required this.waveformData,
    required this.progress,
    this.isRecording = false,
    this.isLightTheme = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) {
      final paint = Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 2;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
      return;
    }

    final paint = Paint()..strokeWidth = 2.5;
    final barWidth = size.width / max(waveformData.length, 1);
    final progressPosition = size.width * progress.clamp(0.0, 1.0);

    // **CHANGE**: Consistent light colors for contrast on glassy backgrounds
    const playedColor = Colors.white;
    final unplayedColor = Colors.white.withValues(alpha: 0.4);
    const handleColor = Colors.white;

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = (waveformData[i] * size.height * 0.8).clamp(2.0, size.height * 0.8);
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;
      paint.color = isRecording ? Colors.redAccent : (x <= progressPosition ? playedColor : unplayedColor);
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }

    if (!isRecording && progress > 0) {
      final progressHandlePaint = Paint()..color = handleColor;
      canvas.drawCircle(Offset(progressPosition, size.height / 2), 4, progressHandlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! VoiceNoteWaveformPainter ||
        oldDelegate.waveformData.length != waveformData.length ||
        oldDelegate.progress != progress ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.isLightTheme != isLightTheme;
  }
}
