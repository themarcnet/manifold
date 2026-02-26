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

  const auto setTempo = CommandParser::parse("SET /looper/tempo 132.5", &endpointRegistry);
  if (!check(setTempo.kind == ParseResult::Kind::Enqueue,
             "SET /looper/tempo parses as enqueue")) {
    return 2;
  }
  if (!check(setTempo.command.operation == ControlOperation::Set,
             "SET /looper/tempo operation is Set")) {
    return 3;
  }
  if (!check(setTempo.command.type == ControlCommand::Type::SetTempo,
             "SET /looper/tempo maps to SetTempo")) {
    return 4;
  }
  if (!check(setTempo.command.value.kind == ControlValueKind::Float &&
                 near(setTempo.command.value.floatValue, 132.5f) &&
                 near(setTempo.command.floatParam, 132.5f),
             "SET /looper/tempo payload carries float value")) {
    return 5;
  }

  const auto setLayerSpeed =
      CommandParser::parse("SET /looper/layer/2/speed 0.75", &endpointRegistry);
  if (!check(setLayerSpeed.kind == ParseResult::Kind::Enqueue,
             "SET layer speed parses as enqueue")) {
    return 6;
  }
  if (!check(setLayerSpeed.command.type == ControlCommand::Type::LayerSpeed &&
                 setLayerSpeed.command.intParam == 2 &&
                 near(setLayerSpeed.command.floatParam, 0.75f),
             "SET layer speed maps layer index and value")) {
    return 7;
  }

  const auto setMode =
      CommandParser::parse("SET /looper/mode freeMode", &endpointRegistry);
  if (!check(setMode.kind == ParseResult::Kind::Enqueue,
             "SET /looper/mode parses as enqueue")) {
    return 8;
  }
  if (!check(setMode.command.type == ControlCommand::Type::SetRecordMode &&
                 setMode.command.value.kind == ControlValueKind::Int &&
                 setMode.command.intParam == 1,
             "SET /looper/mode maps to record mode index")) {
    return 9;
  }

  const auto setOverdub =
      CommandParser::parse("SET /looper/overdub 1", &endpointRegistry);
  if (!check(setOverdub.kind == ParseResult::Kind::Enqueue,
             "SET /looper/overdub parses as enqueue")) {
    return 10;
  }
  if (!check(setOverdub.command.type == ControlCommand::Type::SetOverdubEnabled &&
                 near(setOverdub.command.floatParam, 1.0f),
             "SET /looper/overdub maps to SetOverdubEnabled")) {
    return 11;
  }

  const auto triggerRec =
      CommandParser::parse("TRIGGER /looper/rec", &endpointRegistry);
  if (!check(triggerRec.kind == ParseResult::Kind::Enqueue,
             "TRIGGER /looper/rec parses as enqueue")) {
    return 12;
  }
  if (!check(triggerRec.command.operation == ControlOperation::Trigger &&
                 triggerRec.command.type == ControlCommand::Type::StartRecording &&
                 triggerRec.command.value.kind == ControlValueKind::Trigger,
             "TRIGGER /looper/rec maps trigger payload")) {
    return 13;
  }

  const auto getTempo =
      CommandParser::parse("GET /looper/tempo", &endpointRegistry);
  if (!check(getTempo.kind == ParseResult::Kind::Query &&
                 getTempo.queryType == "GET" &&
                 getTempo.queryPath == "/looper/tempo",
             "GET /looper/tempo parses as query")) {
    return 14;
  }

  const auto getDiagnostics =
      CommandParser::parse("GET /looper/diagnostics", &endpointRegistry);
  if (!check(getDiagnostics.kind == ParseResult::Kind::Query &&
                 getDiagnostics.queryType == "GET" &&
                 getDiagnostics.queryPath == "/looper/diagnostics",
             "GET /looper/diagnostics parses as query")) {
    return 15;
  }

  const auto unknownPath =
      CommandParser::parse("SET /looper/nope 1", &endpointRegistry);
  if (!check(unknownPath.kind == ParseResult::Kind::Error,
             "unknown path returns parse error")) {
    return 16;
  }

  const auto badType =
      CommandParser::parse("SET /looper/tempo nope", &endpointRegistry);
  if (!check(badType.kind == ParseResult::Kind::NoOpWarning,
             "impossible coercion returns no-op warning")) {
    return 17;
  }
  if (!check(badType.warningCode == "W_COERCE_IMPOSSIBLE_NOOP",
             "impossible coercion warning code")) {
    return 18;
  }

  const auto lossyInt =
      CommandParser::parse("SET /looper/layer 2.8", &endpointRegistry);
  if (!check(lossyInt.kind == ParseResult::Kind::Enqueue,
             "lossy coercion still enqueues")) {
    return 19;
  }
  if (!check(lossyInt.warningCode == "W_COERCE_LOSSY" &&
                 lossyInt.command.intParam == 2,
             "lossy coercion warning code")) {
    return 20;
  }

  const auto legacyTempo =
      CommandParser::parse("TEMPO 127", &endpointRegistry);
  if (!check(legacyTempo.kind == ParseResult::Kind::Error,
             "legacy TEMPO now rejected")) {
    return 21;
  }
  if (!check(legacyTempo.usedLegacySyntax &&
                 legacyTempo.errorCode == "W_PATH_DEPRECATED",
             "legacy TEMPO returns deprecation error code")) {
    return 22;
  }

  const auto legacyLayerReverse =
      CommandParser::parse("LAYER 2 REVERSE 1", &endpointRegistry);
  if (!check(legacyLayerReverse.kind == ParseResult::Kind::Error,
             "legacy layer reverse now rejected")) {
    return 23;
  }
  if (!check(legacyLayerReverse.usedLegacySyntax &&
                 legacyLayerReverse.errorCode == "W_PATH_DEPRECATED",
               "legacy layer reverse returns deprecation error code")) {
    return 24;
  }

  const auto legacyStop = CommandParser::parse("STOP", &endpointRegistry);
  if (!check(legacyStop.kind == ParseResult::Kind::Error,
             "legacy STOP now rejected")) {
    return 25;
  }
  if (!check(legacyStop.usedLegacySyntax &&
                 legacyStop.errorCode == "W_PATH_DEPRECATED",
               "legacy STOP returns deprecation error code")) {
    return 26;
  }

  const auto diagnostics = CommandParser::getDiagnosticsSnapshot();
  if (!check(diagnostics.legacySyntaxTotal >= 3,
             "legacy syntax total counter increments")) {
    return 27;
  }
  if (!check(diagnostics.legacyVerbTempo >= 1 &&
                 diagnostics.legacyVerbLayer >= 1 &&
                 diagnostics.legacyVerbStop >= 1,
             "legacy per-verb counters increment")) {
    return 28;
  }

  std::fprintf(stdout, "CanonicalCommandHarness: PASS (%d checks)\n", checks);
  return 0;
}
