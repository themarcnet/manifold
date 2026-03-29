#!/usr/bin/env bash
set -euo pipefail

SOCKET=$(ls -t /tmp/manifold_*.sock | tr '\n' ' ' | awk '{print $1}')
if [ -z "${SOCKET:-}" ]; then
  echo "ERROR no manifold socket found"
  exit 1
fi

send_ipc() {
  local command_text="$1"
  SOCKET_PATH="$SOCKET" IPC_COMMAND="$command_text" python3 - <<'PY'
import os
import socket

sock_path = os.environ["SOCKET_PATH"]
command = os.environ["IPC_COMMAND"] + "\n"

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(2.0)
client.connect(sock_path)
client.sendall(command.encode("utf-8"))
chunks = []
while True:
    try:
        data = client.recv(4096)
    except socket.timeout:
        break
    if not data:
        break
    chunks.append(data)
    if b"\n" in data:
        break
client.close()
print(b"".join(chunks).decode("utf-8", errors="replace").strip())
PY
}

expect_ok_prefix() {
  local response="$1"
  case "$response" in
    OK\ *) ;;
    *)
      echo "ERROR unexpected response: $response"
      exit 1
      ;;
  esac
}

spawn_new_dynamic() {
  local entry_id="$1"
  local spec_id="$2"
  local response
  response=$(send_ipc "EVAL local before={} for id,entry in pairs(__midiSynthDynamicModuleInfo or {}) do if type(entry)=='table' and tostring(entry.specId or '')=='$spec_id' then before[id]=true end end local ok = __midiSynthSpawnPaletteNode and __midiSynthSpawnPaletteNode('$entry_id', 3, 1, false) local newId='' local slot='' local base='' for id,entry in pairs(__midiSynthDynamicModuleInfo or {}) do if type(entry)=='table' and tostring(entry.specId or '')=='$spec_id' and not before[id] then newId=id slot=tostring(entry.slotIndex or '') base=tostring(entry.paramBase or '') break end end return string.format('%s|%s|%s|%s', tostring(ok), newId, slot, base)")
  expect_ok_prefix "$response"
  printf '%s\n' "${response#OK }"
}

delete_dynamic() {
  local node_id="$1"
  local response
  response=$(send_ipc "EVAL local ok = __midiSynthDeleteRackNode and __midiSynthDeleteRackNode('$node_id') local infoGone = ((__midiSynthDynamicModuleInfo or {})['$node_id'] == nil) local specGone = ((__midiSynthDynamicModuleSpecs or {})['$node_id'] == nil) return string.format('%s|%s|%s', tostring(ok), tostring(infoGone), tostring(specGone))")
  expect_ok_prefix "$response"
  printf '%s\n' "${response#OK }"
}

project_response=$(send_ipc "EVAL return getCurrentScriptPath()")
expect_ok_prefix "$project_response"
case "$project_response" in
  "OK /home/shamanic/dev/my-plugin/UserScripts/projects/Main/manifold.project.json5"*) ;;
  *)
    echo "ERROR unexpected current project response"
    exit 1
    ;;
esac

arp_spawn_1=$(spawn_new_dynamic "arp" "arp")
IFS='|' read -r arp_ok_1 arp_node_1 arp_slot_1 arp_base_1 <<< "$arp_spawn_1"
assert_arp_base="/midi/synth/rack/arp/$arp_slot_1"
if [ "$arp_ok_1" != "true" ] || [ -z "$arp_node_1" ] || [ -z "$arp_slot_1" ] || [ "$arp_base_1" != "$assert_arp_base" ]; then
  echo "ERROR arp spawn 1 failed: $arp_spawn_1"
  exit 1
fi

arp_delete_1=$(delete_dynamic "$arp_node_1")
IFS='|' read -r arp_del_ok_1 arp_info_gone_1 arp_spec_gone_1 <<< "$arp_delete_1"
if [ "$arp_del_ok_1" != "true" ] || [ "$arp_info_gone_1" != "true" ] || [ "$arp_spec_gone_1" != "true" ]; then
  echo "ERROR arp delete 1 failed: $arp_delete_1"
  exit 1
fi

arp_spawn_2=$(spawn_new_dynamic "arp" "arp")
IFS='|' read -r arp_ok_2 arp_node_2 arp_slot_2 arp_base_2 <<< "$arp_spawn_2"
if [ "$arp_ok_2" != "true" ] || [ -z "$arp_node_2" ] || [ "$arp_slot_2" != "$arp_slot_1" ] || [ "$arp_base_2" != "/midi/synth/rack/arp/$arp_slot_2" ]; then
  echo "ERROR arp spawn 2 failed or slot not reused: $arp_spawn_2"
  exit 1
fi

arp_delete_2=$(delete_dynamic "$arp_node_2")
IFS='|' read -r arp_del_ok_2 arp_info_gone_2 arp_spec_gone_2 <<< "$arp_delete_2"
if [ "$arp_del_ok_2" != "true" ] || [ "$arp_info_gone_2" != "true" ] || [ "$arp_spec_gone_2" != "true" ]; then
  echo "ERROR arp delete 2 failed: $arp_delete_2"
  exit 1
fi

transpose_spawn=$(spawn_new_dynamic "transpose" "transpose")
IFS='|' read -r transpose_ok transpose_node transpose_slot transpose_base <<< "$transpose_spawn"
if [ "$transpose_ok" != "true" ] || [ -z "$transpose_node" ] || [ -z "$transpose_slot" ] || [ "$transpose_base" != "/midi/synth/rack/transpose/$transpose_slot" ]; then
  echo "ERROR transpose spawn failed: $transpose_spawn"
  exit 1
fi

transpose_delete=$(delete_dynamic "$transpose_node")
IFS='|' read -r transpose_del_ok transpose_info_gone transpose_spec_gone <<< "$transpose_delete"
if [ "$transpose_del_ok" != "true" ] || [ "$transpose_info_gone" != "true" ] || [ "$transpose_spec_gone" != "true" ]; then
  echo "ERROR transpose delete failed: $transpose_delete"
  exit 1
fi

osc_spawn=$(spawn_new_dynamic "rack_oscillator" "rack_oscillator")
IFS='|' read -r osc_ok osc_node osc_slot osc_base <<< "$osc_spawn"
if [ "$osc_ok" != "true" ] || [ -z "$osc_node" ] || [ -z "$osc_slot" ] || [ "$osc_base" != "/midi/synth/rack/osc/$osc_slot" ]; then
  echo "ERROR oscillator spawn failed: $osc_spawn"
  exit 1
fi

osc_delete=$(delete_dynamic "$osc_node")
IFS='|' read -r osc_del_ok osc_info_gone osc_spec_gone <<< "$osc_delete"
if [ "$osc_del_ok" != "true" ] || [ "$osc_info_gone" != "true" ] || [ "$osc_spec_gone" != "true" ]; then
  echo "ERROR oscillator delete failed: $osc_delete"
  exit 1
fi

echo "OK rack_module_factory ipc smoke"
