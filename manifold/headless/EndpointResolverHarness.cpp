#include "../primitives/control/EndpointResolver.h"

#include <cmath>
#include <cstdio>

namespace {

bool near(double a, double b, double epsilon = 0.001) {
  return std::abs(a - b) <= epsilon;
}

} // namespace

int main() {
  OSCEndpointRegistry registry;
  registry.setNumLayers(4);
  registry.rebuild();

  EndpointResolver resolver(&registry);

  int checks = 0;
  auto check = [&](bool ok, const char *message) -> bool {
    ++checks;
    if (!ok) {
      std::fprintf(stderr, "EndpointResolverHarness: FAIL: %s\n", message);
      return false;
    }
    return true;
  };

  ResolvedEndpoint tempo;
  if (!check(resolver.resolve("/core/behavior/tempo", tempo),
             "resolve /core/behavior/tempo")) {
    return 2;
  }
  if (!check(tempo.valueType == ResolverValueType::Float,
             "tempo type is float")) {
    return 3;
  }
  if (!check(tempo.access == 3, "tempo access is read-write")) {
    return 4;
  }
  if (!check(tempo.hasRange && near(tempo.rangeMin, 20.0) &&
                 near(tempo.rangeMax, 300.0),
             "tempo range metadata")) {
    return 5;
  }

  ResolvedEndpoint missing;
  if (!check(!resolver.resolve("/does/not/exist", missing),
             "unknown path rejects")) {
    return 6;
  }

  ResolvedEndpoint recState;
  if (!check(resolver.resolve("/core/behavior/recording", recState),
             "resolve read-only endpoint")) {
    return 7;
  }
  const auto writeDenied = resolver.validateWrite(recState, juce::var(1));
  if (!check(!writeDenied.accepted &&
                 writeDenied.code == ResolverValidationCode::AccessDenied,
             "read-only write denied")) {
    return 8;
  }

  ResolvedEndpoint recTrigger;
  if (!check(resolver.resolve("/core/behavior/rec", recTrigger),
             "resolve trigger endpoint")) {
    return 9;
  }
  const auto readDenied = resolver.validateRead(recTrigger);
  if (!check(!readDenied.accepted &&
                 readDenied.code == ResolverValidationCode::AccessDenied,
             "write-only read denied")) {
    return 10;
  }

  const auto tempoCoerced = resolver.validateWrite(tempo, juce::var("123.5"));
  if (!check(tempoCoerced.accepted &&
                 tempoCoerced.coercionCategory == ResolverCoercionCategory::Lossy,
             "tempo coercion category is lossy for string numeric")) {
    return 11;
  }
  if (!check(near(static_cast<double>(tempoCoerced.normalizedValue), 123.5),
             "tempo coerced value expected")) {
    return 12;
  }

  const auto tempoBad = resolver.validateWrite(tempo, juce::var("abc"));
  if (!check(!tempoBad.accepted &&
                 tempoBad.coercionCategory == ResolverCoercionCategory::Impossible,
             "tempo invalid string is impossible coercion")) {
    return 13;
  }

  const auto tempoClamped = resolver.validateWrite(tempo, juce::var(999.0));
  if (!check(tempoClamped.accepted && tempoClamped.clamped,
             "tempo clamps out-of-range")) {
    return 14;
  }
  if (!check(tempoClamped.coercionCategory == ResolverCoercionCategory::Lossy,
             "tempo clamp is lossy coercion")) {
    return 15;
  }
  if (!check(near(static_cast<double>(tempoClamped.normalizedValue), 300.0),
              "tempo clamped max value")) {
    return 16;
  }

  ResolvedEndpoint reverse;
  if (!check(resolver.resolve("/core/behavior/layer/0/reverse", reverse),
             "resolve layer reverse endpoint")) {
    return 17;
  }
  const auto reverseCoerced = resolver.validateWrite(reverse, juce::var(true));
  if (!check(reverseCoerced.accepted,
              "reverse accepts bool input")) {
    return 18;
  }
  if (!check(reverseCoerced.coercionCategory ==
                 ResolverCoercionCategory::Lossless,
             "reverse bool input is lossless")) {
    return 19;
  }
  if (!check(static_cast<int>(reverseCoerced.normalizedValue) == 1,
              "reverse normalizes bool to 1")) {
    return 20;
  }

  const auto reverseFromString = resolver.validateWrite(reverse, juce::var("on"));
  if (!check(!reverseFromString.accepted &&
                 reverseFromString.coercionCategory ==
                     ResolverCoercionCategory::Impossible,
             "reverse non-numeric string coercion is impossible")) {
    return 21;
  }

  ResolvedEndpoint layerIndex;
  if (!check(resolver.resolve("/core/behavior/layer", layerIndex),
             "resolve /core/behavior/layer int endpoint")) {
    return 22;
  }
  const auto layerIntExact = resolver.validateWrite(layerIndex, juce::var(2));
  if (!check(layerIntExact.accepted &&
                 layerIntExact.coercionCategory == ResolverCoercionCategory::Exact,
             "int endpoint exact int coercion")) {
    return 23;
  }
  const auto layerIntLossless = resolver.validateWrite(layerIndex, juce::var(true));
  if (!check(layerIntLossless.accepted &&
                 layerIntLossless.coercionCategory ==
                     ResolverCoercionCategory::Lossless,
             "int endpoint bool coercion is lossless")) {
    return 24;
  }
  const auto layerIntLossy = resolver.validateWrite(layerIndex, juce::var(2.8));
  if (!check(layerIntLossy.accepted &&
                 layerIntLossy.coercionCategory == ResolverCoercionCategory::Lossy &&
                 static_cast<int>(layerIntLossy.normalizedValue) == 2,
             "int endpoint float coercion is lossy and truncated")) {
    return 25;
  }

  ResolvedEndpoint mode;
  if (!check(resolver.resolve("/core/behavior/mode", mode),
             "resolve /core/behavior/mode string endpoint")) {
    return 26;
  }
  const auto modeExact = resolver.validateWrite(mode, juce::var("freeMode"));
  if (!check(modeExact.accepted &&
                 modeExact.coercionCategory == ResolverCoercionCategory::Exact,
             "string endpoint exact string coercion")) {
    return 27;
  }
  const auto modeLossless = resolver.validateWrite(mode, juce::var(2));
  if (!check(modeLossless.accepted &&
                 modeLossless.coercionCategory ==
                     ResolverCoercionCategory::Lossless,
             "string endpoint int coercion is lossless serialize")) {
    return 28;
  }

  juce::DynamicObject::Ptr impossibleObject(new juce::DynamicObject());
  const auto modeImpossible =
      resolver.validateWrite(mode, juce::var(impossibleObject));
  if (!check(!modeImpossible.accepted &&
                 modeImpossible.coercionCategory ==
                     ResolverCoercionCategory::Impossible,
             "string endpoint table/object coercion impossible")) {
    return 29;
  }

  const int beforeRebuildId = tempo.runtimeId;
  resolver.rebuild();
  ResolvedEndpoint tempoAfter;
  if (!check(resolver.resolve("/core/behavior/tempo", tempoAfter),
             "resolve tempo after rebuild")) {
    return 30;
  }
  if (!check(beforeRebuildId == tempoAfter.runtimeId,
              "runtime id remains stable across rebuild")) {
    return 31;
  }

  std::fprintf(stdout, "EndpointResolverHarness: PASS (%d checks)\n", checks);
  return 0;
}
