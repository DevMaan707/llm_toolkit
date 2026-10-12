import 'dart:typed_data';

import 'package:record/record.dart';

/// Microphone access as a stream of mono PCM16 little-endian chunks. Abstracted
/// so the recording service can be exercised without a device.
abstract interface class PcmRecorder {
  /// Checks (and, if needed, requests) microphone permission.
  Future<bool> hasPermission();

  /// Starts capturing at [sampleRate]; the stream ends after [stop].
  Future<Stream<Uint8List>> start(int sampleRate);

  Future<void> stop();

  Future<void> dispose();
}

/// [PcmRecorder] backed by the `record` package.
class RecordPcmRecorder implements PcmRecorder {
  final AudioRecorder _recorder;

  RecordPcmRecorder([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start(int sampleRate) => _recorder.startStream(
    RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
