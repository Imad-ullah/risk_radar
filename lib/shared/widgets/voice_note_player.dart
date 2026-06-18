import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceNotePlayer extends StatefulWidget {
  final String url;

  const VoiceNotePlayer({super.key, required this.url});

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(UrlSource(widget.url));
      setState(() => _isPlaying = true);

      _audioPlayer.onPlayerComplete.listen((event) {
        setState(() => _isPlaying = false);
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _togglePlay,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: R.blockH * 3,
          vertical: R.blockV * 0.75,
        ),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.purple.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying ? Icons.stop : Icons.play_arrow,
              size: 16,
              color: Colors.purple,
            ),
            SizedBox(width: R.blockH * 1.6),
            Text(
              "Voice Note",
              style: TextStyle(
                fontSize: R.blockH * 3.25,
                fontWeight: FontWeight.w600,
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
