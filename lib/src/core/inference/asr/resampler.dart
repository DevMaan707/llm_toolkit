import 'dart:typed_data';

/// Resamples mono [input] from [fromRate] to [toRate].
///
/// Upsampling uses linear interpolation. Downsampling averages the source
/// samples covered by each output sample (box filter), which suppresses most of
/// the aliasing that plain interpolation would introduce.
Float32List resample(Float32List input, int fromRate, int toRate) {
  if (fromRate <= 0 || toRate <= 0) {
    throw ArgumentError('Sample rates must be positive');
  }
  if (fromRate == toRate || input.isEmpty) return input;

  final outLength = (input.length * toRate / fromRate).round();
  final out = Float32List(outLength);
  final step = fromRate / toRate;

  if (step <= 1) {
    for (var i = 0; i < outLength; i++) {
      final pos = i * step;
      final i0 = pos.floor();
      final i1 = i0 + 1 < input.length ? i0 + 1 : input.length - 1;
      final frac = pos - i0;
      out[i] = input[i0] + (input[i1] - input[i0]) * frac;
    }
    return out;
  }

  // prefix[k] = sum of input[0..k-1]; interpolating it linearly gives the exact
  // integral of the piecewise-constant signal between fractional positions.
  final prefix = Float64List(input.length + 1);
  for (var i = 0; i < input.length; i++) {
    prefix[i + 1] = prefix[i] + input[i];
  }
  double at(double pos) {
    final i0 = pos.floor().clamp(0, input.length);
    if (i0 >= input.length) return prefix[input.length];
    return prefix[i0] + input[i0] * (pos - i0);
  }

  for (var i = 0; i < outLength; i++) {
    final start = i * step;
    final end = (start + step).clamp(0, input.length).toDouble();
    out[i] =
        end > start
            ? (at(end) - at(start)) / (end - start)
            : input[input.length - 1];
  }
  return out;
}
