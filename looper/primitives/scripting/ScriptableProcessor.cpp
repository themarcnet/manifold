#include "ScriptableProcessor.h"

#include <sol/sol.hpp>

// ============================================================================
// Default IStateSerializer implementation (minimal state)
//
// Subclasses like LooperProcessor override these with plugin-specific
// serialization. The default implementation provides a minimal state
// structure for processors that don't need complex state.
// ============================================================================

void ScriptableProcessor::serializeStateToLua(sol::state& lua) const {
  auto state = lua.create_table();
  
  // Minimal default state
  state["projectionVersion"] = 1;
  state["numVoices"] = 0;
  state["params"] = lua.create_table();
  state["voices"] = lua.create_table();
  
  // Empty link state
  auto linkState = lua.create_table();
  linkState["enabled"] = false;
  linkState["tempoSync"] = false;
  linkState["startStopSync"] = false;
  linkState["peers"] = 0;
  linkState["playing"] = false;
  linkState["beat"] = 0.0;
  linkState["phase"] = 0.0;
  state["link"] = linkState;
  
  // Empty spectrum
  state["spectrum"] = lua.create_table();
  
  lua["state"] = state;
}

std::string ScriptableProcessor::serializeStateToJson() const {
  // Minimal JSON representation
  return R"({"projectionVersion":1,"numVoices":0,"params":{},"voices":[],"link":{"enabled":false},"spectrum":[]})";
}

std::vector<IStateSerializer::StateField> ScriptableProcessor::getStateSchema() const {
  // Default: no state fields (subclasses add their own)
  return {};
}

std::string ScriptableProcessor::getValueAtPath(const std::string& /*path*/) const {
  // Default: no paths available
  return "";
}

bool ScriptableProcessor::hasPathChanged(const std::string& /*path*/) const {
  // Default: no change tracking
  return false;
}

void ScriptableProcessor::updateChangeCache() {
  // Default: no cache to update
}

void ScriptableProcessor::subscribeToPath(const std::string& /*path*/, StateChangeCallback /*callback*/) {
  // Default: no subscription support
}

void ScriptableProcessor::unsubscribeFromPath(const std::string& /*path*/) {
  // Default: no subscription support
}

void ScriptableProcessor::clearSubscriptions() {
  // Default: no subscriptions to clear
}

void ScriptableProcessor::processPendingChanges() {
  // Default: no pending changes to process
}
