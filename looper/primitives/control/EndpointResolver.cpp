#include "EndpointResolver.h"

#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <limits>

namespace {

bool parseNumberFromString(const juce::String &value, double &out) {
  const auto trimmed = value.trim();
  if (trimmed.isEmpty()) {
    return false;
  }

  char *end = nullptr;
  const std::string text = trimmed.toStdString();
  const double parsed = std::strtod(text.c_str(), &end);
  if (end == text.c_str() || *end != '\0') {
    return false;
  }

  out = parsed;
  return true;
}

ResolverValidationResult makeRejected(ResolverValidationCode code,
                                      const juce::String &message,
                                      ResolverCoercionCategory category =
                                          ResolverCoercionCategory::None) {
  ResolverValidationResult result;
  result.code = code;
  result.coercionCategory = category;
  result.accepted = false;
  result.coerced =
      category == ResolverCoercionCategory::Lossless ||
      category == ResolverCoercionCategory::Lossy;
  result.message = message;
  return result;
}

ResolverValidationResult makeAccepted(ResolverValidationCode code,
                                      const juce::var &normalized,
                                      ResolverCoercionCategory category,
                                      bool clamped,
                                      const juce::String &message = {}) {
  ResolverValidationResult result;
  result.code = code;
  result.coercionCategory = category;
  result.accepted = true;
  result.coerced =
      category == ResolverCoercionCategory::Lossless ||
      category == ResolverCoercionCategory::Lossy;
  result.clamped = clamped;
  result.normalizedValue = normalized;
  result.message = message;
  return result;
}

ResolverCoercionCategory mergeWithClamp(ResolverCoercionCategory category,
                                        bool clamped) {
  if (!clamped) {
    return category;
  }

  if (category == ResolverCoercionCategory::Exact ||
      category == ResolverCoercionCategory::Lossless) {
    return ResolverCoercionCategory::Lossy;
  }

  return category;
}

ResolverValidationResult makeAcceptedFromCategory(
    const juce::var &normalized,
    ResolverCoercionCategory category,
    bool clamped,
    const juce::String &message = {}) {
  const ResolverCoercionCategory mergedCategory = mergeWithClamp(category, clamped);
  const ResolverValidationCode code =
      clamped ? ResolverValidationCode::RangeClamped
              : (mergedCategory == ResolverCoercionCategory::Exact
                     ? ResolverValidationCode::Ok
                     : ResolverValidationCode::Coerced);
  return makeAccepted(code, normalized, mergedCategory, clamped, message);
}

} // namespace

EndpointResolver::EndpointResolver(OSCEndpointRegistry *registry_) : registry(registry_) {
  rebuild();
}

void EndpointResolver::setRegistry(OSCEndpointRegistry *registry_) {
  {
    const std::lock_guard<std::mutex> lock(mutex);
    registry = registry_;
  }
  rebuild();
}

void EndpointResolver::rebuild() {
  std::vector<OSCEndpoint> sourceEndpoints;
  {
    const std::lock_guard<std::mutex> lock(mutex);
    if (registry == nullptr) {
      endpoints.clear();
      pathToRuntimeId.clear();
      return;
    }
    sourceEndpoints = registry->getAllEndpoints();
  }

  std::sort(sourceEndpoints.begin(), sourceEndpoints.end(),
            [](const OSCEndpoint &a, const OSCEndpoint &b) {
              return a.path < b.path;
            });

  std::vector<ResolvedEndpoint> resolved;
  resolved.reserve(sourceEndpoints.size());
  std::unordered_map<std::string, int> index;
  index.reserve(sourceEndpoints.size());

  for (size_t i = 0; i < sourceEndpoints.size(); ++i) {
    const auto &endpoint = sourceEndpoints[i];
    ResolvedEndpoint item;
    item.runtimeId = static_cast<int>(i);
    item.path = endpoint.path;
    item.valueType = mapValueType(endpoint.type);
    item.access = endpoint.access;
    item.rangeMin = endpoint.rangeMin;
    item.rangeMax = endpoint.rangeMax;
    item.hasRange =
        (item.valueType == ResolverValueType::Float ||
         item.valueType == ResolverValueType::Int) &&
        (endpoint.rangeMin != endpoint.rangeMax);
    item.commandType = endpoint.commandType;
    item.layerIndex = endpoint.layerIndex;
    item.description = endpoint.description;
    item.category = endpoint.category;
    resolved.push_back(item);
    index.emplace(endpoint.path.toStdString(), static_cast<int>(i));
  }

  const std::lock_guard<std::mutex> lock(mutex);
  endpoints = std::move(resolved);
  pathToRuntimeId = std::move(index);
}

bool EndpointResolver::resolve(const juce::String &path, ResolvedEndpoint &out) const {
  const std::lock_guard<std::mutex> lock(mutex);
  const auto it = pathToRuntimeId.find(path.toStdString());
  if (it == pathToRuntimeId.end()) {
    return false;
  }

  const int id = it->second;
  if (id < 0 || id >= static_cast<int>(endpoints.size())) {
    return false;
  }

  out = endpoints[static_cast<size_t>(id)];
  return true;
}

int EndpointResolver::getResolvedCount() const {
  const std::lock_guard<std::mutex> lock(mutex);
  return static_cast<int>(endpoints.size());
}

ResolverValidationResult
EndpointResolver::validateRead(const ResolvedEndpoint &endpoint) const {
  const bool readable = endpoint.access == 1 || endpoint.access == 3;
  if (!readable) {
    return makeRejected(ResolverValidationCode::AccessDenied,
                        "endpoint is not readable");
  }

  return makeAccepted(ResolverValidationCode::Ok, juce::var(),
                      ResolverCoercionCategory::Exact, false);
}

ResolverValidationResult
EndpointResolver::validateWrite(const ResolvedEndpoint &endpoint,
                                const juce::var &input) const {
  const bool writable = endpoint.access == 2 || endpoint.access == 3;
  if (!writable) {
    return makeRejected(ResolverValidationCode::AccessDenied,
                        "endpoint is not writable");
  }

  if (endpoint.valueType == ResolverValueType::Trigger) {
    if (!input.isVoid()) {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "trigger endpoint does not accept a value");
    }
    return makeAccepted(ResolverValidationCode::Ok, juce::var(),
                        ResolverCoercionCategory::Exact, false);
  }

  if (input.isVoid()) {
    return makeRejected(ResolverValidationCode::MissingValue,
                        "missing value for write operation");
  }

  bool clamped = false;
  juce::var normalized = input;
  ResolverCoercionCategory coercionCategory =
      ResolverCoercionCategory::Exact;

  auto clampNumeric = [&](double value) -> double {
    if (!endpoint.hasRange) {
      return value;
    }

    if (value < endpoint.rangeMin) {
      clamped = true;
      return endpoint.rangeMin;
    }
    if (value > endpoint.rangeMax) {
      clamped = true;
      return endpoint.rangeMax;
    }
    return value;
  };

  switch (endpoint.valueType) {
  case ResolverValueType::Float: {
    double value = 0.0;
    if (input.isDouble()) {
      value = static_cast<double>(input);
      coercionCategory = ResolverCoercionCategory::Exact;
    } else if (input.isInt() || input.isInt64() || input.isBool()) {
      value = static_cast<double>(input);
      coercionCategory = ResolverCoercionCategory::Lossless;
    } else if (input.isString()) {
      if (!parseNumberFromString(input.toString(), value)) {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "cannot coerce string to float",
                            ResolverCoercionCategory::Impossible);
      }
      coercionCategory = ResolverCoercionCategory::Lossy;
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for float endpoint",
                          ResolverCoercionCategory::Impossible);
    }

    value = clampNumeric(value);
    normalized = juce::var(static_cast<float>(value));
    return makeAcceptedFromCategory(normalized, coercionCategory, clamped,
                                    clamped ? "value clamped to endpoint range"
                                            : juce::String());
  }

  case ResolverValueType::Int: {
    double value = 0.0;
    if (input.isInt()) {
      value = static_cast<double>(static_cast<int>(input));
      coercionCategory = ResolverCoercionCategory::Exact;
    } else if (input.isBool()) {
      value = static_cast<double>(input);
      coercionCategory = ResolverCoercionCategory::Lossless;
    } else if (input.isInt64()) {
      const auto raw = static_cast<double>(input);
      if (raw < static_cast<double>(std::numeric_limits<int>::lowest()) ||
          raw > static_cast<double>(std::numeric_limits<int>::max())) {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "int64 value out of int range",
                            ResolverCoercionCategory::Impossible);
      }
      value = raw;
      coercionCategory = ResolverCoercionCategory::Lossless;
    } else if (input.isDouble()) {
      const double raw = static_cast<double>(input);
      if (!std::isfinite(raw)) {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "double value is not finite",
                            ResolverCoercionCategory::Impossible);
      }
      value = raw;
      coercionCategory = (std::trunc(raw) == raw)
                             ? ResolverCoercionCategory::Lossless
                             : ResolverCoercionCategory::Lossy;
    } else if (input.isString()) {
      if (!parseNumberFromString(input.toString(), value)) {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "cannot coerce string to int",
                            ResolverCoercionCategory::Impossible);
      }
      coercionCategory = ResolverCoercionCategory::Lossy;
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for int endpoint",
                          ResolverCoercionCategory::Impossible);
    }

    value = clampNumeric(value);
    if (value < static_cast<double>(std::numeric_limits<int>::lowest()) ||
        value > static_cast<double>(std::numeric_limits<int>::max())) {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "numeric value out of int range",
                          ResolverCoercionCategory::Impossible);
    }
    normalized = juce::var(static_cast<int>(value));
    return makeAcceptedFromCategory(normalized, coercionCategory, clamped,
                                    clamped ? "value clamped to endpoint range"
                                            : juce::String());
  }

  case ResolverValueType::Bool: {
    bool value = false;
    if (input.isBool()) {
      value = static_cast<bool>(input);
      coercionCategory = ResolverCoercionCategory::Exact;
    } else if (input.isInt() || input.isInt64() || input.isDouble()) {
      value = static_cast<double>(input) != 0.0;
      coercionCategory = ResolverCoercionCategory::Lossy;
    } else if (input.isString()) {
      const auto text = input.toString().trim().toLowerCase();
      double numeric = 0.0;
      if (parseNumberFromString(text, numeric)) {
        value = numeric != 0.0;
        coercionCategory = ResolverCoercionCategory::Lossy;
      } else if (text == "true" || text == "on" || text == "1") {
        value = true;
        coercionCategory = ResolverCoercionCategory::Lossy;
      } else if (text == "false" || text == "off" || text == "0") {
        value = false;
        coercionCategory = ResolverCoercionCategory::Lossy;
      } else {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "cannot coerce string to bool",
                            ResolverCoercionCategory::Impossible);
      }
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for bool endpoint",
                          ResolverCoercionCategory::Impossible);
    }

    normalized = juce::var(value ? 1 : 0);
    return makeAcceptedFromCategory(normalized, coercionCategory, false);
  }

  case ResolverValueType::String: {
    if (input.isString()) {
      coercionCategory = ResolverCoercionCategory::Exact;
      normalized = input;
    } else if (input.isInt() || input.isInt64() || input.isBool()) {
      coercionCategory = ResolverCoercionCategory::Lossless;
      normalized = juce::var(input.toString());
    } else if (input.isDouble()) {
      coercionCategory = ResolverCoercionCategory::Lossy;
      normalized = juce::var(input.toString());
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for string endpoint",
                          ResolverCoercionCategory::Impossible);
    }

    return makeAcceptedFromCategory(normalized, coercionCategory, false);
  }

  case ResolverValueType::Unknown:
    return makeAcceptedFromCategory(normalized, ResolverCoercionCategory::Exact,
                                    false);

  case ResolverValueType::Trigger:
    return makeAcceptedFromCategory(juce::var(), ResolverCoercionCategory::Exact,
                                    false);
  }

  return makeAcceptedFromCategory(normalized, ResolverCoercionCategory::Exact,
                                  false);
}

ResolverValueType EndpointResolver::mapValueType(const juce::String &typeTag) {
  if (typeTag.isEmpty()) {
    return ResolverValueType::Unknown;
  }

  const juce::juce_wchar first = typeTag[0];
  switch (first) {
  case 'f':
  case 'd':
    return ResolverValueType::Float;
  case 'i':
  case 'h':
    return ResolverValueType::Int;
  case 'T':
  case 'F':
    return ResolverValueType::Bool;
  case 's':
  case 'S':
    return ResolverValueType::String;
  case 'N':
  case 'I':
    return ResolverValueType::Trigger;
  default:
    return ResolverValueType::Unknown;
  }
}
