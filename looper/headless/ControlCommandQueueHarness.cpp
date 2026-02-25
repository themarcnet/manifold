#include "../primitives/control/ControlServer.h"

#include <cmath>
#include <cstdio>

namespace {

ControlCommand buildExpectedCommand(int sequence) {
  ControlCommand command;
  command.operation = ControlOperation::Set;
  command.endpointId = sequence % 97;

  const int mode = sequence % 3;
  if (mode == 0) {
    command.value.kind = ControlValueKind::Float;
    command.value.floatValue = 0.5f + static_cast<float>(sequence % 1000) / 1000.0f;
    command.floatParam = command.value.floatValue;
    command.type = ControlCommand::Type::LayerSpeed;
    command.intParam = sequence % 4;
  } else if (mode == 1) {
    command.value.kind = ControlValueKind::Int;
    command.value.intValue = sequence % 4;
    command.intParam = command.value.intValue;
    command.floatParam = static_cast<float>(command.value.intValue);
    command.type = ControlCommand::Type::SetActiveLayer;
  } else {
    command.value.kind = ControlValueKind::Bool;
    command.value.boolValue = (sequence % 2) != 0;
    command.intParam = sequence % 4;
    command.floatParam = command.value.boolValue ? 1.0f : 0.0f;
    command.type = ControlCommand::Type::LayerReverse;
  }

  return command;
}

bool sameCommand(const ControlCommand &left, const ControlCommand &right) {
  if (left.operation != right.operation || left.endpointId != right.endpointId ||
      left.type != right.type || left.intParam != right.intParam) {
    return false;
  }

  if (left.value.kind != right.value.kind) {
    return false;
  }

  switch (left.value.kind) {
  case ControlValueKind::Float:
    return std::abs(left.value.floatValue - right.value.floatValue) < 0.0001f;
  case ControlValueKind::Int:
    return left.value.intValue == right.value.intValue;
  case ControlValueKind::Bool:
    return left.value.boolValue == right.value.boolValue;
  case ControlValueKind::Trigger:
  case ControlValueKind::None:
    return true;
  }

  return false;
}

} // namespace

int main() {
  SPSCQueue<256> queue;
  int produced = 0;
  int consumed = 0;
  constexpr int kBurstCount = 40000;

  auto consumeOne = [&]() -> bool {
    ControlCommand dequeued;
    if (!queue.dequeue(dequeued)) {
      return false;
    }

    const ControlCommand expected = buildExpectedCommand(consumed);
    if (!sameCommand(dequeued, expected)) {
      std::fprintf(stderr,
                   "ControlCommandQueueHarness: FAIL at index %d (mismatch)\n",
                   consumed);
      return false;
    }

    ++consumed;
    return true;
  };

  for (; produced < kBurstCount; ++produced) {
    const ControlCommand command = buildExpectedCommand(produced);
    while (!queue.enqueue(command)) {
      if (!consumeOne()) {
        return 2;
      }
    }
  }

  while (consumed < produced) {
    if (!consumeOne()) {
      return 3;
    }
  }

  if (produced != consumed) {
    std::fprintf(stderr,
                 "ControlCommandQueueHarness: FAIL produced=%d consumed=%d\n",
                 produced, consumed);
    return 4;
  }

  std::fprintf(stdout,
               "ControlCommandQueueHarness: PASS (commands=%d, capacity=%d)\n",
               produced, 256);
  return 0;
}
