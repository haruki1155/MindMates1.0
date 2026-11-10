
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// MindMate Breathing Sound Service.
///
/// Creates soft, synthetic inhale and exhale sounds.
///
/// No external audio file is required.
/// No microphone or internet connection is needed.
///
/// Designed for the mobile breathing exercise feature.
class BreathingSoundService {
  final AudioPlayer _player = AudioPlayer();

  int _requestId = 0;
  bool _disposed = false;

  /// Plays an inhale or exhale sound.
  ///
  /// The label should contain:
  /// - "Inhale" or "Breathe in"
  /// - "Exhale" or "Breathe out"
  ///
  /// Hold phases are silent.
  Future<void> playPhase({
    required String label,
    required int seconds,
    required double volume,
  }) async {
    if (_disposed) return;

    final requestId = ++_requestId;

    try {
      await _player.stop();

      if (_disposed || requestId != _requestId) {
        return;
      }

      final name = label.toLowerCase();

      final isInhale =
          name.contains('inhale') ||
          name.contains('breathe in');

      final isExhale =
          name.contains('exhale') ||
          name.contains('breathe out');

      // No sound during hold phases.
      if ((!isInhale && !isExhale) || seconds <= 0) {
        return;
      }

      // Prevent unexpectedly long sound generation.
      final duration = seconds.clamp(1, 12).toInt();

      final directory = await getTemporaryDirectory();

      if (_disposed || requestId != _requestId) {
        return;
      }

      final soundType =
          isInhale ? 'inhale' : 'exhale';

      final file = File(
        '${directory.path}/'
        'mindmate_${soundType}_${duration}s.wav',
      );

      // Generate the sound only when not cached.
      if (!await file.exists()) {
        final bytes = _createBreathWav(
          duration,
          inhale: isInhale,
        );

        await file.writeAsBytes(
          bytes,
          flush: true,
        );
      }

      if (_disposed || requestId != _requestId) {
        return;
      }

      await _player.setFilePath(file.path);

      if (_disposed || requestId != _requestId) {
        return;
      }

      await _player.setVolume(
        volume.clamp(0.0, 1.0).toDouble(),
      );

      // Don't block the breathing timer while
      // waiting for audio playback to finish.
      unawaited(_playSafely());
    } catch (error) {
      debugPrint(
        'MindMate breathing audio error: $error',
      );
    }
  }

  /// Handles playback failures safely.
  Future<void> _playSafely() async {
    try {
      if (_disposed) return;

      await _player.play();
    } catch (error) {
      debugPrint(
        'MindMate breathing playback error: $error',
      );
    }
  }

  /// Changes the breathing sound volume.
  Future<void> setVolume(double volume) async {
    if (_disposed) return;

    try {
      await _player.setVolume(
        volume.clamp(0.0, 1.0).toDouble(),
      );
    } catch (error) {
      debugPrint(
        'Breathing volume error: $error',
      );
    }
  }

  /// Stops the currently playing sound.
  Future<void> stop() async {
    _requestId++;

    if (_disposed) return;

    try {
      await _player.stop();
    } catch (error) {
      debugPrint(
        'Breathing stop error: $error',
      );
    }
  }

  /// Releases audio resources.
  Future<void> dispose() async {
    if (_disposed) return;

    _requestId++;
    _disposed = true;

    await _player.dispose();
  }

  /// Creates a mono 16-bit PCM WAV file.
  ///
  /// The sound uses filtered noise with a gradual
  /// rise and fall in volume to simulate soft airflow.
  Uint8List _createBreathWav(
    int seconds, {
    required bool inhale,
  }) {
    const sampleRate = 11025;
    const bytesPerSample = 2;

    final sampleCount = sampleRate * seconds;
    final dataLength =
        sampleCount * bytesPerSample;

    final output = Uint8List(
      44 + dataLength,
    );

    final view = ByteData.sublistView(output);

    void writeText(
      int offset,
      String value,
    ) {
      for (var i = 0; i < value.length; i++) {
        output[offset + i] = value.codeUnitAt(i);
      }
    }

    // WAV file header.
    writeText(0, 'RIFF');

    view.setUint32(
      4,
      36 + dataLength,
      Endian.little,
    );

    writeText(8, 'WAVE');
    writeText(12, 'fmt ');

    view.setUint32(
      16,
      16,
      Endian.little,
    );

    view.setUint16(
      20,
      1,
      Endian.little,
    );

    view.setUint16(
      22,
      1,
      Endian.little,
    );

    view.setUint32(
      24,
      sampleRate,
      Endian.little,
    );

    view.setUint32(
      28,
      sampleRate * bytesPerSample,
      Endian.little,
    );

    view.setUint16(
      32,
      bytesPerSample,
      Endian.little,
    );

    view.setUint16(
      34,
      16,
      Endian.little,
    );

    writeText(36, 'data');

    view.setUint32(
      40,
      dataLength,
      Endian.little,
    );

    // Deterministic random noise creates
    // consistent breathing sound samples.
    final random = math.Random(
      inhale ? 421 : 842,
    );

    double filteredNoise = 0;

    for (var i = 0; i < sampleCount; i++) {
      final time = i / sampleRate;
      final progress = i / sampleCount;

      // Smooth fade-in.
      final fadeIn = math.min(
        1.0,
        time / 0.55,
      );

      // Smooth fade-out.
      final fadeOut = math.min(
        1.0,
        (seconds - time) / 0.70,
      );

      // Natural rise-and-fall envelope.
      final swell = math.sin(
        math.pi * progress,
      ).abs();

      final envelope =
          math.pow(swell, 0.65).toDouble() *
          fadeIn *
          fadeOut;

      // Generate soft filtered noise.
      final noise =
          random.nextDouble() * 2 - 1;

      filteredNoise =
          filteredNoise * 0.78 +
          noise * 0.22;

      final airyNoise =
          filteredNoise * 0.8 +
          noise * 0.2;

      // Exhale is slightly louder.
      final intensity =
          inhale ? 0.30 : 0.38;

      final rawSample =
          airyNoise *
          envelope *
          intensity *
          32767;

      final sample = rawSample
          .round()
          .clamp(-32768, 32767)
          .toInt();

      view.setInt16(
        44 + i * bytesPerSample,
        sample,
        Endian.little,
      );
    }

    return output;
  }
}
