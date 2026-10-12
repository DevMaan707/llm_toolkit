import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Whisper log-mel front end (matches `whisper.audio.log_mel_spectrogram`):
/// 16 kHz audio padded/trimmed to 30 s, 400-point Hann STFT with hop 160 and
/// reflect padding, Slaney mel filters, log10, clamp to max-8, scale (x+4)/4.
class MelSpectrogram {
  static const sampleRate = 16000;
  static const nFft = 400;
  static const hop = 160;
  static const nMels = 80;
  static const nFrames = 3000;
  static const nSamples = nFrames * hop;
  static const _bins = nFft ~/ 2 + 1;
  static const _logFloor = 1e-10;

  final FFT _fft = FFT(nFft);
  final Float64List _window = Float64List(nFft);
  late final List<Float32List> _filters = _slaneyFilters();

  MelSpectrogram() {
    for (var i = 0; i < nFft; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / nFft);
    }
  }

  /// Returns a `[nMels][nFrames]` matrix flattened mel-major (index
  /// `mel * nFrames + frame`). Audio longer than 30 s is truncated.
  Float32List compute(Float32List audio) {
    final n = math.min(audio.length, nSamples);
    // Zero-padded to 30 s with nFft/2 reflect padding on both sides.
    final padded = Float64List(nSamples + nFft);
    const half = nFft ~/ 2;
    for (var i = 0; i < n; i++) {
      padded[half + i] = audio[i];
    }
    for (var i = 1; i <= half; i++) {
      padded[half - i] = i < n ? audio[i].toDouble() : 0.0;
    }

    // Frames whose window lies entirely in the zero padding have zero energy,
    // so they all share the same log value and need no FFT.
    final activeFrames = math.min(nFrames, ((n + half) / hop).ceil());
    final out = Float32List(nMels * nFrames);
    final frame = Float64List(nFft);
    final logFloor = math.log(_logFloor) / math.ln10;
    var maxLog = activeFrames < nFrames ? logFloor : -double.maxFinite;

    for (var t = 0; t < activeFrames; t++) {
      for (var i = 0; i < nFft; i++) {
        frame[i] = padded[t * hop + i] * _window[i];
      }
      final power = _fft.realFft(frame).squareMagnitudes();
      for (var m = 0; m < nMels; m++) {
        final f = _filters[m];
        var acc = 0.0;
        for (var k = 0; k < _bins; k++) {
          acc += f[k] * power[k];
        }
        final v = math.log(math.max(acc, _logFloor)) / math.ln10;
        out[m * nFrames + t] = v;
        if (v > maxLog) maxLog = v;
      }
    }
    for (var m = 0; m < nMels; m++) {
      out.fillRange(m * nFrames + activeFrames, (m + 1) * nFrames, logFloor);
    }

    final floor = maxLog - 8;
    for (var i = 0; i < out.length; i++) {
      out[i] = (math.max(out[i], floor) + 4) / 4;
    }
    return out;
  }

  static double _hzToMel(double hz) =>
      hz < 1000
          ? hz * 3 / 200
          : 15 + math.log(hz / 1000) / (math.log(6.4) / 27);

  static double _melToHz(double mel) =>
      mel < 15
          ? mel * 200 / 3
          : 1000 * math.exp((math.log(6.4) / 27) * (mel - 15));

  static List<Float32List> _slaneyFilters() {
    final maxMel = _hzToMel(sampleRate / 2);
    final edges = [
      for (var i = 0; i < nMels + 2; i++) _melToHz(maxMel * i / (nMels + 1)),
    ];
    final freqs = [for (var k = 0; k < _bins; k++) k * sampleRate / nFft];
    return [
      for (var m = 0; m < nMels; m++)
        Float32List.fromList([
          for (final f in freqs)
            math.max(
                  0.0,
                  math.min(
                    (f - edges[m]) / (edges[m + 1] - edges[m]),
                    (edges[m + 2] - f) / (edges[m + 2] - edges[m + 1]),
                  ),
                ) *
                2 /
                (edges[m + 2] - edges[m]),
        ]),
    ];
  }
}

/// Runs [MelSpectrogram.compute] on a worker isolate.
Future<Float32List> computeMelSpectrogram(Float32List audio) =>
    Isolate.run(() => MelSpectrogram().compute(audio));
