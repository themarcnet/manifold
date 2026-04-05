#include "DSPHostInternal.h"

#include "dsp/core/nodes/PrimitiveNodes.h"

namespace dsp_host {

  std::shared_ptr<dsp_primitives::IPrimitiveNode> toPrimitiveNode(
      const sol::object &obj) {
    if (obj.is<std::shared_ptr<dsp_primitives::IPrimitiveNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::IPrimitiveNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::GainNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::GainNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RecordStateNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RecordStateNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::QuantizerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::QuantizerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::TransportStateNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::TransportStateNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::OscillatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::OscillatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::SineBankNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::SineBankNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ReverbNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ReverbNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::FilterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::FilterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::DistortionNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::DistortionNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::SVFNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::SVFNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::StereoDelayNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::StereoDelayNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::CompressorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::CompressorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::WaveShaperNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::WaveShaperNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ChorusNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ChorusNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::StereoWidenerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::StereoWidenerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PhaserNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PhaserNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::GranulatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::GranulatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PhaseVocoderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PhaseVocoderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::StutterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::StutterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ShimmerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ShimmerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MultitapDelayNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MultitapDelayNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PitchShifterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PitchShifterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::TransientShaperNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::TransientShaperNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RingModulatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RingModulatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::BitCrusherNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::BitCrusherNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::FormantFilterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::FormantFilterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ReverseDelayNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ReverseDelayNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PitchDetectorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PitchDetectorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::CrossfaderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::CrossfaderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MixerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MixerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MSEncoderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MSEncoderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MSDecoderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MSDecoderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MidiVoiceNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MidiVoiceNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MidiInputNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MidiInputNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::EQNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::EQNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::EQ8Node>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::EQ8Node>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::LimiterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::LimiterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>();
    }
    if (obj.is<sol::table>()) {
      sol::table table = obj.as<sol::table>();
      sol::object nodeObj = table["__outputNode"];
      if (!nodeObj.valid()) {
        nodeObj = table["__node"];
      }
      if (nodeObj.valid()) {
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::GainNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::GainNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RecordStateNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RecordStateNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::QuantizerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::QuantizerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::TransportStateNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::TransportStateNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::OscillatorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::OscillatorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::SineBankNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::SineBankNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ReverbNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ReverbNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::FilterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::FilterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::DistortionNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::DistortionNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::SVFNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::SVFNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::StereoDelayNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::StereoDelayNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::CompressorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::CompressorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::WaveShaperNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::WaveShaperNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ChorusNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ChorusNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::StereoWidenerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::StereoWidenerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PhaserNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PhaserNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::GranulatorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::GranulatorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PhaseVocoderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PhaseVocoderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::StutterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::StutterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ShimmerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ShimmerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MultitapDelayNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MultitapDelayNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PitchShifterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PitchShifterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::TransientShaperNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::TransientShaperNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RingModulatorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RingModulatorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::BitCrusherNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::BitCrusherNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::FormantFilterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::FormantFilterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ReverseDelayNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ReverseDelayNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PitchDetectorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PitchDetectorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::CrossfaderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::CrossfaderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MixerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MixerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MSEncoderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MSEncoderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MSDecoderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MSDecoderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MidiVoiceNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MidiVoiceNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MidiInputNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MidiInputNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::EQNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::EQNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::EQ8Node>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::EQ8Node>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::LimiterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::LimiterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>();
        }
      }
    }
    return nullptr;}


} // namespace dsp_host
