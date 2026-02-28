#include "../primitives/control/CommandParser.h"
#include "../primitives/control/OSCEndpointRegistry.h"

#include <cmath>
#include <cstdio>

namespace {

bool near(float left, float right, float epsilon = 0.001f) {
  return std::abs(left - right) <= epsilon;
}

} // namespace

int main() {
  OSCEndpointRegistry endpointRegistry;
  endpointRegistry.setNumLayers(4);
  endpointRegistry.rebuild();

  int checks = 0;
  auto check = [&](bool ok, const char *message) -> bool {
    ++checks;
    if (!ok) {
      std::fprintf(stderr, "CanonicalCommandHarness: FAIL: %s\n", message);
      return false;
    }
    return true;
  };

  auto failCode = [&]() {
    return 100 + checks;
  };

  const auto setTempo = CommandParser::parse("SET /looper/tempo 132.5", &endpointRegistry);
  if (!check(setTempo.kind == ParseResult::Kind::Enqueue,
             "SET /looper/tempo parses as enqueue")) {
    return failCode();
  }
  if (!check(setTempo.command.operation == ControlOperation::Set,
             "SET /looper/tempo operation is Set")) {
    return failCode();
  }
  if (!check(setTempo.command.type == ControlCommand::Type::SetTempo,
             "SET /looper/tempo maps to SetTempo")) {
    return failCode();
  }
  if (!check(setTempo.command.value.kind == ControlValueKind::Float &&
                 near(setTempo.command.value.floatValue, 132.5f) &&
                 near(setTempo.command.floatParam, 132.5f),
             "SET /looper/tempo payload carries float value")) {
    return failCode();
  }

  const auto setLayerSpeed =
      CommandParser::parse("SET /looper/layer/2/speed 0.75", &endpointRegistry);
  if (!check(setLayerSpeed.kind == ParseResult::Kind::Enqueue,
             "SET layer speed parses as enqueue")) {
    return failCode();
  }
  if (!check(setLayerSpeed.command.type == ControlCommand::Type::LayerSpeed &&
                 setLayerSpeed.command.intParam == 2 &&
                 near(setLayerSpeed.command.floatParam, 0.75f),
             "SET layer speed maps layer index and value")) {
    return failCode();
  }

  const auto setMode =
      CommandParser::parse("SET /looper/mode freeMode", &endpointRegistry);
  if (!check(setMode.kind == ParseResult::Kind::Enqueue,
             "SET /looper/mode parses as enqueue")) {
    return failCode();
  }
  if (!check(setMode.command.type == ControlCommand::Type::SetRecordMode &&
                 setMode.command.value.kind == ControlValueKind::Int &&
                 setMode.command.intParam == 1,
             "SET /looper/mode maps to record mode index")) {
    return failCode();
  }

  const auto setOverdub =
      CommandParser::parse("SET /looper/overdub 1", &endpointRegistry);
  if (!check(setOverdub.kind == ParseResult::Kind::Enqueue,
             "SET /looper/overdub parses as enqueue")) {
    return failCode();
  }
  if (!check(setOverdub.command.type == ControlCommand::Type::SetOverdubEnabled &&
                 near(setOverdub.command.floatParam, 1.0f),
             "SET /looper/overdub maps to SetOverdubEnabled")) {
    return failCode();
  }

  const auto triggerRec =
      CommandParser::parse("TRIGGER /looper/rec", &endpointRegistry);
  if (!check(triggerRec.kind == ParseResult::Kind::Enqueue,
             "TRIGGER /looper/rec parses as enqueue")) {
    return failCode();
  }
  if (!check(triggerRec.command.operation == ControlOperation::Trigger &&
                 triggerRec.command.type == ControlCommand::Type::StartRecording &&
                 triggerRec.command.value.kind == ControlValueKind::Trigger,
             "TRIGGER /looper/rec maps trigger payload")) {
    return failCode();
  }

  const auto getTempo =
      CommandParser::parse("GET /looper/tempo", &endpointRegistry);
  if (!check(getTempo.kind == ParseResult::Kind::Query &&
                 getTempo.queryType == "GET" &&
                 getTempo.queryPath == "/looper/tempo",
             "GET /looper/tempo parses as query")) {
    return failCode();
  }

  const auto getDiagnostics =
      CommandParser::parse("GET /looper/diagnostics", &endpointRegistry);
  if (!check(getDiagnostics.kind == ParseResult::Kind::Query &&
                 getDiagnostics.queryType == "GET" &&
                 getDiagnostics.queryPath == "/looper/diagnostics",
             "GET /looper/diagnostics parses as query")) {
    return failCode();
  }

  // Alias parity checks: /core/behavior/* and /dsp/looper/* must map to the
  // same command semantics as /looper/*.
  const auto setTempoCore =
      CommandParser::parse("SET /core/behavior/tempo 98.25", &endpointRegistry);
  const auto setTempoDsp =
      CommandParser::parse("SET /dsp/looper/tempo 98.25", &endpointRegistry);
  if (!check(setTempoCore.kind == ParseResult::Kind::Enqueue &&
                 setTempoDsp.kind == ParseResult::Kind::Enqueue,
             "SET tempo aliases parse as enqueue")) {
    return failCode();
  }
  if (!check(setTempoCore.command.type == ControlCommand::Type::SetTempo &&
                 setTempoDsp.command.type == ControlCommand::Type::SetTempo &&
                 near(setTempoCore.command.floatParam, 98.25f) &&
                 near(setTempoDsp.command.floatParam, 98.25f),
             "SET tempo aliases map to SetTempo with identical payload")) {
    return failCode();
  }

  const auto setLayerSpeedCore =
      CommandParser::parse("SET /core/behavior/layer/3/speed 0.5", &endpointRegistry);
  const auto setLayerSpeedDsp =
      CommandParser::parse("SET /dsp/looper/layer/3/speed 0.5", &endpointRegistry);
  if (!check(setLayerSpeedCore.kind == ParseResult::Kind::Enqueue &&
                 setLayerSpeedDsp.kind == ParseResult::Kind::Enqueue &&
                 setLayerSpeedCore.command.type == ControlCommand::Type::LayerSpeed &&
                 setLayerSpeedDsp.command.type == ControlCommand::Type::LayerSpeed &&
                 setLayerSpeedCore.command.intParam == 3 &&
                 setLayerSpeedDsp.command.intParam == 3 &&
                 near(setLayerSpeedCore.command.floatParam, 0.5f) &&
                 near(setLayerSpeedDsp.command.floatParam, 0.5f),
             "SET layer speed aliases map identically")) {
    return failCode();
  }

  const auto setModeCore =
      CommandParser::parse("SET /core/behavior/mode traditional", &endpointRegistry);
  const auto setModeDsp =
      CommandParser::parse("SET /dsp/looper/mode traditional", &endpointRegistry);
  if (!check(setModeCore.kind == ParseResult::Kind::Enqueue &&
                 setModeDsp.kind == ParseResult::Kind::Enqueue &&
                 setModeCore.command.type == ControlCommand::Type::SetRecordMode &&
                 setModeDsp.command.type == ControlCommand::Type::SetRecordMode &&
                 setModeCore.command.intParam == 2 &&
                 setModeDsp.command.intParam == 2,
             "SET mode aliases map identically")) {
    return failCode();
  }

  const auto triggerRecCore =
      CommandParser::parse("TRIGGER /core/behavior/rec", &endpointRegistry);
  const auto triggerRecDsp =
      CommandParser::parse("TRIGGER /dsp/looper/rec", &endpointRegistry);
  if (!check(triggerRecCore.kind == ParseResult::Kind::Enqueue &&
                 triggerRecDsp.kind == ParseResult::Kind::Enqueue &&
                 triggerRecCore.command.operation == ControlOperation::Trigger &&
                 triggerRecDsp.command.operation == ControlOperation::Trigger &&
                 triggerRecCore.command.type == ControlCommand::Type::StartRecording &&
                 triggerRecDsp.command.type == ControlCommand::Type::StartRecording,
             "TRIGGER rec aliases map to StartRecording")) {
    return failCode();
  }

  const auto triggerStopRecCore =
      CommandParser::parse("TRIGGER /core/behavior/stoprec", &endpointRegistry);
  const auto triggerStopRecDsp =
      CommandParser::parse("TRIGGER /dsp/looper/stoprec", &endpointRegistry);
  if (!check(triggerStopRecCore.kind == ParseResult::Kind::Enqueue &&
                 triggerStopRecDsp.kind == ParseResult::Kind::Enqueue &&
                 triggerStopRecCore.command.type == ControlCommand::Type::StopRecording &&
                 triggerStopRecDsp.command.type == ControlCommand::Type::StopRecording,
             "TRIGGER stoprec aliases map to StopRecording")) {
    return failCode();
  }

  const auto getTempoCore =
      CommandParser::parse("GET /core/behavior/tempo", &endpointRegistry);
  const auto getTempoDsp =
      CommandParser::parse("GET /dsp/looper/tempo", &endpointRegistry);
  if (!check(getTempoCore.kind == ParseResult::Kind::Query &&
                 getTempoDsp.kind == ParseResult::Kind::Query &&
                 getTempoCore.queryPath == "/core/behavior/tempo" &&
                 getTempoDsp.queryPath == "/dsp/looper/tempo",
             "GET aliases remain query operations with preserved paths")) {
    return failCode();
  }

  const auto unknownCore =
      CommandParser::parse("SET /core/behavior/nope 1", &endpointRegistry);
  if (!check(unknownCore.kind == ParseResult::Kind::Error,
             "unknown canonical path returns parse error")) {
    return failCode();
  }

  const auto unknownPath =
      CommandParser::parse("SET /looper/nope 1", &endpointRegistry);
  if (!check(unknownPath.kind == ParseResult::Kind::Error,
             "unknown path returns parse error")) {
    return failCode();
  }

  const auto badType =
      CommandParser::parse("SET /looper/tempo nope", &endpointRegistry);
  if (!check(badType.kind == ParseResult::Kind::NoOpWarning,
             "impossible coercion returns no-op warning")) {
    return failCode();
  }
  if (!check(badType.warningCode == "W_COERCE_IMPOSSIBLE_NOOP",
             "impossible coercion warning code")) {
    return failCode();
  }

  const auto lossyInt =
      CommandParser::parse("SET /looper/layer 2.8", &endpointRegistry);
  if (!check(lossyInt.kind == ParseResult::Kind::Enqueue,
             "lossy coercion still enqueues")) {
    return failCode();
  }
  if (!check(lossyInt.warningCode == "W_COERCE_LOSSY" &&
                 lossyInt.command.intParam == 2,
             "lossy coercion warning code")) {
    return failCode();
  }

  const auto legacyTempo =
      CommandParser::parse("TEMPO 127", &endpointRegistry);
  if (!check(legacyTempo.kind == ParseResult::Kind::Error,
             "legacy TEMPO now rejected")) {
    return failCode();
  }
  if (!check(legacyTempo.usedLegacySyntax &&
                 legacyTempo.errorCode == "W_PATH_DEPRECATED",
             "legacy TEMPO returns deprecation error code")) {
    return failCode();
  }

  const auto legacyLayerReverse =
      CommandParser::parse("LAYER 2 REVERSE 1", &endpointRegistry);
  if (!check(legacyLayerReverse.kind == ParseResult::Kind::Error,
             "legacy layer reverse now rejected")) {
    return failCode();
  }
  if (!check(legacyLayerReverse.usedLegacySyntax &&
                 legacyLayerReverse.errorCode == "W_PATH_DEPRECATED",
             "legacy layer reverse returns deprecation error code")) {
    return failCode();
  }

  const auto legacyStop = CommandParser::parse("STOP", &endpointRegistry);
  if (!check(legacyStop.kind == ParseResult::Kind::Error,
             "legacy STOP now rejected")) {
    return failCode();
  }
  if (!check(legacyStop.usedLegacySyntax &&
                 legacyStop.errorCode == "W_PATH_DEPRECATED",
             "legacy STOP returns deprecation error code")) {
    return failCode();
  }

  const auto diagnostics = CommandParser::getDiagnosticsSnapshot();
  if (!check(diagnostics.legacySyntaxTotal >= 3,
             "legacy syntax total counter increments")) {
    return failCode();
  }
  if (!check(diagnostics.legacyVerbTempo >= 1 &&
                 diagnostics.legacyVerbLayer >= 1 &&
                 diagnostics.legacyVerbStop >= 1,
             "legacy per-verb counters increment")) {
    return failCode();
  }

  std::fprintf(stdout, "CanonicalCommandHarness: PASS (%d checks)\n", checks);
  return 0;
}
