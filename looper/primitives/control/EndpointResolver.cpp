#include "EndpointResolver.h"

#include <algorithm>
#include <cstdlib>
#include <cmath>

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
                                      const juce::String &message) {
  ResolverValidationResult result;
  result.code = code;
  result.accepted = false;
  result.message = message;
  return result;
}

ResolverValidationResult makeAccepted(ResolverValidationCode code,
                                      const juce::var &normalized,
                                      bool coerced,
                                      bool clamped,
                                      const juce::String &message = {}) {
  ResolverValidationResult result;
  result.code = code;
  result.accepted = true;
  result.coerced = coerced;
  result.clamped = clamped;
  result.normalizedValue = normalized;
  result.message = message;
  return result;
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

  return makeAccepted(ResolverValidationCode::Ok, juce::var(), false, false);
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
    return makeAccepted(ResolverValidationCode::Ok, juce::var(), false, false);
  }

  if (input.isVoid()) {
    return makeRejected(ResolverValidationCode::MissingValue,
                        "missing value for write operation");
  }

  bool coerced = false;
  bool clamped = false;
  juce::var normalized = input;

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
    if (input.isInt() || input.isInt64() || input.isDouble() || input.isBool()) {
      value = static_cast<double>(input);
      coerced = !input.isDouble();
    } else if (input.isString()) {
      if (!parseNumberFromString(input.toString(), value)) {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "cannot coerce string to float");
      }
      coerced = true;
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for float endpoint");
    }

    value = clampNumeric(value);
    normalized = juce::var(static_cast<float>(value));
    break;
  }

  case ResolverValueType::Int: {
    double value = 0.0;
    if (input.isInt()) {
      value = static_cast<double>(static_cast<int>(input));
    } else if (input.isInt64() || input.isDouble() || input.isBool()) {
      value = static_cast<double>(input);
      coerced = true;
    } else if (input.isString()) {
      if (!parseNumberFromString(input.toString(), value)) {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "cannot coerce string to int");
      }
      coerced = true;
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for int endpoint");
    }

    value = clampNumeric(value);
    normalized = juce::var(static_cast<int>(std::round(value)));
    break;
  }

  case ResolverValueType::Bool: {
    bool value = false;
    if (input.isBool()) {
      value = static_cast<bool>(input);
    } else if (input.isInt() || input.isInt64() || input.isDouble()) {
      value = static_cast<double>(input) != 0.0;
      coerced = true;
    } else if (input.isString()) {
      const auto text = input.toString().trim().toLowerCase();
      if (text == "true" || text == "on" || text == "1") {
        value = true;
      } else if (text == "false" || text == "off" || text == "0") {
        value = false;
      } else {
        return makeRejected(ResolverValidationCode::TypeMismatch,
                            "cannot coerce string to bool");
      }
      coerced = true;
    } else {
      return makeRejected(ResolverValidationCode::TypeMismatch,
                          "unsupported input type for bool endpoint");
    }

    normalized = juce::var(value ? 1 : 0);
    break;
  }

  case ResolverValueType::String: {
    if (!input.isString()) {
      coerced = true;
      normalized = juce::var(input.toString());
    }
    break;
  }

  case ResolverValueType::Unknown:
    break;

  case ResolverValueType::Trigger:
    break;
  }

  if (clamped) {
    return makeAccepted(ResolverValidationCode::RangeClamped, normalized, coerced,
                        true, "value clamped to endpoint range");
  }
  if (coerced) {
    return makeAccepted(ResolverValidationCode::Coerced, normalized, true, false,
                        "value coerced to endpoint type");
  }
  return makeAccepted(ResolverValidationCode::Ok, normalized, false, false);
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
