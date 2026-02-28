#pragma once

namespace dsp_primitives {

class LoopBufferWrapper {
public:
  void setSize(int sizeSamples, int channels = 2);
  int getLength() const;
  int getChannels() const;
  void setCrossfade(float ms);
  float getCrossfade() const;

private:
  int length_ = 0;
  int channels_ = 2;
  float crossfadeMs_ = 0.0f;
};

class PlayheadWrapper {
public:
  void setLoopLength(int length);
  int getLoopLength() const;
  void setPosition(float normalized);
  float getPosition() const;
  void setSpeed(float speed);
  float getSpeed() const;
  void setReversed(bool reversed);
  bool isReversed() const;
  void play();
  void pause();
  void stop();

private:
  int loopLength_ = 0;
  int position_ = 0;
  float speed_ = 1.0f;
  bool reversed_ = false;
  bool playing_ = false;
};

class CaptureBufferWrapper {
public:
  void setSize(int sizeSamples, int channels = 2);
  int getSize() const;
  int getChannels() const;
  void setRecordEnabled(bool enabled);
  bool isRecordEnabled() const;
  void clear();

private:
  int size_ = 0;
  int channels_ = 2;
  bool recordEnabled_ = false;
};

class QuantizerWrapper {
public:
  void setSampleRate(double sampleRate);
  void setTempo(float bpm);
  float getTempo() const;
  int getQuantizedLength(int samples) const;
  float getQuantizedBars(int samples) const;

private:
  double sampleRate_ = 44100.0;
  float tempo_ = 120.0f;
};

} // namespace dsp_primitives
