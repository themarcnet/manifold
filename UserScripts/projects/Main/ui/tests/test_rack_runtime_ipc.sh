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

project_response=$(send_ipc "EVAL return getCurrentScriptPath()")
printf '%s\n' "$project_response"
case "$project_response" in
  "OK /home/shamanic/dev/my-plugin/UserScripts/projects/Main/manifold.project.json5"*) ;;
  *)
    echo "ERROR unexpected current project response"
    exit 1
    ;;
esac

rack_response=$(send_ipc "EVAL return string.format('%s|%s|%s', type(__midiSynthRackState), type(__midiSynthRackConnections), type(__midiSynthUtilityDock))")
printf '%s\n' "$rack_response"
case "$rack_response" in
  "OK table|table|table"*) ;;
  *)
    echo "ERROR rack globals not exposed as expected"
    exit 1
    ;;
esac

echo "OK rack runtime ipc smoke"
