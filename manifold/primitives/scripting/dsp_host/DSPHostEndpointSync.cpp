#include "DSPHostInternal.h"

#include "../../control/OSCQuery.h"
#include "../../control/OSCServer.h"
#include "../../control/OSCEndpointRegistry.h"
#include "../ScriptableProcessor.h"

#include <map>

namespace dsp_host {

void syncEndpoints(LoadSession& session,
                   ScriptableProcessor* processor,
                   std::vector<juce::String>& registeredEndpoints,
                   const std::map<std::string, DspParamSpec>& orderedSpecs) {
  // Unregister old custom endpoints
  for (const auto& path : registeredEndpoints) {
    processor->getEndpointRegistry().unregisterCustomEndpoint(path);
    processor->getOSCServer().removeCustomValue(path);
  }
  registeredEndpoints.clear();

  // Register new endpoints from paramSpecs
  for (const auto& entry : orderedSpecs) {
    const auto& path = entry.first;
    const auto& spec = entry.second;

    OSCEndpoint endpoint;
    endpoint.path = juce::String(path);
    endpoint.type = spec.typeTag;
    endpoint.rangeMin = spec.rangeMin;
    endpoint.rangeMax = spec.rangeMax;
    endpoint.access = spec.access;
    endpoint.description = spec.description;
    endpoint.category = "dsp";
    endpoint.commandType = ControlCommand::Type::None;
    endpoint.layerIndex = -1;

    const OSCEndpoint existingEndpoint =
        processor->getEndpointRegistry().findEndpoint(endpoint.path);
    const bool backendOwned = existingEndpoint.path.isNotEmpty() &&
                              isRegistryOwnedCategory(existingEndpoint.category);

    // Register script parameters as custom OSCQuery endpoints unless a backend
    // endpoint already owns this exact path. This lets behavior scripts expose
    // newly added parameters without having to wait for static template updates.
    if (!backendOwned) {
      processor->getEndpointRegistry().registerCustomEndpoint(endpoint);
      registeredEndpoints.push_back(endpoint.path);

      const auto valIt = session.paramValues.find(path);
      if (valIt != session.paramValues.end()) {
        processor->getOSCServer().setCustomValue(
            endpoint.path, {juce::var(valIt->second)});
      }
    }
  }

  processor->getOSCQueryServer().rebuildTree();
}

} // namespace dsp_host
