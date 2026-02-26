#!/usr/bin/env python3

import glob
import json
import socket
import time
import urllib.request


def send_command(socket_path: str, command: str) -> str:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(socket_path)
        client.sendall((command + "\n").encode("utf-8"))
        data = b""
        while not data.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk
        return data.decode("utf-8", errors="replace").strip()


def query_diagnostics(socket_path: str) -> dict:
    raw = send_command(socket_path, "DIAGNOSTICS")
    if not raw.startswith("OK "):
        raise RuntimeError(f"DIAGNOSTICS failed: {raw}")
    return json.loads(raw[3:])


def main() -> int:
    sockets = sorted(glob.glob("/tmp/looper_*.sock"))
    if not sockets:
        raise RuntimeError("No /tmp/looper_*.sock sockets found")

    socket_path = sockets[-1]
    print(f"socket: {socket_path}")

    before = query_diagnostics(socket_path)
    print(f"before legacySyntaxTotal: {before.get('legacySyntaxTotal')}")

    canonical_commands = [
        "SET /looper/tempo 134",
        "SET /looper/mode freeMode",
        "SET /looper/layer 1",
        "SET /looper/layer/1/speed 0.77",
        "SET /looper/layer/1/reverse 1",
        "SET /looper/layer/1/volume 0.63",
        "TRIGGER /looper/play",
        "GET /looper/tempo",
    ]

    print("--- canonical phase ---")
    for command in canonical_commands:
        print(f"{command} => {send_command(socket_path, command)[:120]}")

    time.sleep(0.25)
    after_canonical = query_diagnostics(socket_path)
    canonical_delta = after_canonical.get("legacySyntaxTotal", 0) - before.get(
        "legacySyntaxTotal", 0
    )
    print(
        f"after canonical legacySyntaxTotal: {after_canonical.get('legacySyntaxTotal')}"
    )
    print(f"canonical delta legacySyntaxTotal: {canonical_delta}")
    if canonical_delta != 0:
        raise RuntimeError(
            f"Expected canonical legacySyntaxTotal delta 0, got {canonical_delta}"
        )

    legacy_commands = [
        "TEMPO 137",
        "MODE traditional",
        "LAYER 2 SPEED 1.2",
        "STOP",
    ]

    print("--- legacy phase ---")
    for command in legacy_commands:
        print(f"{command} => {send_command(socket_path, command)[:120]}")

    time.sleep(0.25)
    after_legacy = query_diagnostics(socket_path)
    legacy_delta = after_legacy.get("legacySyntaxTotal", 0) - after_canonical.get(
        "legacySyntaxTotal", 0
    )
    print(f"after legacy legacySyntaxTotal: {after_legacy.get('legacySyntaxTotal')}")
    print(f"legacy delta legacySyntaxTotal: {legacy_delta}")
    if legacy_delta < len(legacy_commands):
        raise RuntimeError(
            "Expected legacy syntax counter to increase for deprecated commands"
        )

    for key in [
        "legacyVerbTempo",
        "legacyVerbMode",
        "legacyVerbLayer",
        "legacyVerbStop",
    ]:
        delta = after_legacy.get(key, 0) - after_canonical.get(key, 0)
        print(f"{key} delta: {delta}")
        if delta < 1:
            raise RuntimeError(f"Expected {key} delta >= 1, got {delta}")

    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:9001/osc/looper/diagnostics", timeout=2
        ) as response:
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
        value = payload.get("VALUE", {})
        print(
            f"oscquery diagnostics legacySyntaxTotal: {value.get('legacySyntaxTotal')}"
        )
    except Exception as error:  # pragma: no cover - network path
        print(f"oscquery diagnostics query failed: {error}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
