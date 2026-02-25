#pragma once

#include "OSCEndpointRegistry.h"
#include <juce_core/juce_core.h>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

enum class ResolverValueType {
  Unknown = 0,
  Trigger,
  Float,
  Int,
  Bool,
  String,
};

enum class ResolverValidationCode {
  Ok = 0,
  UnknownPath,
  AccessDenied,
  MissingValue,
  TypeMismatch,
  Coerced,
  RangeClamped,
};

enum class ResolverCoercionCategory {
  None = 0,
  Exact,
  Lossless,
  Lossy,
  Impossible,
};

struct ResolvedEndpoint {
  int runtimeId = -1;
  juce::String path;
  ResolverValueType valueType = ResolverValueType::Unknown;
  int access = 0; // 0=none, 1=read, 2=write, 3=read-write
  float rangeMin = 0.0f;
  float rangeMax = 0.0f;
  bool hasRange = false;
  ControlCommand::Type commandType = ControlCommand::Type::None;
  int layerIndex = -1;
  juce::String description;
  juce::String category;
};

struct ResolverValidationResult {
  ResolverValidationCode code = ResolverValidationCode::Ok;
  ResolverCoercionCategory coercionCategory =
      ResolverCoercionCategory::None;
  bool accepted = false;
  bool coerced = false;
  bool clamped = false;
  juce::var normalizedValue;
  juce::String message;
};

class EndpointResolver {
public:
  explicit EndpointResolver(OSCEndpointRegistry *registry = nullptr);

  void setRegistry(OSCEndpointRegistry *registry);
  void rebuild();

  bool resolve(const juce::String &path, ResolvedEndpoint &out) const;
  int getResolvedCount() const;

  ResolverValidationResult validateRead(const ResolvedEndpoint &endpoint) const;
  ResolverValidationResult validateWrite(const ResolvedEndpoint &endpoint,
                                         const juce::var &input) const;

private:
  static ResolverValueType mapValueType(const juce::String &typeTag);

  OSCEndpointRegistry *registry = nullptr;
  std::vector<ResolvedEndpoint> endpoints;
  std::unordered_map<std::string, int> pathToRuntimeId;
  mutable std::mutex mutex;
};
