local MidiDevices = require("ui.midi_devices")

local M = {}

local SEMANTIC_SOURCES = {
  {
    id = "midi.note",
    direction = "source",
    scope = "voice",
    signalKind = "scalar",
    domain = "midi_note",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "MIDI Note",
    available = true,
    min = 0,
    max = 127,
    default = 60,
  },
  {
    id = "midi.gate",
    direction = "source",
    scope = "voice",
    signalKind = "gate",
    domain = "event",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "MIDI Gate",
    available = true,
    min = 0,
    max = 1,
    default = 0,
  },
  {
    id = "midi.velocity",
    direction = "source",
    scope = "voice",
    signalKind = "scalar_unipolar",
    domain = "normalized",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "MIDI Velocity",
    available = true,
    min = 0,
    max = 1,
    default = 0,
  },
  {
    id = "midi.voice",
    direction = "source",
    scope = "voice",
    signalKind = "voice_bundle",
    domain = "voice",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "MIDI Voice",
    available = true,
    min = 0,
    max = 1,
    default = 0,
  },
  {
    id = "midi.pitch_bend",
    direction = "source",
    scope = "global",
    signalKind = "scalar_bipolar",
    domain = "pitch_bend",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "Pitch Bend",
    available = true,
    min = -1,
    max = 1,
    default = 0,
  },
  {
    id = "midi.channel_pressure",
    direction = "source",
    scope = "global",
    signalKind = "scalar_unipolar",
    domain = "pressure",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "Channel Pressure",
    available = true,
    min = 0,
    max = 1,
    default = 0,
  },
  {
    id = "midi.mod_wheel",
    direction = "source",
    scope = "global",
    signalKind = "scalar_unipolar",
    domain = "normalized",
    provider = "midi-performance",
    owner = "keyboard",
    displayName = "Mod Wheel",
    available = true,
    min = 0,
    max = 1,
    default = 0,
    meta = {
      cc = 1,
    },
  },
}

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, entry in pairs(value) do
    out[key] = copyTable(entry)
  end
  return out
end

local function copyArray(values)
  local out = {}
  for i = 1, #(values or {}) do
    out[i] = copyTable(values[i])
  end
  return out
end

local function currentDevice(ctx)
  local activeLabel = MidiDevices.getCurrentMidiInputLabel(ctx)
  if type(activeLabel) ~= "string" or activeLabel == "" then
    return nil
  end

  local activeKey = MidiDevices.normalizeDeviceKey(activeLabel)
  if activeKey == nil then
    return nil
  end

  return {
    key = activeKey,
    label = activeLabel,
  }
end

local function makeDeviceEndpoint(device, suffix, displayName, signalKind, domain, meta, available)
  return {
    id = string.format("midi.device.%s.%s", tostring(device.key), tostring(suffix)),
    direction = "source",
    scope = "global",
    signalKind = signalKind,
    domain = domain,
    provider = "midi-device",
    owner = tostring(device.key),
    displayName = string.format("%s — %s", tostring(device.label or device.key), tostring(displayName)),
    available = available,
    min = signalKind == "scalar_bipolar" and -1 or 0,
    max = 1,
    default = 0,
    meta = meta,
  }
end

function M.collect(ctx, options)
  local out = copyArray(SEMANTIC_SOURCES)
  local device = currentDevice(ctx)
  if device == nil then
    return out
  end

  out[#out + 1] = makeDeviceEndpoint(device, "pitch_bend", "Pitch Bend", "scalar_bipolar", "pitch_bend", {
    deviceKey = device.key,
    deviceLabel = device.label,
    endpointKey = "pitch_bend",
  }, true)

  out[#out + 1] = makeDeviceEndpoint(device, "channel_pressure", "Channel Pressure", "scalar_unipolar", "pressure", {
    deviceKey = device.key,
    deviceLabel = device.label,
    endpointKey = "channel_pressure",
  }, true)

  for cc = 0, 127 do
    out[#out + 1] = makeDeviceEndpoint(device, string.format("cc.%d", cc), string.format("CC %d", cc), "scalar_unipolar", "midi_cc", {
      deviceKey = device.key,
      deviceLabel = device.label,
      endpointKey = string.format("cc.%d", cc),
      cc = cc,
    }, true)
  end

  return out
end

return M
