/**
 * Sampler Key Detection - Auto Key Mapping for Samplers
 * 
 * Designed for one-shot analysis of recorded samples to determine
 * the root key for automatic key mapping in sampler synths.
 */

export interface SamplerKeyResult {
  midiNote: number;           // MIDI note number (0-127)
  noteName: string;           // Musical note name (e.g., "C4", "F#3")
  frequency: number;          // Detected frequency in Hz
  confidence: number;         // Detection confidence (0-1)
  algorithm: string;          // Algorithm used
  analysisRegion: {           // Which part of sample was analyzed
    startSample: number;
    endSample: number;
    startTime: number;        // in seconds
    endTime: number;
  };
  suggestedMapping: {         // Suggested key mapping range
    lowNote: number;
    highNote: number;
    rootNote: number;
  };
  pitchStability: number;     // How stable the pitch is (0-1)
  isPercussive: boolean;      // True if sample appears unpitched/percussive
}

export interface KeyDetectionOptions {
  sampleRate: number;
  minFreq?: number;           // Default 50 Hz
  maxFreq?: number;           // Default 4000 Hz
  skipAttack?: number;        // Seconds to skip at start (default 0.05)
  analysisDuration?: number;  // How much to analyze (default 0.3s)
  yinThreshold?: number;      // YIN threshold (default 0.15)
  mappingRange?: number;      // Semitones above/below root for mapping
}

// Note names for MIDI conversion
const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/**
 * Convert frequency to MIDI note number
 */
export function frequencyToMidi(frequency: number): number {
  // MIDI note 69 = A4 = 440 Hz
  return Math.round(69 + 12 * Math.log2(frequency / 440));
}

/**
 * Convert MIDI note to note name + octave
 */
export function midiToNoteName(midi: number): string {
  if (midi < 0 || midi > 127) return '--';
  const octave = Math.floor(midi / 12) - 1;
  const noteIdx = midi % 12;
  return `${NOTE_NAMES[noteIdx]}${octave}`;
}

/**
 * Convert MIDI note to frequency
 */
export function midiToFrequency(midi: number): number {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

/**
 * Apply Hann window to buffer
 */
function applyHannWindow(buffer: Float32Array): Float32Array {
  const result = new Float32Array(buffer.length);
  for (let i = 0; i < buffer.length; i++) {
    const multiplier = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (buffer.length - 1)));
    result[i] = buffer[i] * multiplier;
  }
  return result;
}

/**
 * Calculate RMS of buffer
 */
function calculateRMS(buffer: Float32Array): number {
  let sum = 0;
  for (let i = 0; i < buffer.length; i++) {
    sum += buffer[i] * buffer[i];
  }
  return Math.sqrt(sum / buffer.length);
}

/**
 * Find the attack end by detecting where amplitude stabilizes
 */
function findAttackEnd(buffer: Float32Array, sampleRate: number, windowMs: number = 50): number {
  const windowSize = Math.floor((windowMs / 1000) * sampleRate);
  const numWindows = Math.floor(buffer.length / windowSize);
  
  if (numWindows < 3) return 0;
  
  // Calculate RMS for each window
  const rmsValues: number[] = [];
  for (let w = 0; w < numWindows; w++) {
    const start = w * windowSize;
    const end = start + windowSize;
    rmsValues.push(calculateRMS(buffer.slice(start, end)));
  }
  
  // Find where the amplitude stabilizes (derivative becomes small)
  for (let i = 2; i < rmsValues.length; i++) {
    const prevChange = Math.abs(rmsValues[i - 1] - rmsValues[i - 2]);
    const currChange = Math.abs(rmsValues[i] - rmsValues[i - 1]);
    
    // If changes are small and amplitude is significant, we're past the attack
    if (prevChange < 0.02 && currChange < 0.02 && rmsValues[i] > 0.05) {
      return i * windowSize;
    }
  }
  
  return 0; // No clear attack found
}

/**
 * YIN-based pitch detection (optimized for sampler use)
 */
function detectPitchYIN(
  buffer: Float32Array,
  sampleRate: number,
  threshold: number,
  minFreq: number,
  maxFreq: number
): { pitch: number | null; clarity: number } {
  const bufferSize = buffer.length;
  const minLag = Math.floor(sampleRate / maxFreq);
  const maxLag = Math.min(Math.floor(sampleRate / minFreq), bufferSize / 2);

  if (maxLag <= minLag || bufferSize < maxLag * 2) {
    return { pitch: null, clarity: 0 };
  }

  // Difference function
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

  // Cumulative mean normalized difference
  let runningSum = 0;
  for (let lag = 1; lag < maxLag; lag++) {
    runningSum += yinBuffer[lag];
    yinBuffer[lag] = (yinBuffer[lag] * lag) / runningSum;
  }

  // Find the pitch
  let tau = minLag;
  let found = false;
  
  for (tau = minLag; tau < maxLag; tau++) {
    if (yinBuffer[tau] < threshold) {
      while (tau + 1 < maxLag && yinBuffer[tau + 1] < yinBuffer[tau]) {
        tau++;
      }
      found = true;
      break;
    }
  }

  if (!found) {
    return { pitch: null, clarity: 0 };
  }

  // Parabolic interpolation
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
    return { pitch: null, clarity: 0 };
  }

  return { pitch: frequency, clarity };
}

/**
 * NSDF pitch detection
 */
function detectPitchNSDF(
  buffer: Float32Array,
  sampleRate: number,
  threshold: number,
  minFreq: number,
  maxFreq: number
): { pitch: number | null; clarity: number } {
  const bufferSize = buffer.length;
  const minLag = Math.floor(sampleRate / maxFreq);
  const maxLag = Math.min(Math.floor(sampleRate / minFreq), bufferSize / 2);

  if (maxLag <= minLag) {
    return { pitch: null, clarity: 0 };
  }

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

  // Find peaks
  let maxVal = 0;
  let maxLagFound = 0;

  for (let lag = minLag; lag < maxLag; lag++) {
    if (nsdf[lag] > threshold && 
        nsdf[lag] > nsdf[lag - 1] && 
        nsdf[lag] > nsdf[lag + 1]) {
      if (nsdf[lag] > maxVal) {
        maxVal = nsdf[lag];
        maxLagFound = lag;
      }
    }
  }

  if (maxVal < threshold) {
    return { pitch: null, clarity: 0 };
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
  
  if (frequency < minFreq || frequency > maxFreq || isNaN(frequency)) {
    return { pitch: null, clarity: 0 };
  }

  return { pitch: frequency, clarity: maxVal };
}

/**
 * Analyze pitch stability across the sample
 * Returns a stability score (0-1) and array of detected pitches
 */
function analyzePitchStability(
  buffer: Float32Array,
  sampleRate: number,
  windowSize: number,
  threshold: number,
  minFreq: number,
  maxFreq: number
): { stability: number; pitches: number[]; avgPitch: number | null } {
  const hopSize = Math.floor(windowSize / 2);
  const numWindows = Math.floor((buffer.length - windowSize) / hopSize);
  
  if (numWindows < 2) {
    return { stability: 0, pitches: [], avgPitch: null };
  }
  
  const pitches: number[] = [];
  
  for (let i = 0; i < numWindows; i++) {
    const start = i * hopSize;
    const window = buffer.slice(start, start + windowSize);
    const windowed = applyHannWindow(window);
    const result = detectPitchYIN(windowed, sampleRate, threshold, minFreq, maxFreq);
    
    if (result.pitch !== null && result.clarity > 0.5) {
      pitches.push(result.pitch);
    }
  }
  
  if (pitches.length < 2) {
    return { stability: 0, pitches, avgPitch: null };
  }
  
  // Calculate variance in cents
  const avgPitch = pitches.reduce((a, b) => a + b, 0) / pitches.length;
  let variance = 0;
  
  for (const pitch of pitches) {
    const cents = 1200 * Math.log2(pitch / avgPitch);
    variance += cents * cents;
  }
  
  variance /= pitches.length;
  
  // Convert variance to stability score
  // 0 cents variance = 1.0 stability
  // 50 cents variance = ~0.5 stability
  // 100+ cents variance = ~0 stability
  const stability = Math.max(0, 1 - variance / 2500);
  
  return { stability, pitches, avgPitch };
}

/**
 * Detect if a sample is percussive/unpitched
 * Based on spectral flatness and amplitude envelope
 */
function detectPercussive(buffer: Float32Array, sampleRate: number): boolean {
  // Quick check: very short samples are likely percussive
  if (buffer.length / sampleRate < 0.05) return true;
  
  // Check amplitude decay
  const numSegments = 10;
  const segmentSize = Math.floor(buffer.length / numSegments);
  const amplitudes: number[] = [];
  
  for (let i = 0; i < numSegments; i++) {
    const start = i * segmentSize;
    amplitudes.push(calculateRMS(buffer.slice(start, start + segmentSize)));
  }
  
  // Check for rapid decay (percussive characteristic)
  const initialAmp = amplitudes[0];
  const finalAmp = amplitudes[amplitudes.length - 1];
  
  // If amplitude decays very quickly, likely percussive
  if (initialAmp > 0.3 && finalAmp < 0.02 && amplitudes[2] < initialAmp * 0.3) {
    return true;
  }
  
  return false;
}

/**
 * Main function: Detect the root key of a sample for sampler mapping
 */
export function detectSampleRootKey(
  buffer: Float32Array,
  options: KeyDetectionOptions
): SamplerKeyResult {
  const {
    sampleRate,
    minFreq = 50,
    maxFreq = 4000,
    skipAttack = 0.05,
    analysisDuration = 0.3,
    yinThreshold = 0.15,
    mappingRange = 12 // +/- 1 octave default mapping
  } = options;

  // Check if percussive
  const isPercussive = detectPercussive(buffer, sampleRate);

  // Find attack end automatically
  const autoAttackEnd = findAttackEnd(buffer, sampleRate);
  const manualSkip = Math.floor(skipAttack * sampleRate);
  const attackEnd = Math.max(autoAttackEnd, manualSkip);

  // Determine analysis region
  const analysisSamples = Math.floor(analysisDuration * sampleRate);
  const endSample = Math.min(attackEnd + analysisSamples, buffer.length);
  
  if (endSample - attackEnd < sampleRate / maxFreq * 3) {
    // Not enough samples for analysis
    return {
      midiNote: 60, // Default to C4
      noteName: 'C4',
      frequency: 261.63,
      confidence: 0,
      algorithm: 'none',
      analysisRegion: {
        startSample: attackEnd,
        endSample: endSample,
        startTime: attackEnd / sampleRate,
        endTime: endSample / sampleRate
      },
      suggestedMapping: {
        lowNote: 60 - mappingRange,
        highNote: 60 + mappingRange,
        rootNote: 60
      },
      pitchStability: 0,
      isPercussive: true
    };
  }

  // Extract analysis region
  const analysisBuffer = buffer.slice(attackEnd, endSample);
  const windowedBuffer = applyHannWindow(analysisBuffer);

  // Run multiple detection algorithms
  const yinResult = detectPitchYIN(windowedBuffer, sampleRate, yinThreshold, minFreq, maxFreq);
  const nsdfResult = detectPitchNSDF(windowedBuffer, sampleRate, 0.6, minFreq, maxFreq);

  // Analyze pitch stability
  const stabilityAnalysis = analyzePitchStability(
    analysisBuffer,
    sampleRate,
    Math.floor(sampleRate * 0.05), // 50ms windows
    yinThreshold,
    minFreq,
    maxFreq
  );

  // Choose best result
  let bestPitch: number | null = null;
  let bestConfidence = 0;
  let algorithm = 'none';

  // Prefer YIN, but use NSDF as backup
  if (yinResult.pitch !== null && yinResult.clarity > 0.5) {
    bestPitch = yinResult.pitch;
    bestConfidence = yinResult.clarity;
    algorithm = 'YIN';
  } else if (nsdfResult.pitch !== null && nsdfResult.clarity > 0.5) {
    bestPitch = nsdfResult.pitch;
    bestConfidence = nsdfResult.clarity;
    algorithm = 'NSDF';
  }

  // If stability analysis has good average, use that
  if (stabilityAnalysis.avgPitch !== null && stabilityAnalysis.stability > 0.7) {
    bestPitch = stabilityAnalysis.avgPitch;
    algorithm = 'YIN+Stability';
    bestConfidence = Math.max(bestConfidence, stabilityAnalysis.stability);
  }

  // Calculate final confidence
  const confidence = bestPitch !== null 
    ? bestConfidence * (isPercussive ? 0.5 : 1) * stabilityAnalysis.stability
    : 0;

  // Convert to MIDI
  const midiNote = bestPitch !== null ? frequencyToMidi(bestPitch) : 60;
  const noteName = midiToNoteName(midiNote);
  const frequency = bestPitch || midiToFrequency(60);

  return {
    midiNote,
    noteName,
    frequency,
    confidence: Math.min(1, confidence),
    algorithm,
    analysisRegion: {
      startSample: attackEnd,
      endSample: endSample,
      startTime: attackEnd / sampleRate,
      endTime: endSample / sampleRate
    },
    suggestedMapping: {
      lowNote: Math.max(0, midiNote - mappingRange),
      highNote: Math.min(127, midiNote + mappingRange),
      rootNote: midiNote
    },
    pitchStability: stabilityAnalysis.stability,
    isPercussive
  };
}

/**
 * Batch analyze multiple samples for a multi-sampled instrument
 */
export function batchAnalyzeSamples(
  samples: { buffer: Float32Array; name: string }[],
  sampleRate: number,
  options?: Partial<KeyDetectionOptions>
): Map<string, SamplerKeyResult> {
  const results = new Map<string, SamplerKeyResult>();
  
  for (const sample of samples) {
    const result = detectSampleRootKey(sample.buffer, {
      sampleRate,
      ...options
    });
    results.set(sample.name, result);
  }
  
  return results;
}

/**
 * Generate key mapping for a sampler from detected root keys
 * Returns zones with overlap handling
 */
export function generateKeyZones(
  results: Map<string, SamplerKeyResult>
): Array<{
  sampleName: string;
  lowKey: number;
  highKey: number;
  rootKey: number;
}> {
  const entries = Array.from(results.entries())
    .filter(([, r]) => r.confidence > 0.3)
    .sort((a, b) => a[1].midiNote - b[1].midiNote);

  if (entries.length === 0) return [];

  const zones: Array<{
    sampleName: string;
    lowKey: number;
    highKey: number;
    rootKey: number;
  }> = [];

  for (let i = 0; i < entries.length; i++) {
    const [name, result] = entries[i];
    
    let lowKey: number;
    let highKey: number;

    if (entries.length === 1) {
      lowKey = Math.max(0, result.midiNote - 12);
      highKey = Math.min(127, result.midiNote + 12);
    } else {
      // Calculate boundaries based on neighboring samples
      const prevKey = i > 0 ? entries[i - 1][1].midiNote : 0;
      const nextKey = i < entries.length - 1 ? entries[i + 1][1].midiNote : 127;
      
      lowKey = i === 0 ? 0 : Math.floor((prevKey + result.midiNote) / 2) + 1;
      highKey = i === entries.length - 1 ? 127 : Math.floor((result.midiNote + nextKey) / 2);
    }

    zones.push({
      sampleName: name,
      lowKey,
      highKey,
      rootKey: result.midiNote
    });
  }

  return zones;
}
