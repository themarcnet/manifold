// Pitch Detection Algorithms Implementation
// For Web Audio API real-time processing

export interface PitchDetectionResult {
  pitch: number | null;
  clarity: number;
  algorithm: string;
}

// =====================
// 1. ZERO-CROSSING RATE
// =====================
// Simplest method - counts zero crossings to estimate frequency
// Fast but inaccurate for complex signals, noise-sensitive

export function detectPitchZeroCrossing(
  buffer: Float32Array,
  sampleRate: number
): PitchDetectionResult {
  let crossings = 0;
  let prevSample = buffer[0];

  for (let i = 1; i < buffer.length; i++) {
    if ((prevSample >= 0 && buffer[i] < 0) || (prevSample < 0 && buffer[i] >= 0)) {
      crossings++;
    }
    prevSample = buffer[i];
  }

  // Each period has 2 zero crossings
  const frequency = (crossings * sampleRate) / (2 * buffer.length);

  // Calculate clarity based on signal strength
  let sum = 0;
  for (let i = 0; i < buffer.length; i++) {
    sum += Math.abs(buffer[i]);
  }
  const avgAmplitude = sum / buffer.length;
  const clarity = Math.min(1, avgAmplitude * 10);

  if (frequency < 20 || frequency > 5000 || isNaN(frequency)) {
    return { pitch: null, clarity: 0, algorithm: 'Zero-Crossing' };
  }

  return { pitch: frequency, clarity, algorithm: 'Zero-Crossing' };
}

// =====================
// 2. AUTOCORRELATION
// =====================
// Classic time-domain method - correlates signal with itself
// Robust for periodic signals, widely used

export function detectPitchAutocorrelation(
  buffer: Float32Array,
  sampleRate: number,
  minFreq: number = 50,
  maxFreq: number = 2000
): PitchDetectionResult {
  const minLag = Math.floor(sampleRate / maxFreq);
  const maxLag = Math.floor(sampleRate / minFreq);

  if (maxLag > buffer.length) {
    return { pitch: null, clarity: 0, algorithm: 'Autocorrelation' };
  }

  // Compute autocorrelation
  const correlations = new Float32Array(maxLag - minLag + 1);
  let maxCorrelation = -Infinity;
  let bestLag = minLag;

  for (let lag = minLag; lag <= maxLag; lag++) {
    let sum = 0;
    for (let i = 0; i < buffer.length - lag; i++) {
      sum += buffer[i] * buffer[i + lag];
    }
    correlations[lag - minLag] = sum / (buffer.length - lag);

    if (correlations[lag - minLag] > maxCorrelation) {
      maxCorrelation = correlations[lag - minLag];
      bestLag = lag;
    }
  }

  // Parabolic interpolation for sub-sample accuracy
  if (bestLag > minLag && bestLag < maxLag) {
    const y1 = correlations[bestLag - minLag - 1];
    const y2 = correlations[bestLag - minLag];
    const y3 = correlations[bestLag - minLag + 1];

    const denom = y1 - 2 * y2 + y3;
    if (Math.abs(denom) > 1e-10) {
      const refinedLag = bestLag + (y1 - y3) / (2 * denom);
      const frequency = sampleRate / refinedLag;
      const clarity = Math.max(0, Math.min(1, maxCorrelation * 2));

      if (frequency > minFreq && frequency < maxFreq) {
        return { pitch: frequency, clarity, algorithm: 'Autocorrelation' };
      }
    }
  }

  const frequency = sampleRate / bestLag;
  const clarity = Math.max(0, Math.min(1, maxCorrelation * 2));

  if (frequency < minFreq || frequency > maxFreq || isNaN(frequency)) {
    return { pitch: null, clarity: 0, algorithm: 'Autocorrelation' };
  }

  return { pitch: frequency, clarity, algorithm: 'Autocorrelation' };
}

// =====================
// 3. YIN ALGORITHM
// =====================
// Improved autocorrelation with difference function
// Better at avoiding octave errors, more accurate than basic autocorrelation
// Paper: "YIN, a fundamental frequency estimator for speech and music"
// by Alain de Cheveigné and Hideki Kawahara

export function detectPitchYIN(
  buffer: Float32Array,
  sampleRate: number,
  threshold: number = 0.15,
  minFreq: number = 50,
  maxFreq: number = 2000
): PitchDetectionResult {
  const bufferSize = buffer.length;
  const minLag = Math.floor(sampleRate / maxFreq);
  const maxLag = Math.min(Math.floor(sampleRate / minFreq), bufferSize / 2);

  if (maxLag <= minLag) {
    return { pitch: null, clarity: 0, algorithm: 'YIN' };
  }

  // Step 1: Difference function
  const yinBuffer = new Float32Array(maxLag);
  yinBuffer[0] = 1;

  for (let lag = 1; lag < maxLag; lag++) {
    let sum = 0;
    for (let i = 0; i < maxLag; i++) {
      const delta = buffer[i] - buffer[i + lag];
      sum += delta * delta;
    }
    yinBuffer[lag] = sum;
  }

  // Step 2: Cumulative mean normalized difference
  let runningSum = 0;
  for (let lag = 1; lag < maxLag; lag++) {
    runningSum += yinBuffer[lag];
    yinBuffer[lag] = (yinBuffer[lag] * lag) / runningSum;
  }

  // Step 3: Absolute threshold
  let tau = 2;
  for (tau = minLag; tau < maxLag; tau++) {
    if (yinBuffer[tau] < threshold) {
      // Find local minimum
      while (tau + 1 < maxLag && yinBuffer[tau + 1] < yinBuffer[tau]) {
        tau++;
      }
      break;
    }
  }

  if (tau >= maxLag || yinBuffer[tau] >= threshold) {
    return { pitch: null, clarity: 0, algorithm: 'YIN' };
  }

  // Step 4: Parabolic interpolation
  let betterTau: number;
  if (tau > 0 && tau < maxLag - 1) {
    const s0 = yinBuffer[tau - 1];
    const s1 = yinBuffer[tau];
    const s2 = yinBuffer[tau + 1];

    const denom = s0 - 2 * s1 + s2;
    if (Math.abs(denom) > 1e-10) {
      betterTau = tau + (s0 - s2) / (2 * denom);
    } else {
      betterTau = tau;
    }
  } else {
    betterTau = tau;
  }

  const frequency = sampleRate / betterTau;
  const clarity = 1 - yinBuffer[tau];

  if (frequency < minFreq || frequency > maxFreq || isNaN(frequency)) {
    return { pitch: null, clarity: 0, algorithm: 'YIN' };
  }

  return { pitch: frequency, clarity, algorithm: 'YIN' };
}

// =====================
// 4. HARMONIC PRODUCT SPECTRUM (HPS)
// =====================
// FFT-based method - multiplies downsampled spectra
// Good for harmonic signals, robust to noise
// Works in frequency domain

export function detectPitchHPS(
  buffer: Float32Array,
  sampleRate: number,
  harmonics: number = 5,
  minFreq: number = 50,
  maxFreq: number = 2000
): PitchDetectionResult {
  const fftSize = buffer.length;
  const fftResult = fft(buffer);

  // Get magnitude spectrum
  const magnitudes = new Float32Array(fftSize / 2);
  for (let i = 0; i < fftSize / 2; i++) {
    magnitudes[i] = Math.sqrt(
      fftResult.real[i] * fftResult.real[i] + fftResult.imag[i] * fftResult.imag[i]
    );
  }

  // Harmonic Product Spectrum
  const hpsLength = Math.floor(magnitudes.length / harmonics);
  const hps = new Float32Array(hpsLength);

  for (let i = 0; i < hpsLength; i++) {
    hps[i] = magnitudes[i];
    for (let h = 2; h <= harmonics; h++) {
      if (i * h < magnitudes.length) {
        hps[i] *= magnitudes[i * h];
      }
    }
  }

  // Find peak
  const minBin = Math.floor((minFreq * fftSize) / sampleRate);
  const maxBin = Math.min(Math.floor((maxFreq * fftSize) / sampleRate), hpsLength);

  let maxVal = 0;
  let maxIdx = minBin;

  for (let i = minBin; i < maxBin; i++) {
    if (hps[i] > maxVal) {
      maxVal = hps[i];
      maxIdx = i;
    }
  }

  // Parabolic interpolation
  let refinedIdx = maxIdx;
  if (maxIdx > 0 && maxIdx < hpsLength - 1) {
    const alpha = hps[maxIdx - 1];
    const beta = hps[maxIdx];
    const gamma = hps[maxIdx + 1];

    const denom = alpha - 2 * beta + gamma;
    if (Math.abs(denom) > 1e-10) {
      refinedIdx = maxIdx + (alpha - gamma) / (2 * denom);
    }
  }

  const frequency = (refinedIdx * sampleRate) / fftSize;

  // Calculate clarity from HPS magnitude
  const avgMagnitude = magnitudes.reduce((a, b) => a + b, 0) / magnitudes.length;
  const clarity = Math.min(1, maxVal / (avgMagnitude * 100 + 1));

  if (frequency < minFreq || frequency > maxFreq || isNaN(frequency)) {
    return { pitch: null, clarity: 0, algorithm: 'HPS' };
  }

  return { pitch: frequency, clarity, algorithm: 'HPS' };
}

// Simple FFT implementation (Cooley-Tukey)
function fft(buffer: Float32Array): { real: Float32Array; imag: Float32Array } {
  const n = buffer.length;
  const real = new Float32Array(n);
  const imag = new Float32Array(n);

  // Copy input to real part
  for (let i = 0; i < n; i++) {
    real[i] = buffer[i];
    imag[i] = 0;
  }

  // Bit-reversal permutation
  const bits = Math.log2(n);
  for (let i = 0; i < n; i++) {
    const j = reverseBits(i, bits);
    if (j > i) {
      [real[i], real[j]] = [real[j], real[i]];
      [imag[i], imag[j]] = [imag[j], imag[i]];
    }
  }

  // Cooley-Tukey FFT
  for (let size = 2; size <= n; size *= 2) {
    const halfSize = size / 2;
    const step = (2 * Math.PI) / size;

    for (let i = 0; i < n; i += size) {
      for (let j = 0; j < halfSize; j++) {
        const angle = -j * step;
        const cos = Math.cos(angle);
        const sin = Math.sin(angle);

        const idx1 = i + j;
        const idx2 = i + j + halfSize;

        const tReal = real[idx2] * cos - imag[idx2] * sin;
        const tImag = real[idx2] * sin + imag[idx2] * cos;

        real[idx2] = real[idx1] - tReal;
        imag[idx2] = imag[idx1] - tImag;
        real[idx1] += tReal;
        imag[idx1] += tImag;
      }
    }
  }

  return { real, imag };
}

function reverseBits(n: number, bits: number): number {
  let reversed = 0;
  for (let i = 0; i < bits; i++) {
    reversed = (reversed << 1) | (n & 1);
    n >>= 1;
  }
  return reversed;
}

// =====================
// 5. NSDF (Normalized Square Difference Function)
// =====================
// Used in McLeod Pitch Method - combines autocorrelation benefits with normalization
// Good for real-time applications, robust amplitude handling

export function detectPitchNSDF(
  buffer: Float32Array,
  sampleRate: number,
  threshold: number = 0.6,
  minFreq: number = 50,
  maxFreq: number = 2000
): PitchDetectionResult {
  const bufferSize = buffer.length;
  const minLag = Math.floor(sampleRate / maxFreq);
  const maxLag = Math.min(Math.floor(sampleRate / minFreq), bufferSize / 2);

  if (maxLag <= minLag) {
    return { pitch: null, clarity: 0, algorithm: 'NSDF' };
  }

  // Compute NSDF
  const nsdf = new Float32Array(maxLag);

  for (let lag = 0; lag < maxLag; lag++) {
    let autocorr = 0;
    let energy = 0;

    for (let i = 0; i < bufferSize - lag; i++) {
      autocorr += buffer[i] * buffer[i + lag];
      energy += buffer[i] * buffer[i] + buffer[i + lag] * buffer[i + lag];
    }

    nsdf[lag] = energy > 0 ? (2 * autocorr) / energy : 0;
  }

  // Find peaks above threshold
  let maxVal = 0;
  let maxLagFound = 0;

  for (let lag = minLag; lag < maxLag; lag++) {
    // Check for local maximum
    if (nsdf[lag] > threshold && nsdf[lag] > nsdf[lag - 1] && nsdf[lag] > nsdf[lag + 1]) {
      if (nsdf[lag] > maxVal) {
        maxVal = nsdf[lag];
        maxLagFound = lag;
      }
    }
  }

  if (maxVal < threshold) {
    return { pitch: null, clarity: 0, algorithm: 'NSDF' };
  }

  // Parabolic interpolation
  let refinedLag = maxLagFound;
  if (maxLagFound > 0 && maxLagFound < maxLag - 1) {
    const y1 = nsdf[maxLagFound - 1];
    const y2 = nsdf[maxLagFound];
    const y3 = nsdf[maxLagFound + 1];

    const denom = y1 - 2 * y2 + y3;
    if (Math.abs(denom) > 1e-10) {
      refinedLag = maxLagFound + (y1 - y3) / (2 * denom);
    }
  }

  const frequency = sampleRate / refinedLag;
  const clarity = maxVal;

  if (frequency < minFreq || frequency > maxFreq || isNaN(frequency)) {
    return { pitch: null, clarity: 0, algorithm: 'NSDF' };
  }

  return { pitch: frequency, clarity, algorithm: 'NSDF' };
}

// =====================
// UTILITY FUNCTIONS
// =====================

export function frequencyToNote(frequency: number): string {
  const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const a4 = 440;
  const c0 = a4 * Math.pow(2, -4.75);

  if (frequency <= 0) return '--';

  const h = Math.round(12 * Math.log2(frequency / c0));
  const octave = Math.floor(h / 12);
  const noteIdx = h % 12;

  return `${noteNames[noteIdx]}${octave}`;
}

export function frequencyToCents(frequency: number): number {
  if (frequency <= 0) return 0;
  return 1200 * Math.log2(frequency / 440);
}

export function centsToFrequency(cents: number, reference: number = 440): number {
  return reference * Math.pow(2, cents / 1200);
}

// Apply a window function to reduce spectral leakage
export function applyHannWindow(buffer: Float32Array): Float32Array {
  const result = new Float32Array(buffer.length);
  for (let i = 0; i < buffer.length; i++) {
    const multiplier = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (buffer.length - 1)));
    result[i] = buffer[i] * multiplier;
  }
  return result;
}

// RMS (Root Mean Square) for signal level
export function calculateRMS(buffer: Float32Array): number {
  let sum = 0;
  for (let i = 0; i < buffer.length; i++) {
    sum += buffer[i] * buffer[i];
  }
  return Math.sqrt(sum / buffer.length);
}

// Convert dBFS to linear
export function dbFSToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

// Convert linear to dBFS
export function linearToDbFS(linear: number): number {
  if (linear <= 0) return -Infinity;
  return 20 * Math.log10(linear);
}
