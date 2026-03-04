#pragma once

#include "ControlServer.h" // for ControlCommand
#include "EndpointResolver.h"
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <string>
#include <vector>

// ============================================================================
// CommandParser - shared text-protocol parser used by both ControlServer (IPC)
// and LuaEngine (UI). One source of truth for command string → ControlCommand.
// ============================================================================

struct ParseResult {
  enum class Kind {
    Enqueue,         // a ControlCommand that should be enqueued to audio thread
    Query,           // a read-only query (STATE, PING, DIAGNOSE, etc.)
    Watch,           // enter watch mode (IPC only)
    Inject,          // INJECT <filepath> - handled by server thread
    InjectionStatus, // INJECTION_STATUS query
    UISwitch,        // UISWITCH <filepath> - switch UI script
    NoOpWarning,     // accepted no-op with warning (e.g. impossible coercion)
    Error            // parse error
  };

  Kind kind = Kind::Error;
  ControlCommand command;   // valid when kind == Enqueue
  std::string queryType;    // "STATE", "PING", "DIAGNOSE" when kind == Query
  std::string queryPath;    // endpoint path when kind == Query and queryType == "GET"
  std::string filepath;     // valid when kind == Inject
  std::string errorMessage; // valid when kind == Error
  bool usedLegacySyntax = false;
  std::string legacyVerb;
  std::string warningCode;
  std::string warningMessage;
  std::string errorCode;
};

struct CommandDiagnosticsSnapshot {
  int warningsTotal = 0;
  int errorsTotal = 0;
  int warningPathUnknown = 0;
  int warningPathDeprecated = 0;
  int warningAccessDenied = 0;
  int warningRangeClamped = 0;
  int warningCoerceLossy = 0;
  int warningCoerceImpossibleNoop = 0;
  int legacySyntaxTotal = 0;
  int legacyVerbCommit = 0;
  int legacyVerbForward = 0;
  int legacyVerbTempo = 0;
  int legacyVerbRec = 0;
  int legacyVerbOverdub = 0;
  int legacyVerbStop = 0;
  int legacyVerbPlay = 0;
  int legacyVerbPause = 0;
  int legacyVerbStopRec = 0;
  int legacyVerbClear = 0;
  int legacyVerbClearAll = 0;
  int legacyVerbMode = 0;
  int legacyVerbVolume = 0;
  int legacyVerbTargetBpm = 0;
  int legacyVerbLayer = 0;
};

namespace CommandParser {

namespace detail {

struct DiagnosticsCounters {
  std::atomic<int> warningsTotal{0};
  std::atomic<int> errorsTotal{0};
  std::atomic<int> warningPathUnknown{0};
  std::atomic<int> warningPathDeprecated{0};
  std::atomic<int> warningAccessDenied{0};
  std::atomic<int> warningRangeClamped{0};
  std::atomic<int> warningCoerceLossy{0};
  std::atomic<int> warningCoerceImpossibleNoop{0};
  std::atomic<int> legacySyntaxTotal{0};
  std::atomic<int> legacyVerbCommit{0};
  std::atomic<int> legacyVerbForward{0};
  std::atomic<int> legacyVerbTempo{0};
  std::atomic<int> legacyVerbRec{0};
  std::atomic<int> legacyVerbOverdub{0};
  std::atomic<int> legacyVerbStop{0};
  std::atomic<int> legacyVerbPlay{0};
  std::atomic<int> legacyVerbPause{0};
  std::atomic<int> legacyVerbStopRec{0};
  std::atomic<int> legacyVerbClear{0};
  std::atomic<int> legacyVerbClearAll{0};
  std::atomic<int> legacyVerbMode{0};
  std::atomic<int> legacyVerbVolume{0};
  std::atomic<int> legacyVerbTargetBpm{0};
  std::atomic<int> legacyVerbLayer{0};
};

inline DiagnosticsCounters &diagnosticsCounters() {
  static DiagnosticsCounters counters;
  return counters;
}

} // namespace detail

inline void recordWarningCode(const std::string &warningCode) {
  auto &counters = detail::diagnosticsCounters();
  counters.warningsTotal.fetch_add(1, std::memory_order_relaxed);

  if (warningCode == "W_PATH_UNKNOWN") {
    counters.warningPathUnknown.fetch_add(1, std::memory_order_relaxed);
  } else if (warningCode == "W_PATH_DEPRECATED") {
    counters.warningPathDeprecated.fetch_add(1, std::memory_order_relaxed);
  } else if (warningCode == "W_ACCESS_DENIED") {
    counters.warningAccessDenied.fetch_add(1, std::memory_order_relaxed);
  } else if (warningCode == "W_RANGE_CLAMPED") {
    counters.warningRangeClamped.fetch_add(1, std::memory_order_relaxed);
  } else if (warningCode == "W_COERCE_LOSSY") {
    counters.warningCoerceLossy.fetch_add(1, std::memory_order_relaxed);
  } else if (warningCode == "W_COERCE_IMPOSSIBLE_NOOP") {
    counters.warningCoerceImpossibleNoop.fetch_add(1,
                                                   std::memory_order_relaxed);
  }
}

inline void recordErrorEvent() {
  detail::diagnosticsCounters().errorsTotal.fetch_add(1,
                                                      std::memory_order_relaxed);
}

inline void recordLegacyVerb(const std::string &legacyVerb) {
  auto &counters = detail::diagnosticsCounters();
  counters.legacySyntaxTotal.fetch_add(1, std::memory_order_relaxed);

  if (legacyVerb == "COMMIT") {
    counters.legacyVerbCommit.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "FORWARD") {
    counters.legacyVerbForward.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "TEMPO") {
    counters.legacyVerbTempo.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "REC") {
    counters.legacyVerbRec.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "OVERDUB") {
    counters.legacyVerbOverdub.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "STOP") {
    counters.legacyVerbStop.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "PLAY") {
    counters.legacyVerbPlay.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "PAUSE") {
    counters.legacyVerbPause.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "STOPREC") {
    counters.legacyVerbStopRec.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "CLEAR") {
    counters.legacyVerbClear.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "CLEARALL") {
    counters.legacyVerbClearAll.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "MODE") {
    counters.legacyVerbMode.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "VOLUME" || legacyVerb == "MASTERVOLUME") {
    counters.legacyVerbVolume.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "TARGETBPM") {
    counters.legacyVerbTargetBpm.fetch_add(1, std::memory_order_relaxed);
  } else if (legacyVerb == "LAYER") {
    counters.legacyVerbLayer.fetch_add(1, std::memory_order_relaxed);
  }
}

inline CommandDiagnosticsSnapshot getDiagnosticsSnapshot() {
  CommandDiagnosticsSnapshot snapshot;
  auto &counters = detail::diagnosticsCounters();
  snapshot.warningsTotal = counters.warningsTotal.load(std::memory_order_relaxed);
  snapshot.errorsTotal = counters.errorsTotal.load(std::memory_order_relaxed);
  snapshot.warningPathUnknown =
      counters.warningPathUnknown.load(std::memory_order_relaxed);
  snapshot.warningPathDeprecated =
      counters.warningPathDeprecated.load(std::memory_order_relaxed);
  snapshot.warningAccessDenied =
      counters.warningAccessDenied.load(std::memory_order_relaxed);
  snapshot.warningRangeClamped =
      counters.warningRangeClamped.load(std::memory_order_relaxed);
  snapshot.warningCoerceLossy =
      counters.warningCoerceLossy.load(std::memory_order_relaxed);
  snapshot.warningCoerceImpossibleNoop =
      counters.warningCoerceImpossibleNoop.load(std::memory_order_relaxed);
  snapshot.legacySyntaxTotal =
      counters.legacySyntaxTotal.load(std::memory_order_relaxed);
  snapshot.legacyVerbCommit =
      counters.legacyVerbCommit.load(std::memory_order_relaxed);
  snapshot.legacyVerbForward =
      counters.legacyVerbForward.load(std::memory_order_relaxed);
  snapshot.legacyVerbTempo =
      counters.legacyVerbTempo.load(std::memory_order_relaxed);
  snapshot.legacyVerbRec = counters.legacyVerbRec.load(std::memory_order_relaxed);
  snapshot.legacyVerbOverdub =
      counters.legacyVerbOverdub.load(std::memory_order_relaxed);
  snapshot.legacyVerbStop =
      counters.legacyVerbStop.load(std::memory_order_relaxed);
  snapshot.legacyVerbPlay =
      counters.legacyVerbPlay.load(std::memory_order_relaxed);
  snapshot.legacyVerbPause =
      counters.legacyVerbPause.load(std::memory_order_relaxed);
  snapshot.legacyVerbStopRec =
      counters.legacyVerbStopRec.load(std::memory_order_relaxed);
  snapshot.legacyVerbClear =
      counters.legacyVerbClear.load(std::memory_order_relaxed);
  snapshot.legacyVerbClearAll =
      counters.legacyVerbClearAll.load(std::memory_order_relaxed);
  snapshot.legacyVerbMode = counters.legacyVerbMode.load(std::memory_order_relaxed);
  snapshot.legacyVerbVolume =
      counters.legacyVerbVolume.load(std::memory_order_relaxed);
  snapshot.legacyVerbTargetBpm =
      counters.legacyVerbTargetBpm.load(std::memory_order_relaxed);
  snapshot.legacyVerbLayer =
      counters.legacyVerbLayer.load(std::memory_order_relaxed);
  return snapshot;
}

inline std::string toUpper(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), ::toupper);
  return s;
}

inline int recordModeFromString(const std::string &s) {
  auto upper = toUpper(s);
  if (upper == "FIRSTLOOP" || upper == "FIRST" || upper == "0")
    return 0;
  if (upper == "FREEMODE" || upper == "FREE" || upper == "1")
    return 1;
  if (upper == "TRADITIONAL" || upper == "TRAD" || upper == "2")
    return 2;
  if (upper == "RETROSPECTIVE" || upper == "RETRO" || upper == "3")
    return 3;
  return -1;
}

inline bool parseBoolToken(const std::string &token, bool &out) {
  const auto upper = toUpper(token);
  if (upper == "1" || upper == "TRUE" || upper == "ON") {
    out = true;
    return true;
  }
  if (upper == "0" || upper == "FALSE" || upper == "OFF") {
    out = false;
    return true;
  }
  return false;
}

inline bool parseIntToken(const std::string &token, int &out) {
  if (token.empty()) {
    return false;
  }

  char *end = nullptr;
  const long parsed = std::strtol(token.c_str(), &end, 10);
  if (end == token.c_str() || *end != '\0') {
    return false;
  }

  out = static_cast<int>(parsed);
  return true;
}

inline bool parseFloatToken(const std::string &token, float &out) {
  if (token.empty()) {
    return false;
  }

  char *end = nullptr;
  const float parsed = std::strtof(token.c_str(), &end);
  if (end == token.c_str() || *end != '\0') {
    return false;
  }

  out = parsed;
  return true;
}

inline juce::var parseCanonicalValueToken(const std::string &token) {
  bool boolValue = false;
  if (parseBoolToken(token, boolValue)) {
    return juce::var(boolValue);
  }

  int intValue = 0;
  if (parseIntToken(token, intValue)) {
    return juce::var(intValue);
  }

  float floatValue = 0.0f;
  if (parseFloatToken(token, floatValue)) {
    return juce::var(floatValue);
  }

  return juce::var(juce::String(token));
}

inline bool isLayerAddressedCommand(ControlCommand::Type type) {
  return type == ControlCommand::Type::LayerMute ||
         type == ControlCommand::Type::LayerSpeed ||
         type == ControlCommand::Type::LayerReverse ||
         type == ControlCommand::Type::LayerVolume ||
         type == ControlCommand::Type::LayerStop ||
         type == ControlCommand::Type::LayerPlay ||
         type == ControlCommand::Type::LayerPause ||
         type == ControlCommand::Type::LayerClear ||
         type == ControlCommand::Type::LayerSeek;
}

inline void seedLegacyFieldsFromResolved(ControlCommand &command,
                                         const ResolvedEndpoint &endpoint) {
  if (endpoint.layerIndex >= 0 && isLayerAddressedCommand(command.type)) {
    command.intParam = endpoint.layerIndex;
  }
}

inline ParseResult makeCanonicalCommand(const ResolvedEndpoint &endpoint,
                                        ControlOperation operation,
                                        ControlCommand::Type commandType) {
  ParseResult result;
  result.kind = ParseResult::Kind::Enqueue;
  result.command.operation = operation;
  result.command.endpointId = endpoint.runtimeId;
  result.command.type = commandType;
  seedLegacyFieldsFromResolved(result.command, endpoint);
  return result;
}

inline ParseResult makeParserError(const std::string &message,
                                   const std::string &errorCode = {}) {
  recordErrorEvent();

  if (!errorCode.empty() && errorCode.rfind("W_", 0) == 0) {
    recordWarningCode(errorCode);
  }

  ParseResult result;
  result.kind = ParseResult::Kind::Error;
  result.errorMessage = message;
  result.errorCode = errorCode;
  return result;
}

inline ParseResult makeNoOpWarning(const std::string &warningCode,
                                   const std::string &warningMessage) {
  recordWarningCode(warningCode);

  ParseResult result;
  result.kind = ParseResult::Kind::NoOpWarning;
  result.warningCode = warningCode;
  result.warningMessage = warningMessage;
  return result;
}

inline void attachCoercionWarning(ParseResult &result,
                                  const juce::String &path,
                                  const ResolverValidationResult &validation) {
  if (!validation.accepted) {
    return;
  }

  if (validation.clamped) {
    result.warningCode = "W_RANGE_CLAMPED";
    result.warningMessage = "value clamped for path: " + path.toStdString();
    recordWarningCode(result.warningCode);
    return;
  }

  if (validation.coercionCategory == ResolverCoercionCategory::Lossy) {
    result.warningCode = "W_COERCE_LOSSY";
    result.warningMessage = "lossy coercion for path: " + path.toStdString();
    recordWarningCode(result.warningCode);
  }
}

inline bool isDeprecatedLegacyVerb(const std::string &verb) {
  return verb == "COMMIT" || verb == "FORWARD" || verb == "TEMPO" ||
         verb == "REC" || verb == "OVERDUB" || verb == "STOP" ||
         verb == "PLAY" || verb == "PAUSE" || verb == "STOPREC" ||
         verb == "CLEAR" || verb == "CLEARALL" || verb == "MODE" ||
         verb == "VOLUME" || verb == "MASTERVOLUME" ||
         verb == "TARGETBPM" || verb == "LAYER";
}

inline ParseResult makeLegacyRemovedError(const std::string &verb) {
  recordLegacyVerb(verb);

  ParseResult result =
      makeParserError("legacy command removed: " + verb +
                          ". Use SET/GET/TRIGGER /path syntax.",
                      "W_PATH_DEPRECATED");
  result.usedLegacySyntax = true;
  result.legacyVerb = verb;
  return result;
}

inline ParseResult buildResolverSetCommand(OSCEndpointRegistry *endpointRegistry,
                                           const juce::String &path,
                                           const juce::var &input) {
  if (endpointRegistry == nullptr) {
    return makeParserError("canonical path commands unavailable",
                           "E_CANONICAL_UNAVAILABLE");
  }

  EndpointResolver resolver(endpointRegistry);
  ResolvedEndpoint endpoint;
  if (!resolver.resolve(path, endpoint)) {
    return makeParserError("unknown path: " + path.toStdString(),
                           "W_PATH_UNKNOWN");
  }

  const auto validation = resolver.validateWrite(endpoint, input);
  if (!validation.accepted) {
    if (validation.code == ResolverValidationCode::AccessDenied) {
      return makeParserError("path is not writable: " + path.toStdString(),
                             "W_ACCESS_DENIED");
    }
    if (validation.coercionCategory == ResolverCoercionCategory::Impossible) {
      return makeNoOpWarning("W_COERCE_IMPOSSIBLE_NOOP",
                             "impossible coercion for path: " +
                                 path.toStdString());
    }
    return makeParserError("invalid value for path: " + path.toStdString(),
                           "E_INVALID_VALUE");
  }

  ControlCommand::Type commandType = endpoint.commandType;
  if (commandType == ControlCommand::Type::None) {
    return makeParserError("path is not writable command endpoint: " +
                           path.toStdString(),
                           "W_ACCESS_DENIED");
  }

  if (commandType == ControlCommand::Type::ToggleOverdub) {
    commandType = ControlCommand::Type::SetOverdubEnabled;
  }

  ParseResult result =
      makeCanonicalCommand(endpoint, ControlOperation::Set, commandType);
  attachCoercionWarning(result, path, validation);

  if (commandType == ControlCommand::Type::SetRecordMode) {
    const int mode = recordModeFromString(input.toString().toStdString());
    if (mode < 0) {
      return makeNoOpWarning(
          "W_COERCE_IMPOSSIBLE_NOOP",
          "impossible coercion for path: " + path.toStdString());
    }

    result.command.value.kind = ControlValueKind::Int;
    result.command.value.intValue = mode;
    result.command.intParam = mode;
    result.command.floatParam = static_cast<float>(mode);
    return result;
  }

  switch (endpoint.valueType) {
  case ResolverValueType::Float: {
    const float value = static_cast<float>(validation.normalizedValue);
    result.command.value.kind = ControlValueKind::Float;
    result.command.value.floatValue = value;
    result.command.floatParam = value;
    break;
  }

  case ResolverValueType::Int: {
    const int value = static_cast<int>(validation.normalizedValue);
    result.command.value.kind = ControlValueKind::Int;
    result.command.value.intValue = value;
    result.command.floatParam = static_cast<float>(value);

    if (commandType == ControlCommand::Type::SetActiveLayer) {
      result.command.intParam = value;
    }
    break;
  }

  case ResolverValueType::Bool: {
    const bool value = static_cast<int>(validation.normalizedValue) != 0;
    result.command.value.kind = ControlValueKind::Bool;
    result.command.value.boolValue = value;
    result.command.floatParam = value ? 1.0f : 0.0f;

    if (!isLayerAddressedCommand(commandType)) {
      result.command.intParam = value ? 1 : 0;
    }
    break;
  }

  case ResolverValueType::String:
  case ResolverValueType::Trigger:
  case ResolverValueType::Unknown:
    return makeParserError("unsupported value type for path: " +
                           path.toStdString(),
                           "E_UNSUPPORTED_VALUE_TYPE");
  }

  return result;
}

inline ParseResult
buildResolverTriggerCommand(OSCEndpointRegistry *endpointRegistry,
                            const juce::String &path,
                            bool allowToggleOverdubTrigger = false) {
  if (endpointRegistry == nullptr) {
    return makeParserError("canonical path commands unavailable",
                           "E_CANONICAL_UNAVAILABLE");
  }

  EndpointResolver resolver(endpointRegistry);
  ResolvedEndpoint endpoint;
  if (!resolver.resolve(path, endpoint)) {
    return makeParserError("unknown path: " + path.toStdString(),
                           "W_PATH_UNKNOWN");
  }

  if (endpoint.commandType == ControlCommand::Type::None) {
    return makeParserError("path is not triggerable: " + path.toStdString(),
                           "W_ACCESS_DENIED");
  }

  ParseResult result;
  if (allowToggleOverdubTrigger &&
      endpoint.commandType == ControlCommand::Type::ToggleOverdub) {
    result = makeCanonicalCommand(endpoint, ControlOperation::Trigger,
                                  ControlCommand::Type::ToggleOverdub);
  } else {
    const auto validation = resolver.validateWrite(endpoint, juce::var());
    if (!validation.accepted) {
      return makeParserError("path does not accept trigger: " +
                                 path.toStdString(),
                             validation.code == ResolverValidationCode::AccessDenied
                                 ? "W_ACCESS_DENIED"
                                 : "E_TRIGGER_REJECTED");
    }

    result = makeCanonicalCommand(endpoint, ControlOperation::Trigger,
                                  endpoint.commandType);
  }

  result.command.value.kind = ControlValueKind::Trigger;
  return result;
}

// Parse a single command line into a ParseResult.
// Pure function - no side effects, no mutex, no IO.
inline ParseResult parse(const std::string &cmd,
                         OSCEndpointRegistry *endpointRegistry = nullptr) {
  std::istringstream iss(cmd);
  std::vector<std::string> tokens;
  std::string tok;
  while (iss >> tok)
    tokens.push_back(tok);

  if (tokens.empty())
    return makeParserError("empty command", "E_EMPTY_COMMAND");

  auto verb = toUpper(tokens[0]);

  auto makeQuery = [](const std::string &qt) -> ParseResult {
    ParseResult r;
    r.kind = ParseResult::Kind::Query;
    r.queryType = qt;
    return r;
  };

  auto makeError = [](const std::string &msg,
                      const std::string &code = {}) -> ParseResult {
    return makeParserError(msg, code);
  };

  // ---- Queries (no side effects) ----
  if (verb == "STATE")
    return makeQuery("STATE");
  if (verb == "PING")
    return makeQuery("PING");
  if (verb == "DIAGNOSE")
    return makeQuery("DIAGNOSE");
  if (verb == "DIAGNOSTICS")
    return makeQuery("DIAGNOSTICS");
  if (verb == "WATCH")
  {
    ParseResult result;
    result.kind = ParseResult::Kind::Watch;
    return result;
  }

  // ---- Canonical path operations: SET/GET/TRIGGER ----
  if (verb == "SET" || verb == "GET" || verb == "TRIGGER") {
    if (endpointRegistry == nullptr) {
      return makeError("canonical path commands unavailable",
                       "E_CANONICAL_UNAVAILABLE");
    }

    if (tokens.size() < 2) {
      return makeError("usage: " + verb + " /path [value]");
    }

    const juce::String path(tokens[1]);
    EndpointResolver resolver(endpointRegistry);
    ResolvedEndpoint endpoint;
    if (!resolver.resolve(path, endpoint)) {
      return makeError("unknown path: " + tokens[1], "W_PATH_UNKNOWN");
    }

    if (verb == "GET") {
      const auto readValidation = resolver.validateRead(endpoint);
      if (!readValidation.accepted) {
        return makeError("path not readable: " + tokens[1],
                         readValidation.code == ResolverValidationCode::AccessDenied
                             ? "W_ACCESS_DENIED"
                             : "E_QUERY_READ_REJECTED");
      }

      ParseResult query = makeQuery("GET");
      query.queryPath = endpoint.path.toStdString();
      return query;
    }

    if (verb == "TRIGGER") {
      if (tokens.size() != 2) {
        return makeError("usage: TRIGGER /path");
      }

      return buildResolverTriggerCommand(endpointRegistry, path,
                                         true /* allow toggle overdub */);
    }

    if (tokens.size() < 3) {
      return makeError("usage: SET /path <value>");
    }

    std::string rawValue = tokens[2];
    for (size_t index = 3; index < tokens.size(); ++index) {
      rawValue += " ";
      rawValue += tokens[index];
    }

    const ParseResult result =
        buildResolverSetCommand(endpointRegistry, path,
                                parseCanonicalValueToken(rawValue));
    if (result.kind == ParseResult::Kind::Error) {
      return makeError(result.errorMessage,
                       result.errorCode.empty() ? "E_SET_REJECTED"
                                                : result.errorCode);
    }
    return result;
  }

  if (isDeprecatedLegacyVerb(verb)) {
    return makeLegacyRemovedError(verb);
  }

  // ---- INJECT <filepath> ----
  if (verb == "INJECT") {
    if (tokens.size() < 2)
      return makeError("usage: INJECT <filepath>");
    std::string filepath;
    for (size_t i = 1; i < tokens.size(); ++i) {
      if (i > 1)
        filepath += " ";
      filepath += tokens[i];
    }
    ParseResult r;
    r.kind = ParseResult::Kind::Inject;
    r.filepath = filepath;
    return r;
  }

  // ---- INJECTION_STATUS ----
  if (verb == "INJECTION_STATUS") {
    ParseResult result;
    result.kind = ParseResult::Kind::InjectionStatus;
    return result;
  }

  // ---- UISWITCH <filepath> ----
  if (verb == "UISWITCH") {
    if (tokens.size() < 2)
      return makeError("usage: UISWITCH <filepath>");
    std::string filepath;
    for (size_t i = 1; i < tokens.size(); ++i) {
      if (i > 1)
        filepath += " ";
      filepath += tokens[i];
    }
    // Return a special result that the ControlServer will handle
    ParseResult r;
    r.kind = ParseResult::Kind::UISwitch;
    r.filepath = filepath; // reuse filepath field for UI path
    return r;
  }

  return makeError("unknown command: " + tokens[0]);
}

} // namespace CommandParser
