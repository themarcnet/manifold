#include "DSPHostInternal.h"

namespace dsp_host {

float clampParamValue(const DspParamSpec &spec, float value) {
  if (spec.rangeMax > spec.rangeMin) {
    return juce::jlimit(spec.rangeMin, spec.rangeMax, value);
  }
  return value;
}

juce::String sanitizePath(const std::string &path) {
  juce::String p(path);
  if (!p.startsWithChar('/')) {
    p = "/" + p;
  }
  return p;
}

bool isRegistryOwnedCategory(const juce::String &category) {
  return category == "backend" || category == "query";
}

} // namespace dsp_host
