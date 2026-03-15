#!/usr/bin/env python3
from __future__ import annotations

import argparse
import signal
import sys
import time
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from harness import (  # noqa: E402
    ManagedManifoldProcess,
    TestFailure,
    repo_root,
    wait_for,
)


class EditorE2EHarness:
    def __init__(self, headless_path: str, duration: float, sample_rate: float, block_size: int):
        self.repo_root = repo_root()
        binary_path = (self.repo_root / headless_path).resolve()
        self.process = ManagedManifoldProcess(
            binary_path,
            [
                "--duration",
                str(duration),
                "--blocksize",
                str(block_size),
                "--samplerate",
                str(sample_rate),
                "--test-ui",
            ],
            cwd=self.repo_root,
            artifact_name="headless_editor_e2e",
        )
        self.client = None

    def start(self) -> None:
        print("Starting ManifoldHeadless editor harness...")
        self.process.start(timeout=12.0)
        self.client = self.process.create_client()
        print(f"Socket found: {self.process.socket_path}")
        print(f"Artifacts: {self.process.artifacts.base_dir}")

        def lua_ready() -> bool:
            return self.client.command("EVAL return 1") == "OK 1"

        if not wait_for(lua_ready, timeout=4.0, step=0.05):
            raise TestFailure("lua engine never became ready")

    def stop(self) -> None:
        if self.client is not None:
            self.client.close()
            self.client = None
        self.process.stop()

    def write_failure_artifacts(self) -> None:
        try:
            self.process.artifacts.write_json("diagnose.json", self.client.diagnose_payload())
        except Exception:
            pass
        try:
            self.process.artifacts.write_json("state.json", self.client.state())
        except Exception:
            pass


TEST_SCRIPT_SWITCHES = [
    "manifold/ui/manifold_settings_ui.lua",
    "UserScripts/projects/DspLiveScripting/manifold.project.json5",
]


def require_ok(response: str, message: str) -> None:
    if not response.startswith("OK"):
        raise TestFailure(f"{message}: {response}")


def wait_for_renderer(harness: EditorE2EHarness, mode: str, timeout: float = 3.0) -> None:
    def predicate() -> bool:
        payload = harness.client.diagnose_payload()
        return payload.get("uiRendererMode") == mode

    if not wait_for(predicate, timeout=timeout, step=0.05):
        payload = harness.client.diagnose_payload()
        raise TestFailure(f"renderer mode did not become {mode!r}: {payload.get('uiRendererMode')!r}")


def wait_for_log_fragment(harness: EditorE2EHarness, fragment: str, timeout: float = 3.0) -> None:
    if not wait_for(lambda: fragment in harness.process.get_log_text(), timeout=timeout, step=0.05):
        raise TestFailure(f"log fragment did not appear: {fragment!r}")


def test_ping(harness: EditorE2EHarness) -> None:
    response = harness.client.command("PING")
    if response != "OK PONG":
        raise TestFailure(f"expected OK PONG, got {response}")


def test_eval_available(harness: EditorE2EHarness) -> None:
    response = harness.client.eval("return 6*7")
    if response != "OK 42":
        raise TestFailure(f"expected OK 42, got {response}")


def test_shell_available(harness: EditorE2EHarness) -> None:
    response = harness.client.eval("return type(shell)")
    if response != "OK table":
        raise TestFailure(f"expected shell global table, got {response}")

    mode_response = harness.client.eval("return type(shell.setMode)")
    if mode_response != "OK function":
        raise TestFailure(f"expected shell.setMode function, got {mode_response}")


def test_frame_timing_available(harness: EditorE2EHarness) -> None:
    harness.client.reset_perf()

    def predicate() -> bool:
        frame_timing = harness.client.frame_timing()
        return int(frame_timing.get("frameCount", 0)) > 0

    if not wait_for(predicate, timeout=2.0, step=0.05):
        frame_timing = harness.client.frame_timing()
        raise TestFailure(f"frame timing never advanced: {frame_timing}")

    payload = harness.client.diagnose_payload()
    if "imgui" not in payload:
        raise TestFailure(f"DIAGNOSE missing imgui block: {payload}")


def test_renderer_switch_direct(harness: EditorE2EHarness) -> None:
    response = harness.client.command("UIRENDERER imgui-direct")
    require_ok(response, "UIRENDERER imgui-direct failed")
    wait_for_renderer(harness, "imgui-direct")


def test_legacy_script_switches_in_direct(harness: EditorE2EHarness) -> None:
    wait_for_renderer(harness, "imgui-direct")
    for relative in TEST_SCRIPT_SWITCHES:
        script_path = harness.repo_root / relative
        if not script_path.exists():
            raise TestFailure(f"missing test script: {script_path}")
        response = harness.client.command(f"UISWITCH {script_path}")
        require_ok(response, f"UISWITCH failed for {script_path}")
        wait_for_log_fragment(harness, f"LuaEngine: loaded script: {script_path}")
        shell_response = harness.client.eval("return type(shell)")
        if shell_response != "OK table":
            raise TestFailure(f"shell unavailable after switching to {script_path}: {shell_response}")


def test_renderer_switch_back_canvas(harness: EditorE2EHarness) -> None:
    response = harness.client.command("UIRENDERER canvas")
    require_ok(response, "UIRENDERER canvas failed")
    wait_for_renderer(harness, "canvas")


def test_perf_reset_live_editor(harness: EditorE2EHarness) -> None:
    harness.client.reset_perf()
    time.sleep(0.2)
    frame_timing = harness.client.frame_timing()
    peak_total = frame_timing.get("peakTotalUs")
    if peak_total is None:
        raise TestFailure(f"frameTiming missing peakTotalUs: {frame_timing}")
    if int(frame_timing.get("frameCount", 0)) <= 0:
        raise TestFailure(f"frame count did not advance after PERF RESET: {frame_timing}")


TESTS = [
    test_ping,
    test_eval_available,
    test_shell_available,
    test_frame_timing_available,
    test_renderer_switch_direct,
    test_legacy_script_switches_in_direct,
    test_renderer_switch_back_canvas,
    test_perf_reset_live_editor,
]


def install_signal_handlers(cleanup) -> None:
    def handler(signum, _frame):
        cleanup()
        raise KeyboardInterrupt(f"signal {signum}")

    signal.signal(signal.SIGINT, handler)
    signal.signal(signal.SIGTERM, handler)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Editor-enabled headless IPC regression suite")
    parser.add_argument("--headless", default="build-dev/ManifoldHeadless", help="Path to ManifoldHeadless executable")
    parser.add_argument("--duration", type=float, default=30.0, help="Headless runtime duration in seconds")
    parser.add_argument("--samplerate", type=float, default=44100.0, help="Sample rate")
    parser.add_argument("--blocksize", type=int, default=512, help="Block size")
    return parser.parse_args(argv[1:])


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    harness = EditorE2EHarness(args.headless, args.duration, args.samplerate, args.blocksize)
    install_signal_handlers(harness.stop)

    failures = []
    passed = 0

    try:
        harness.start()
        for test in TESTS:
            name = test.__name__
            try:
                test(harness)
                passed += 1
                print(f"  PASS: {name}")
            except TestFailure as exc:
                failures.append((name, str(exc)))
                print(f"  FAIL: {name}: {exc}")

        print(f"Headless editor IPC tests: {passed}/{len(TESTS)} passed, {len(failures)} failed")
        if failures:
            harness.write_failure_artifacts()
            log_tail = harness.process.get_log_tail()
            if log_tail:
                print("\nManifoldHeadless log tail:")
                print(log_tail)
            print(f"Artifacts: {harness.process.artifacts.base_dir}")
            return 1
        return 0
    except KeyboardInterrupt:
        print("Interrupted")
        return 2
    except Exception as exc:
        harness.write_failure_artifacts()
        print(f"Infrastructure error: {exc}")
        log_tail = harness.process.get_log_tail()
        if log_tail:
            print("\nManifoldHeadless log tail:")
            print(log_tail)
        print(f"Artifacts: {harness.process.artifacts.base_dir}")
        return 2
    finally:
        harness.stop()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
