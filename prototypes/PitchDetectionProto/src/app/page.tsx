'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Slider } from '@/components/ui/slider'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { 
  Mic, MicOff, Volume2, Activity, Music, Zap, Brain, Signal,
  Play, Square, Gauge, Waves, KeyRound, CheckCircle2, AlertCircle, Piano
} from 'lucide-react'
import {
  detectPitchZeroCrossing,
  detectPitchAutocorrelation,
  detectPitchYIN,
  detectPitchHPS,
  detectPitchNSDF,
  frequencyToNote,
  calculateRMS,
  applyHannWindow,
  PitchDetectionResult
} from '@/lib/pitch-detection'
import {
  detectSampleRootKey,
  midiToNoteName,
  midiToFrequency,
  SamplerKeyResult,
  KeyDetectionOptions
} from '@/lib/sampler-key-detection'

// ========================================
// ALGORITHM METADATA
// ========================================
const ALGORITHMS = {
  'zero-crossing': {
    name: 'Zero-Crossing Rate',
    icon: Signal,
    description: 'Simplest pitch detection method that counts zero crossings in the signal.',
    complexity: 'O(n)',
    latency: 'Very Low',
    accuracy: 'Low',
    bestFor: 'Simple sine waves, educational purposes',
    limitations: 'Poor with harmonics, noise-sensitive, octave errors',
    paper: null,
    industryUse: 'Basic guitar tuners, simple applications',
    color: 'text-green-500'
  },
  'autocorrelation': {
    name: 'Autocorrelation',
    icon: Activity,
    description: 'Classic time-domain method that correlates the signal with time-shifted versions of itself.',
    complexity: 'O(n²)',
    latency: 'Low',
    accuracy: 'Medium',
    bestFor: 'Speech, monophonic instruments, real-time applications',
    limitations: 'Can have octave errors, computationally heavier than ZCR',
    paper: 'Rabiner & Schafer (1978) - Digital Processing of Speech Signals',
    industryUse: 'Praat, many classic pitch trackers',
    color: 'text-blue-500'
  },
  'yin': {
    name: 'YIN Algorithm',
    icon: Zap,
    description: 'Improved autocorrelation with cumulative mean normalized difference function.',
    complexity: 'O(n²)',
    latency: 'Low',
    accuracy: 'High',
    bestFor: 'Speech recognition, music analysis, professional audio',
    limitations: 'Requires proper threshold tuning, slightly more compute than autocorrelation',
    paper: 'de Cheveigné & Kawahara (2002) - YIN, a fundamental frequency estimator',
    industryUse: 'Aubio, Librosa, widely used in research',
    color: 'text-yellow-500'
  },
  'hps': {
    name: 'Harmonic Product Spectrum',
    icon: Waves,
    description: 'FFT-based frequency domain method that multiplies downsampled spectra to find fundamental.',
    complexity: 'O(n log n)',
    latency: 'Medium (FFT window)',
    accuracy: 'Medium-High',
    bestFor: 'Harmonic instruments, polyphonic hints, frequency analysis',
    limitations: 'Requires sufficient FFT size, less accurate for inharmonic sounds',
    paper: 'Schroeder (1968) - Period histogram and product spectrum',
    industryUse: 'Spectral analysis tools, music information retrieval',
    color: 'text-purple-500'
  },
  'nsdf': {
    name: 'NSDF (McLeod)',
    icon: Music,
    description: 'Normalized Square Difference Function with parabolic interpolation.',
    complexity: 'O(n²)',
    latency: 'Low',
    accuracy: 'High',
    bestFor: 'Real-time pitch tracking, musical instruments',
    limitations: 'Similar to YIN, requires threshold tuning',
    paper: 'McLeod & Wyvill (2005) - A smarter way to find pitch',
    industryUse: 'Used in some real-time tuners and audio software',
    color: 'text-pink-500'
  }
} as const

type AlgorithmKey = keyof typeof ALGORITHMS

// ========================================
// PIANO KEYBOARD COMPONENT
// ========================================
function PianoKeyboard({ 
  rootKey, 
  lowKey, 
  highKey,
  numKeys = 49,
  startKey = 36
}: { 
  rootKey: number
  lowKey: number
  highKey: number
  numKeys?: number
  startKey?: number
}) {
  const keys: JSX.Element[] = []
  
  const isBlackKey = (midi: number) => {
    const noteInOctave = midi % 12
    return [1, 3, 6, 8, 10].includes(noteInOctave)
  }

  const whiteKeys: number[] = []
  const blackKeyPositions = new Map<number, number>()
  
  for (let i = 0; i < numKeys; i++) {
    const midi = startKey + i
    if (!isBlackKey(midi)) {
      whiteKeys.push(midi)
    }
  }

  let whiteKeyIndex = 0
  for (let i = 0; i < numKeys; i++) {
    const midi = startKey + i
    if (isBlackKey(midi)) {
      blackKeyPositions.set(midi, whiteKeyIndex - 0.5)
    } else {
      whiteKeyIndex++
    }
  }

  const whiteKeyWidth = 100 / whiteKeys.length

  whiteKeys.forEach((midi, idx) => {
    const isInMapping = midi >= lowKey && midi <= highKey
    const isRoot = midi === rootKey
    
    keys.push(
      <div
        key={`white-${midi}`}
        className={`absolute h-24 border border-slate-300 rounded-b transition-colors ${
          isRoot ? 'bg-green-500 border-green-600' :
          isInMapping ? 'bg-blue-200 border-blue-300' :
          'bg-white hover:bg-slate-50'
        }`}
        style={{
          left: `${idx * whiteKeyWidth}%`,
          width: `${whiteKeyWidth}%`,
          zIndex: 1
        }}
      >
        {midi % 12 === 0 && (
          <span className="absolute bottom-1 left-1/2 -translate-x-1/2 text-[10px] text-slate-500 font-medium">
            C{Math.floor(midi / 12) - 1}
          </span>
        )}
        {isRoot && (
          <span className="absolute top-1 left-1/2 -translate-x-1/2 text-[9px] text-white font-bold">
            ROOT
          </span>
        )}
      </div>
    )
  })

  blackKeyPositions.forEach((pos, midi) => {
    const isInMapping = midi >= lowKey && midi <= highKey
    const isRoot = midi === rootKey
    
    keys.push(
      <div
        key={`black-${midi}`}
        className={`absolute h-14 rounded-b transition-colors ${
          isRoot ? 'bg-green-600' :
          isInMapping ? 'bg-blue-500' :
          'bg-slate-800 hover:bg-slate-700'
        }`}
        style={{
          left: `${(pos + 0.65) * whiteKeyWidth}%`,
          width: `${whiteKeyWidth * 0.6}%`,
          zIndex: 2
        }}
      />
    )
  })

  return (
    <div className="relative w-full h-24 bg-slate-100 rounded-lg overflow-hidden">
      {keys}
    </div>
  )
}

// ========================================
// MIDI NOTE DISPLAY COMPONENT
// ========================================
function MidiNoteDisplay({ midiNote, noteName, frequency }: { midiNote: number, noteName: string, frequency: number }) {
  return (
    <div className="flex items-center gap-4 p-4 bg-gradient-to-r from-slate-800 to-slate-900 rounded-lg">
      <div className="text-center">
        <div className="text-sm text-slate-400 mb-1">MIDI Note</div>
        <div className="text-3xl font-mono font-bold text-white">{midiNote}</div>
      </div>
      <Separator orientation="vertical" className="h-12 bg-slate-600" />
      <div className="text-center">
        <div className="text-sm text-slate-400 mb-1">Note Name</div>
        <div className="text-3xl font-mono font-bold text-green-400">{noteName}</div>
      </div>
      <Separator orientation="vertical" className="h-12 bg-slate-600" />
      <div className="text-center">
        <div className="text-sm text-slate-400 mb-1">Frequency</div>
        <div className="text-xl font-mono text-blue-400">{frequency.toFixed(1)} Hz</div>
      </div>
    </div>
  )
}

// ========================================
// MAIN COMPONENT
// ========================================
export default function PitchDetectionApp() {
  // ========================================
  // STATE - Real-time Pitch Detection
  // ========================================
  const [isListening, setIsListening] = useState(false)
  const [selectedAlgorithm, setSelectedAlgorithm] = useState<AlgorithmKey>('yin')
  const [detectedPitch, setDetectedPitch] = useState<PitchDetectionResult | null>(null)
  const [audioLevel, setAudioLevel] = useState(0)
  const [pitchHistory, setPitchHistory] = useState<{ time: number; pitch: number | null }[]>([])
  const [error, setError] = useState<string | null>(null)
  const [yinThreshold, setYinThreshold] = useState(0.15)
  const [minFreq, setMinFreq] = useState(50)
  const [maxFreq, setMaxFreq] = useState(2000)

  // ========================================
  // STATE - Sampler Key Detection
  // ========================================
  const [isRecording, setIsRecording] = useState(false)
  const [isPlaying, setIsPlaying] = useState(false)
  const [recordedBuffer, setRecordedBuffer] = useState<Float32Array | null>(null)
  const [sampleRate, setSampleRate] = useState(48000)
  const [detectionResult, setDetectionResult] = useState<SamplerKeyResult | null>(null)
  
  // Sampler detection parameters
  const [skipAttack, setSkipAttack] = useState(0.05)
  const [analysisDuration, setAnalysisDuration] = useState(0.3)
  const [mappingRange, setMappingRange] = useState(12)

  // ========================================
  // REFS
  // ========================================
  const audioContextRef = useRef<AudioContext | null>(null)
  const analyserRef = useRef<AnalyserNode | null>(null)
  const mediaStreamRef = useRef<MediaStream | null>(null)
  const animationFrameRef = useRef<number | null>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const pitchCanvasRef = useRef<HTMLCanvasElement>(null)
  const samplerCanvasRef = useRef<HTMLCanvasElement>(null)
  const analysisCanvasRef = useRef<HTMLCanvasElement>(null)
  const scriptProcessorRef = useRef<ScriptProcessorNode | null>(null)
  const recordedChunksRef = useRef<Float32Array[]>([])
  const sourceRef = useRef<AudioBufferSourceNode | null>(null)
  
  // Refs for real-time processing values
  const selectedAlgorithmRef = useRef(selectedAlgorithm)
  const yinThresholdRef = useRef(yinThreshold)
  const minFreqRef = useRef(minFreq)
  const maxFreqRef = useRef(maxFreq)
  const pitchHistoryRef = useRef(pitchHistory)

  // Keep refs in sync
  useEffect(() => {
    selectedAlgorithmRef.current = selectedAlgorithm
  }, [selectedAlgorithm])
  useEffect(() => {
    yinThresholdRef.current = yinThreshold
  }, [yinThreshold])
  useEffect(() => {
    minFreqRef.current = minFreq
  }, [minFreq])
  useEffect(() => {
    maxFreqRef.current = maxFreq
  }, [maxFreq])
  useEffect(() => {
    pitchHistoryRef.current = pitchHistory
  }, [pitchHistory])

  // ========================================
  // REAL-TIME PITCH DETECTION
  // ========================================
  const detectPitch = useCallback((buffer: Float32Array, sampleRate: number, algo: AlgorithmKey, threshold: number, min: number, max: number): PitchDetectionResult => {
    const windowedBuffer = applyHannWindow(buffer)
    switch (algo) {
      case 'zero-crossing':
        return detectPitchZeroCrossing(buffer, sampleRate)
      case 'autocorrelation':
        return detectPitchAutocorrelation(buffer, sampleRate, min, max)
      case 'yin':
        return detectPitchYIN(windowedBuffer, sampleRate, threshold, min, max)
      case 'hps':
        return detectPitchHPS(windowedBuffer, sampleRate, 5, min, max)
      case 'nsdf':
        return detectPitchNSDF(windowedBuffer, sampleRate, 0.6, min, max)
      default:
        return detectPitchYIN(windowedBuffer, sampleRate, threshold, min, max)
    }
  }, [])

  const drawWaveform = useCallback((canvas: HTMLCanvasElement, buffer: Float32Array, pitch: PitchDetectionResult | null, sampleRate: number) => {
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const width = canvas.width
    const height = canvas.height

    ctx.fillStyle = 'rgb(15, 23, 42)'
    ctx.fillRect(0, 0, width, height)

    ctx.strokeStyle = 'rgb(51, 65, 85)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, height / 2)
    ctx.lineTo(width, height / 2)
    ctx.stroke()

    ctx.strokeStyle = 'rgb(34, 197, 94)'
    ctx.lineWidth = 2
    ctx.beginPath()

    const sliceWidth = width / buffer.length
    let x = 0

    for (let i = 0; i < buffer.length; i++) {
      const y = (buffer[i] + 1) / 2 * height
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
      x += sliceWidth
    }
    ctx.stroke()

    if (pitch?.pitch && sampleRate > 0) {
      ctx.strokeStyle = 'rgb(239, 68, 68)'
      ctx.lineWidth = 2
      ctx.setLineDash([5, 5])
      ctx.beginPath()
      const period = sampleRate / pitch.pitch
      const pixelsPerPeriod = (period / buffer.length) * width
      for (let px = 0; px < width; px += pixelsPerPeriod) {
        ctx.moveTo(px, 0)
        ctx.lineTo(px, height)
      }
      ctx.stroke()
      ctx.setLineDash([])
    }
  }, [])

  const drawPitchHistoryOnCanvas = useCallback((canvas: HTMLCanvasElement, history: typeof pitchHistory) => {
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const width = canvas.width
    const height = canvas.height

    ctx.fillStyle = 'rgb(15, 23, 42)'
    ctx.fillRect(0, 0, width, height)

    if (history.length < 2) return

    ctx.strokeStyle = 'rgb(59, 130, 246)'
    ctx.lineWidth = 2
    ctx.beginPath()

    let started = false
    history.forEach((point, i) => {
      if (point.pitch === null) return
      const x = (i / history.length) * width
      const minPitch = 50
      const maxPitch = 2000
      const y = height - ((Math.log2(point.pitch / minPitch)) / (Math.log2(maxPitch / minPitch))) * height
      if (!started) { ctx.moveTo(x, y); started = true }
      else ctx.lineTo(x, y)
    })
    ctx.stroke()

    ctx.strokeStyle = 'rgb(71, 85, 105)'
    ctx.lineWidth = 1
    ctx.setLineDash([2, 2])

    const referenceFreqs = [65.41, 82.41, 110, 146.83, 196, 246.94, 329.63, 440, 587.33, 783.99, 1046.5, 1396.9, 1760]
    const noteNames = ['C2', 'E2', 'A2', 'D3', 'G3', 'B3', 'E4', 'A4', 'D5', 'G5', 'C6', 'F6', 'A6']

    referenceFreqs.forEach((freq, i) => {
      const y = height - ((Math.log2(freq / 50)) / (Math.log2(2000 / 50))) * height
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(width, y)
      ctx.stroke()
      ctx.fillStyle = 'rgb(148, 163, 184)'
      ctx.font = '10px sans-serif'
      ctx.fillText(noteNames[i], 5, y - 3)
    })
    ctx.setLineDash([])
  }, [])

  // Real-time processing loop
  useEffect(() => {
    const processAudio = () => {
      if (!analyserRef.current || !audioContextRef.current) {
        animationFrameRef.current = requestAnimationFrame(processAudio)
        return
      }

      const analyser = analyserRef.current
      const sr = audioContextRef.current.sampleRate
      const bufferLength = analyser.fftSize
      const buffer = new Float32Array(bufferLength)

      analyser.getFloatTimeDomainData(buffer)
      const rms = calculateRMS(buffer)
      setAudioLevel(rms)

      const result = detectPitch(buffer, sr, selectedAlgorithmRef.current, yinThresholdRef.current, minFreqRef.current, maxFreqRef.current)
      setDetectedPitch(result)

      setPitchHistory(prev => {
        const newHistory = [...prev, { time: Date.now(), pitch: result.pitch }]
        return newHistory.slice(-100)
      })

      if (canvasRef.current) drawWaveform(canvasRef.current, buffer, result, sr)
      if (pitchCanvasRef.current) drawPitchHistoryOnCanvas(pitchCanvasRef.current, pitchHistoryRef.current)

      animationFrameRef.current = requestAnimationFrame(processAudio)
    }

    if (isListening) {
      animationFrameRef.current = requestAnimationFrame(processAudio)
    }

    return () => {
      if (animationFrameRef.current) cancelAnimationFrame(animationFrameRef.current)
    }
  }, [isListening, detectPitch, drawWaveform, drawPitchHistoryOnCanvas])

  // Start/stop real-time listening
  const startListening = useCallback(async () => {
    try {
      setError(null)
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false }
      })
      mediaStreamRef.current = stream
      audioContextRef.current = new AudioContext()
      const source = audioContextRef.current.createMediaStreamSource(stream)
      const analyser = audioContextRef.current.createAnalyser()
      analyser.fftSize = 4096
      analyser.smoothingTimeConstant = 0
      source.connect(analyser)
      analyserRef.current = analyser
      setIsListening(true)
    } catch (err) {
      setError('Failed to access microphone')
    }
  }, [])

  const stopListening = useCallback(() => {
    if (animationFrameRef.current) cancelAnimationFrame(animationFrameRef.current)
    if (mediaStreamRef.current) mediaStreamRef.current.getTracks().forEach(track => track.stop())
    if (audioContextRef.current) audioContextRef.current.close()
    setIsListening(false)
    setAudioLevel(0)
    setDetectedPitch(null)
    setPitchHistory([])
  }, [])

  // ========================================
  // SAMPLER KEY DETECTION
  // ========================================
  const initAudioContext = useCallback(() => {
    if (!audioContextRef.current) {
      audioContextRef.current = new AudioContext()
      setSampleRate(audioContextRef.current.sampleRate)
    }
    return audioContextRef.current
  }, [])

  const startRecording = async () => {
    try {
      setError(null)
      setRecordedBuffer(null)
      setDetectionResult(null)
      recordedChunksRef.current = []

      const ctx = initAudioContext()
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false }
      })
      mediaStreamRef.current = stream

      const source = ctx.createMediaStreamSource(stream)
      const processor = ctx.createScriptProcessor(4096, 1, 1)
      scriptProcessorRef.current = processor
      source.connect(processor)
      processor.connect(ctx.destination)

      processor.onaudioprocess = (e) => {
        const inputData = e.inputBuffer.getChannelData(0)
        const chunk = new Float32Array(inputData.length)
        chunk.set(inputData)
        recordedChunksRef.current.push(chunk)
      }
      setIsRecording(true)
    } catch (err) {
      setError('Failed to access microphone')
    }
  }

  const stopRecording = useCallback(() => {
    if (scriptProcessorRef.current) scriptProcessorRef.current.disconnect()
    if (mediaStreamRef.current) mediaStreamRef.current.getTracks().forEach(track => track.stop())

    const chunks = recordedChunksRef.current
    if (chunks.length > 0) {
      const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0)
      const buffer = new Float32Array(totalLength)
      let offset = 0
      for (const chunk of chunks) {
        buffer.set(chunk, offset)
        offset += chunk.length
      }
      setRecordedBuffer(buffer)
    }
    setIsRecording(false)
  }, [])

  const playSample = useCallback(() => {
    if (!recordedBuffer || !audioContextRef.current) return
    if (sourceRef.current) { sourceRef.current.stop(); sourceRef.current = null }

    const ctx = audioContextRef.current
    const audioBuffer = ctx.createBuffer(1, recordedBuffer.length, ctx.sampleRate)
    audioBuffer.getChannelData(0).set(recordedBuffer)
    const source = ctx.createBufferSource()
    source.buffer = audioBuffer
    source.connect(ctx.destination)
    sourceRef.current = source
    source.onended = () => { setIsPlaying(false); sourceRef.current = null }
    source.start()
    setIsPlaying(true)
  }, [recordedBuffer])

  const stopPlayback = useCallback(() => {
    if (sourceRef.current) { sourceRef.current.stop(); sourceRef.current = null }
    setIsPlaying(false)
  }, [])

  const analyzeSample = useCallback(() => {
    if (!recordedBuffer) return
    const options: KeyDetectionOptions = {
      sampleRate,
      minFreq,
      maxFreq,
      skipAttack,
      analysisDuration,
      yinThreshold,
      mappingRange
    }
    const result = detectSampleRootKey(recordedBuffer, options)
    setDetectionResult(result)
  }, [recordedBuffer, sampleRate, minFreq, maxFreq, skipAttack, analysisDuration, yinThreshold, mappingRange])

  // Auto-analyze when buffer changes
  useEffect(() => {
    if (recordedBuffer) {
      const frameId = requestAnimationFrame(() => analyzeSample())
      return () => cancelAnimationFrame(frameId)
    }
  }, [recordedBuffer, analyzeSample])

  // Draw sampler waveform
  useEffect(() => {
    if (!samplerCanvasRef.current || !recordedBuffer) return
    const canvas = samplerCanvasRef.current
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const width = canvas.width
    const height = canvas.height

    ctx.fillStyle = 'rgb(15, 23, 42)'
    ctx.fillRect(0, 0, width, height)
    ctx.strokeStyle = 'rgb(51, 65, 85)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, height / 2)
    ctx.lineTo(width, height / 2)
    ctx.stroke()

    if (detectionResult) {
      const startX = (detectionResult.analysisRegion.startSample / recordedBuffer.length) * width
      const endX = (detectionResult.analysisRegion.endSample / recordedBuffer.length) * width
      ctx.fillStyle = 'rgba(34, 197, 94, 0.2)'
      ctx.fillRect(startX, 0, endX - startX, height)
      ctx.strokeStyle = 'rgb(34, 197, 94)'
      ctx.setLineDash([4, 4])
      ctx.beginPath()
      ctx.moveTo(startX, 0)
      ctx.lineTo(startX, height)
      ctx.moveTo(endX, 0)
      ctx.lineTo(endX, height)
      ctx.stroke()
      ctx.setLineDash([])
    }

    ctx.strokeStyle = 'rgb(59, 130, 246)'
    ctx.lineWidth = 1.5
    ctx.beginPath()
    const step = Math.ceil(recordedBuffer.length / width)
    for (let i = 0; i < width; i++) {
      const sampleIndex = Math.floor(i * step)
      const sample = recordedBuffer[sampleIndex] || 0
      const y = (sample + 1) / 2 * height
      if (i === 0) ctx.moveTo(i, y)
      else ctx.lineTo(i, y)
    }
    ctx.stroke()
  }, [recordedBuffer, detectionResult])

  // Draw analysis detail
  useEffect(() => {
    if (!analysisCanvasRef.current || !recordedBuffer || !detectionResult) return
    const canvas = analysisCanvasRef.current
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const width = canvas.width
    const height = canvas.height

    ctx.fillStyle = 'rgb(15, 23, 42)'
    ctx.fillRect(0, 0, width, height)

    const { startSample, endSample } = detectionResult.analysisRegion
    const analysisBuffer = recordedBuffer.slice(startSample, endSample)

    ctx.strokeStyle = 'rgb(51, 65, 85)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, height / 2)
    ctx.lineTo(width, height / 2)
    ctx.stroke()

    ctx.strokeStyle = 'rgb(34, 197, 94)'
    ctx.lineWidth = 2
    ctx.beginPath()
    const step = Math.max(1, Math.floor(analysisBuffer.length / width))
    for (let i = 0; i < width; i++) {
      const sampleIndex = i * step
      const sample = analysisBuffer[sampleIndex] || 0
      const y = (sample + 1) / 2 * height
      if (i === 0) ctx.moveTo(i, y)
      else ctx.lineTo(i, y)
    }
    ctx.stroke()

    if (detectionResult.frequency > 0) {
      const period = sampleRate / detectionResult.frequency
      const periodPixels = (period / (endSample - startSample)) * width
      ctx.strokeStyle = 'rgb(239, 68, 68)'
      ctx.lineWidth = 1
      ctx.setLineDash([3, 3])
      ctx.beginPath()
      for (let x = 0; x < width; x += periodPixels) {
        ctx.moveTo(x, 0)
        ctx.lineTo(x, height)
      }
      ctx.stroke()
      ctx.setLineDash([])
    }
  }, [recordedBuffer, detectionResult, sampleRate])

  // Cleanup
  useEffect(() => {
    return () => {
      if (sourceRef.current) sourceRef.current.stop()
      if (mediaStreamRef.current) mediaStreamRef.current.getTracks().forEach(track => track.stop())
      if (audioContextRef.current) audioContextRef.current.close()
    }
  }, [])

  const algorithm = ALGORITHMS[selectedAlgorithm]
  const AlgorithmIcon = algorithm.icon

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 text-white p-4 md:p-8">
      <div className="max-w-7xl mx-auto space-y-6">
        {/* Header */}
        <div className="text-center space-y-2">
          <h1 className="text-3xl md:text-4xl font-bold bg-gradient-to-r from-green-400 via-blue-500 to-purple-500 bg-clip-text text-transparent">
            Audio Pitch Detection Algorithms
          </h1>
          <p className="text-slate-400 max-w-3xl mx-auto">
            Interactive demonstrations of pitch detection algorithms for audio applications and VST development.
            Real-time analysis, algorithm comparison, and sampler key mapping tools.
          </p>
        </div>

        {/* Main Tabs */}
        <Tabs defaultValue="realtime" className="w-full">
          <TabsList className="grid w-full grid-cols-2 bg-slate-800/50 h-auto">
            <TabsTrigger value="realtime" className="py-3">
              <div className="flex items-center gap-2">
                <Activity className="w-4 h-4" />
                <span>Real-time Detection</span>
              </div>
            </TabsTrigger>
            <TabsTrigger value="sampler" className="py-3">
              <div className="flex items-center gap-2">
                <KeyRound className="w-4 h-4" />
                <span>Sampler Key Mapping</span>
              </div>
            </TabsTrigger>
          </TabsList>

          {/* ============================================== */}
          {/* REAL-TIME PITCH DETECTION TAB */}
          {/* ============================================== */}
          <TabsContent value="realtime" className="mt-6 space-y-6">
            {/* Control Panel */}
            <Card className="bg-slate-800/50 border-slate-700 backdrop-blur">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Volume2 className="w-5 h-5 text-green-400" />
                  Audio Input Control
                </CardTitle>
                <CardDescription>Connect your microphone to test pitch detection in real-time</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex flex-wrap items-center gap-4">
                  <Button
                    onClick={isListening ? stopListening : startListening}
                    className={isListening ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'}
                    size="lg"
                  >
                    {isListening ? <><MicOff className="w-5 h-5 mr-2" />Stop Listening</> : <><Mic className="w-5 h-5 mr-2" />Start Listening</>}
                  </Button>
                  <div className="flex items-center gap-2 flex-1 min-w-48">
                    <span className="text-sm text-slate-400">Level:</span>
                    <div className="flex-1 h-4 bg-slate-700 rounded-full overflow-hidden">
                      <div className="h-full transition-all duration-75 rounded-full" style={{ width: `${Math.min(100, audioLevel * 500)}%`, background: audioLevel > 0.02 ? 'linear-gradient(to right, #22c55e, #84cc16)' : 'linear-gradient(to right, #374151, #4b5563)' }} />
                    </div>
                    <span className="text-sm text-slate-400 w-12 text-right">{Math.round(audioLevel * 1000) / 10}%</span>
                  </div>
                </div>

                {/* Detected Pitch Display */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-slate-900/50 rounded-lg">
                  <div className="text-center p-4 bg-slate-800 rounded-lg">
                    <div className="text-sm text-slate-400 mb-1">Frequency</div>
                    <div className={`text-4xl font-mono font-bold ${algorithm.color}`}>
                      {detectedPitch?.pitch ? `${detectedPitch.pitch.toFixed(1)} Hz` : '-- Hz'}
                    </div>
                  </div>
                  <div className="text-center p-4 bg-slate-800 rounded-lg">
                    <div className="text-sm text-slate-400 mb-1">Musical Note</div>
                    <div className="text-4xl font-mono font-bold text-blue-400">
                      {detectedPitch?.pitch ? frequencyToNote(detectedPitch.pitch) : '--'}
                    </div>
                  </div>
                  <div className="text-center p-4 bg-slate-800 rounded-lg">
                    <div className="text-sm text-slate-400 mb-1">Clarity</div>
                    <div className="text-4xl font-mono font-bold text-yellow-400">
                      {detectedPitch ? `${(detectedPitch.clarity * 100).toFixed(0)}%` : '--%'}
                    </div>
                  </div>
                </div>

                {error && (
                  <Alert variant="destructive">
                    <Brain className="w-4 h-4" />
                    <AlertTitle>Error</AlertTitle>
                    <AlertDescription>{error}</AlertDescription>
                  </Alert>
                )}
              </CardContent>
            </Card>

            {/* Algorithm Selection */}
            <Tabs value={selectedAlgorithm} onValueChange={(v) => setSelectedAlgorithm(v as AlgorithmKey)}>
              <TabsList className="grid w-full grid-cols-5 bg-slate-800/50">
                {Object.entries(ALGORITHMS).map(([key, algo]) => {
                  const Icon = algo.icon
                  return (
                    <TabsTrigger key={key} value={key} className="flex flex-col md:flex-row items-center gap-1 md:gap-2 py-2">
                      <Icon className={`w-4 h-4 ${algo.color}`} />
                      <span className="text-xs md:text-sm">{algo.name}</span>
                    </TabsTrigger>
                  )
                })}
              </TabsList>

              {Object.entries(ALGORITHMS).map(([key, algo]) => (
                <TabsContent key={key} value={key} className="mt-4">
                  <Card className="bg-slate-800/50 border-slate-700">
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        <algo.icon className={`w-6 h-6 ${algo.color}`} />
                        {algo.name}
                      </CardTitle>
                      <CardDescription>{algo.description}</CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                        <div className="p-3 bg-slate-900/50 rounded-lg">
                          <div className="text-xs text-slate-400 mb-1">Complexity</div>
                          <Badge variant="secondary" className="font-mono">{algo.complexity}</Badge>
                        </div>
                        <div className="p-3 bg-slate-900/50 rounded-lg">
                          <div className="text-xs text-slate-400 mb-1">Latency</div>
                          <Badge variant="secondary">{algo.latency}</Badge>
                        </div>
                        <div className="p-3 bg-slate-900/50 rounded-lg">
                          <div className="text-xs text-slate-400 mb-1">Accuracy</div>
                          <Badge variant={algo.accuracy === 'High' ? 'default' : 'secondary'}>{algo.accuracy}</Badge>
                        </div>
                        <div className="p-3 bg-slate-900/50 rounded-lg">
                          <div className="text-xs text-slate-400 mb-1">Industry Use</div>
                          <div className="text-sm">{algo.industryUse}</div>
                        </div>
                      </div>
                      <Separator className="bg-slate-700" />
                      <div className="grid md:grid-cols-2 gap-4">
                        <div>
                          <h4 className="font-medium mb-2 text-green-400">Best For:</h4>
                          <p className="text-sm text-slate-300">{algo.bestFor}</p>
                        </div>
                        <div>
                          <h4 className="font-medium mb-2 text-red-400">Limitations:</h4>
                          <p className="text-sm text-slate-300">{algo.limitations}</p>
                        </div>
                      </div>
                      {algo.paper && (
                        <div className="p-3 bg-slate-900/50 rounded-lg">
                          <div className="text-xs text-slate-400 mb-1">Reference Paper:</div>
                          <p className="text-sm text-slate-300">{algo.paper}</p>
                        </div>
                      )}
                    </CardContent>
                  </Card>
                </TabsContent>
              ))}
            </Tabs>

            {/* Visualization Panel */}
            <div className="grid md:grid-cols-2 gap-4">
              <Card className="bg-slate-800/50 border-slate-700">
                <CardHeader>
                  <CardTitle className="flex items-center gap-2 text-lg"><Activity className="w-5 h-5 text-green-400" />Waveform</CardTitle>
                  <CardDescription>Real-time audio signal visualization</CardDescription>
                </CardHeader>
                <CardContent>
                  <canvas ref={canvasRef} width={600} height={200} className="w-full h-48 rounded-lg" />
                </CardContent>
              </Card>
              <Card className="bg-slate-800/50 border-slate-700">
                <CardHeader>
                  <CardTitle className="flex items-center gap-2 text-lg"><Music className="w-5 h-5 text-blue-400" />Pitch Contour</CardTitle>
                  <CardDescription>Pitch tracking history (log frequency scale)</CardDescription>
                </CardHeader>
                <CardContent>
                  <canvas ref={pitchCanvasRef} width={600} height={200} className="w-full h-48 rounded-lg" />
                </CardContent>
              </Card>
            </div>

            {/* Algorithm Parameters */}
            <Card className="bg-slate-800/50 border-slate-700">
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Gauge className="w-5 h-5 text-purple-400" />Algorithm Parameters</CardTitle>
                <CardDescription>Adjust detection parameters to see how they affect performance</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="grid md:grid-cols-3 gap-6">
                  <div className="space-y-2">
                    <div className="flex justify-between"><Label>YIN Threshold</Label><span className="text-sm text-slate-400">{yinThreshold.toFixed(2)}</span></div>
                    <Slider value={[yinThreshold]} onValueChange={([v]) => setYinThreshold(v)} min={0.05} max={0.5} step={0.01} disabled={selectedAlgorithm !== 'yin'} />
                    <p className="text-xs text-slate-500">Lower = more sensitive, Higher = stricter</p>
                  </div>
                  <div className="space-y-2">
                    <div className="flex justify-between"><Label>Min Frequency</Label><span className="text-sm text-slate-400">{minFreq} Hz</span></div>
                    <Slider value={[minFreq]} onValueChange={([v]) => setMinFreq(v)} min={20} max={200} step={10} />
                    <p className="text-xs text-slate-500">Lowest frequency to detect</p>
                  </div>
                  <div className="space-y-2">
                    <div className="flex justify-between"><Label>Max Frequency</Label><span className="text-sm text-slate-400">{maxFreq} Hz</span></div>
                    <Slider value={[maxFreq]} onValueChange={([v]) => setMaxFreq(v)} min={500} max={4000} step={100} />
                    <p className="text-xs text-slate-500">Highest frequency to detect</p>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Algorithm Comparison Table */}
            <Card className="bg-slate-800/50 border-slate-700">
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Brain className="w-5 h-5 text-cyan-400" />Algorithm Comparison Summary</CardTitle>
                <CardDescription>Quick reference for choosing the right algorithm</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-slate-700">
                        <th className="text-left p-3">Algorithm</th>
                        <th className="text-left p-3">Domain</th>
                        <th className="text-left p-3">Complexity</th>
                        <th className="text-left p-3">Accuracy</th>
                        <th className="text-left p-3">Real-time</th>
                        <th className="text-left p-3">VST Suitable</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr className="border-b border-slate-700/50 hover:bg-slate-700/30"><td className="p-3 font-medium">Zero-Crossing</td><td className="p-3">Time</td><td className="p-3"><Badge variant="outline" className="bg-green-900/30 text-green-400">O(n)</Badge></td><td className="p-3">Low</td><td className="p-3 text-green-400">Excellent</td><td className="text-slate-500">Limited</td></tr>
                      <tr className="border-b border-slate-700/50 hover:bg-slate-700/30"><td className="p-3 font-medium">Autocorrelation</td><td className="p-3">Time</td><td className="p-3"><Badge variant="outline" className="bg-yellow-900/30 text-yellow-400">O(n²)</Badge></td><td className="p-3">Medium</td><td className="p-3 text-green-400">Good</td><td className="text-green-400">Yes</td></tr>
                      <tr className="border-b border-slate-700/50 hover:bg-slate-700/30"><td className="p-3 font-medium">YIN</td><td className="p-3">Time</td><td className="p-3"><Badge variant="outline" className="bg-yellow-900/30 text-yellow-400">O(n²)</Badge></td><td className="p-3 text-green-400">High</td><td className="p-3 text-green-400">Good</td><td className="text-green-400">Yes</td></tr>
                      <tr className="border-b border-slate-700/50 hover:bg-slate-700/30"><td className="p-3 font-medium">HPS</td><td className="p-3">Frequency</td><td className="p-3"><Badge variant="outline" className="bg-blue-900/30 text-blue-400">O(n log n)</Badge></td><td className="p-3">Medium-High</td><td className="p-3 text-yellow-400">Medium</td><td className="text-green-400">Yes</td></tr>
                      <tr className="hover:bg-slate-700/30"><td className="p-3 font-medium">NSDF</td><td className="p-3">Time</td><td className="p-3"><Badge variant="outline" className="bg-yellow-900/30 text-yellow-400">O(n²)</Badge></td><td className="p-3 text-green-400">High</td><td className="p-3 text-green-400">Good</td><td className="text-green-400">Yes</td></tr>
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          {/* ============================================== */}
          {/* SAMPLER KEY MAPPING TAB */}
          {/* ============================================== */}
          <TabsContent value="sampler" className="mt-6 space-y-6">
            {/* Recording Control */}
            <Card className="bg-slate-800/50 border-slate-700">
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Mic className="w-5 h-5 text-red-400" />Sample Recording</CardTitle>
                <CardDescription>Record a sound sample to analyze its root key for automatic key mapping</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex items-center gap-4">
                  <Button onClick={isRecording ? stopRecording : startRecording} className={isRecording ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'} size="lg">
                    {isRecording ? <><Square className="w-5 h-5 mr-2" />Stop Recording</> : <><Mic className="w-5 h-5 mr-2" />Record Sample</>}
                  </Button>
                  {recordedBuffer && (
                    <>
                      <Button onClick={isPlaying ? stopPlayback : playSample} variant="outline" className="border-slate-600" size="lg">
                        {isPlaying ? <><Square className="w-5 h-5 mr-2" />Stop</> : <><Play className="w-5 h-5 mr-2" />Play Sample</>}
                      </Button>
                      <div className="text-sm text-slate-400">Duration: {(recordedBuffer.length / sampleRate).toFixed(2)}s</div>
                    </>
                  )}
                </div>
              </CardContent>
            </Card>

            {/* Detection Results */}
            {detectionResult && (
              <div className="space-y-4">
                <Card className="bg-slate-800/50 border-slate-700">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2"><KeyRound className="w-5 h-5 text-green-400" />Detected Root Key</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <MidiNoteDisplay midiNote={detectionResult.midiNote} noteName={detectionResult.noteName} frequency={detectionResult.frequency} />
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-4">
                      <div className="p-3 bg-slate-900/50 rounded-lg text-center">
                        <div className="text-xs text-slate-400 mb-1">Confidence</div>
                        <div className="flex items-center justify-center gap-2">
                          {detectionResult.confidence > 0.7 ? <CheckCircle2 className="w-4 h-4 text-green-400" /> : detectionResult.confidence > 0.4 ? <AlertCircle className="w-4 h-4 text-yellow-400" /> : <AlertCircle className="w-4 h-4 text-red-400" />}
                          <span className={`font-mono ${detectionResult.confidence > 0.7 ? 'text-green-400' : detectionResult.confidence > 0.4 ? 'text-yellow-400' : 'text-red-400'}`}>{(detectionResult.confidence * 100).toFixed(0)}%</span>
                        </div>
                      </div>
                      <div className="p-3 bg-slate-900/50 rounded-lg text-center">
                        <div className="text-xs text-slate-400 mb-1">Pitch Stability</div>
                        <div className="font-mono text-blue-400">{(detectionResult.pitchStability * 100).toFixed(0)}%</div>
                      </div>
                      <div className="p-3 bg-slate-900/50 rounded-lg text-center">
                        <div className="text-xs text-slate-400 mb-1">Algorithm</div>
                        <Badge variant="secondary">{detectionResult.algorithm}</Badge>
                      </div>
                      <div className="p-3 bg-slate-900/50 rounded-lg text-center">
                        <div className="text-xs text-slate-400 mb-1">Type</div>
                        <Badge variant={detectionResult.isPercussive ? 'destructive' : 'default'}>{detectionResult.isPercussive ? 'Percussive' : 'Tonal'}</Badge>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                {/* Key Mapping */}
                <Card className="bg-slate-800/50 border-slate-700">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2"><Piano className="w-5 h-5 text-blue-400" />Suggested Key Mapping</CardTitle>
                    <CardDescription>Sample will play across this key range, transposed from the root</CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <div className="grid grid-cols-3 gap-4 mb-4">
                      <div className="p-3 bg-slate-900/50 rounded-lg text-center">
                        <div className="text-xs text-slate-400 mb-1">Low Key</div>
                        <div className="font-mono text-lg">{midiToNoteName(detectionResult.suggestedMapping.lowNote)}<span className="text-slate-500 text-sm ml-1">({detectionResult.suggestedMapping.lowNote})</span></div>
                      </div>
                      <div className="p-3 bg-green-900/30 rounded-lg text-center border border-green-600">
                        <div className="text-xs text-green-400 mb-1">Root Key</div>
                        <div className="font-mono text-lg text-green-400">{detectionResult.noteName}<span className="text-green-500 text-sm ml-1">({detectionResult.midiNote})</span></div>
                      </div>
                      <div className="p-3 bg-slate-900/50 rounded-lg text-center">
                        <div className="text-xs text-slate-400 mb-1">High Key</div>
                        <div className="font-mono text-lg">{midiToNoteName(detectionResult.suggestedMapping.highNote)}<span className="text-slate-500 text-sm ml-1">({detectionResult.suggestedMapping.highNote})</span></div>
                      </div>
                    </div>
                    <PianoKeyboard rootKey={detectionResult.midiNote} lowKey={detectionResult.suggestedMapping.lowNote} highKey={detectionResult.suggestedMapping.highNote} numKeys={49} startKey={36} />
                  </CardContent>
                </Card>

                {/* Waveforms */}
                <div className="grid md:grid-cols-2 gap-4">
                  <Card className="bg-slate-800/50 border-slate-700">
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2 text-lg"><Activity className="w-5 h-5 text-blue-400" />Full Sample</CardTitle>
                      <CardDescription>Green region shows analyzed portion</CardDescription>
                    </CardHeader>
                    <CardContent><canvas ref={samplerCanvasRef} width={600} height={150} className="w-full h-36 rounded-lg" /></CardContent>
                  </Card>
                  <Card className="bg-slate-800/50 border-slate-700">
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2 text-lg"><Zap className="w-5 h-5 text-green-400" />Analysis Region</CardTitle>
                      <CardDescription>Detected pitch periods shown as red lines</CardDescription>
                    </CardHeader>
                    <CardContent><canvas ref={analysisCanvasRef} width={600} height={150} className="w-full h-36 rounded-lg" /></CardContent>
                  </Card>
                </div>
              </div>
            )}

            {/* Sampler Settings */}
            <Card className="bg-slate-800/50 border-slate-700">
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Gauge className="w-5 h-5 text-purple-400" />Sampler Detection Settings</CardTitle>
                <CardDescription>Fine-tune key detection for your samples</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="grid md:grid-cols-3 gap-6">
                  <div className="space-y-2">
                    <div className="flex justify-between"><Label>Skip Attack</Label><span className="text-sm text-slate-400">{skipAttack.toFixed(2)}s</span></div>
                    <Slider value={[skipAttack]} onValueChange={([v]) => setSkipAttack(v)} min={0} max={0.5} step={0.01} />
                    <p className="text-xs text-slate-500">Time to skip at sample start</p>
                  </div>
                  <div className="space-y-2">
                    <div className="flex justify-between"><Label>Analysis Duration</Label><span className="text-sm text-slate-400">{analysisDuration.toFixed(2)}s</span></div>
                    <Slider value={[analysisDuration]} onValueChange={([v]) => setAnalysisDuration(v)} min={0.1} max={1.0} step={0.05} />
                    <p className="text-xs text-slate-500">How much of sample to analyze</p>
                  </div>
                  <div className="space-y-2">
                    <div className="flex justify-between"><Label>Mapping Range</Label><span className="text-sm text-slate-400">±{mappingRange} semitones</span></div>
                    <Slider value={[mappingRange]} onValueChange={([v]) => setMappingRange(v)} min={1} max={24} step={1} />
                    <p className="text-xs text-slate-500">Key spread for mapping</p>
                  </div>
                </div>
                {recordedBuffer && <Button onClick={analyzeSample} className="w-full">Re-analyze Sample</Button>}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {/* ============================================== */}
        {/* RESEARCH & RESOURCES (Always visible) */}
        {/* ============================================== */}
        <Card className="bg-slate-800/50 border-slate-700">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">Research Papers &amp; Resources</CardTitle>
            <CardDescription>Key papers and resources for further learning</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid md:grid-cols-2 gap-4">
              <div className="p-4 bg-slate-900/50 rounded-lg space-y-2">
                <h4 className="font-medium text-blue-400">Classical Algorithms</h4>
                <ul className="text-sm space-y-2 text-slate-300">
                  <li>• Rabiner (1977) - &quot;On the Use of Autocorrelation Analysis for Pitch Detection&quot;</li>
                  <li>• de Cheveigné &amp; Kawahara (2002) - &quot;YIN, a fundamental frequency estimator for speech and music&quot;</li>
                  <li>• McLeod &amp; Wyvill (2005) - &quot;A smarter way to find pitch&quot;</li>
                  <li>• Talkin (1995) - &quot;A Robust Algorithm for Pitch Tracking (RAPT)&quot;</li>
                </ul>
              </div>
              <div className="p-4 bg-slate-900/50 rounded-lg space-y-2">
                <h4 className="font-medium text-purple-400">Modern Deep Learning</h4>
                <ul className="text-sm space-y-2 text-slate-300">
                  <li>• Kim et al. (2018) - &quot;CREPE: A Convolutional Representation for Pitch Estimation&quot;</li>
                  <li>• Stefani &amp; Turchet (2022) - &quot;PESTO: Real-Time Pitch Estimation with Self-Supervised Learning&quot;</li>
                  <li>• SwiftF0 (2025) - &quot;Fast and Accurate Monophonic Pitch Detection&quot;</li>
                  <li>• arXiv:2507.11233 - &quot;Improving Neural Pitch Estimation with SWIPE Kernels&quot;</li>
                </ul>
              </div>
              <div className="p-4 bg-slate-900/50 rounded-lg space-y-2">
                <h4 className="font-medium text-green-400">Industry Tools</h4>
                <ul className="text-sm space-y-2 text-slate-300">
                  <li>• <strong>Antares Auto-Tune</strong> - Industry standard pitch correction</li>
                  <li>• <strong>Celemony Melodyne</strong> - Professional pitch editing</li>
                  <li>• <strong>Librosa (pYIN)</strong> - Python library for audio analysis</li>
                  <li>• <strong>Aubio</strong> - C library for audio labeling</li>
                </ul>
              </div>
              <div className="p-4 bg-slate-900/50 rounded-lg space-y-2">
                <h4 className="font-medium text-yellow-400">VST Development</h4>
                <ul className="text-sm space-y-2 text-slate-300">
                  <li>• JUCE Framework - Cross-platform audio application framework</li>
                  <li>• Steinberg VST SDK - Official VST development kit</li>
                  <li>• iPlug2 - Modern C++ audio plug-in framework</li>
                  <li>• RTAudio/RTAudio - Cross-platform audio I/O</li>
                </ul>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Footer */}
        <footer className="text-center text-sm text-slate-500 py-4">
          <p>Built with Web Audio API for real-time pitch detection demonstration</p>
          <p className="mt-1">For best results, use a microphone in a quiet environment with clear sound sources</p>
        </footer>
      </div>
    </div>
  )
}
