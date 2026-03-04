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

  const auto setTempo =
      CommandParser::parse("SET /core/behavior/tempo 132.5", &endpointRegistry);
  if (!check(setTempo.kind == ParseResult::Kind::Enqueue,
             "SET /core/behavior/tempo parses as enqueue")) {
    return failCode();
  }
  if (!check(setTempo.command.operation == ControlOperation::Set,
             "SET /core/behavior/tempo operation is Set")) {
    return failCode();
  }
  if (!check(setTempo.command.type == ControlCommand::Type::SetTempo,
             "SET /core/behavior/tempo maps to SetTempo")) {
    return failCode();
  }
  if (!check(setTempo.command.value.kind == ControlValueKind::Float &&
                 near(setTempo.command.value.floatValue, 132.5f) &&
                 near(setTempo.command.floatParam, 132.5f),
             "SET /core/behavior/tempo payload carries float value")) {
    return failCode();
  }

  const auto setLayerSpeed =
      CommandParser::parse("SET /core/behavior/layer/2/speed 0.75", &endpointRegistry);
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
      CommandParser::parse("SET /core/behavior/mode freeMode", &endpointRegistry);
  if (!check(setMode.kind == ParseResult::Kind::Enqueue,
             "SET /core/behavior/mode parses as enqueue")) {
    return failCode();
  }
  if (!check(setMode.command.type == ControlCommand::Type::SetRecordMode &&
                 setMode.command.value.kind == ControlValueKind::Int &&
                 setMode.command.intParam == 1,
             "SET /core/behavior/mode maps to record mode index")) {
    return failCode();
  }

  const auto setOverdub =
      CommandParser::parse("SET /core/behavior/overdub 1", &endpointRegistry);
  if (!check(setOverdub.kind == ParseResult::Kind::Enqueue,
             "SET /core/behavior/overdub parses as enqueue")) {
    return failCode();
  }
  if (!check(setOverdub.command.type == ControlCommand::Type::SetOverdubEnabled &&
                 near(setOverdub.command.floatParam, 1.0f),
             "SET /core/behavior/overdub maps to SetOverdubEnabled")) {
    return failCode();
  }

  const auto triggerRec =
      CommandParser::parse("TRIGGER /core/behavior/rec", &endpointRegistry);
  if (!check(triggerRec.kind == ParseResult::Kind::Enqueue,
             "TRIGGER /core/behavior/rec parses as enqueue")) {
    return failCode();
  }
  if (!check(triggerRec.command.operation == ControlOperation::Trigger &&
                 triggerRec.command.type == ControlCommand::Type::StartRecording &&
                 triggerRec.command.value.kind == ControlValueKind::Trigger,
             "TRIGGER /core/behavior/rec maps trigger payload")) {
    return failCode();
  }

  const auto getTempo =
      CommandParser::parse("GET /core/behavior/tempo", &endpointRegistry);
  if (!check(getTempo.kind == ParseResult::Kind::Query &&
                 getTempo.queryType == "GET" &&
                 getTempo.queryPath == "/core/behavior/tempo",
             "GET /core/behavior/tempo parses as query")) {
    return failCode();
  }

  const auto getDiagnostics =
      CommandParser::parse("GET /core/behavior/diagnostics", &endpointRegistry);
  if (!check(getDiagnostics.kind == ParseResult::Kind::Query &&
                 getDiagnostics.queryType == "GET" &&
                 getDiagnostics.queryPath == "/core/behavior/diagnostics",
             "GET /core/behavior/diagnostics parses as query")) {
    return failCode();
  }

  const auto legacyLooperPath =
      CommandParser::parse("SET /looper/tempo 98.25", &endpointRegistry);
  if (!check(legacyLooperPath.kind == ParseResult::Kind::Error,
             "legacy /looper alias path rejected")) {
    return failCode();
  }

  const auto legacyDspPath =
      CommandParser::parse("SET /dsp/looper/tempo 98.25", &endpointRegistry);
  if (!check(legacyDspPath.kind == ParseResult::Kind::Error,
             "legacy /dsp/looper alias path rejected")) {
    return failCode();
  }

  const auto unknownCore =
      CommandParser::parse("SET /core/behavior/nope 1", &endpointRegistry);
  if (!check(unknownCore.kind == ParseResult::Kind::Error,
             "unknown canonical path returns parse error")) {
    return failCode();
  }

  const auto badType =
      CommandParser::parse("SET /core/behavior/tempo nope", &endpointRegistry);
  if (!check(badType.kind == ParseResult::Kind::NoOpWarning,
             "impossible coercion returns no-op warning")) {
    return failCode();
  }
  if (!check(badType.warningCode == "W_COERCE_IMPOSSIBLE_NOOP",
             "impossible coercion warning code")) {
    return failCode();
  }

  const auto lossyInt =
      CommandParser::parse("SET /core/behavior/layer 2.8", &endpointRegistry);
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
