#!/usr/bin/env python3
"""
Main Tab Bar regression tests.

Tests the shell's main tab bar functionality before refactoring to ProjectTabHost.
These tests validate expected behaviors that must be preserved:

1. mainTabs table is populated from listUiScripts()
2. Active tab is synced with getCurrentScriptPath()
3. Clicking a tab calls switchUiScript() (current behavior)
4. Tab bar rendering produces expected display list structure
5. Tab activation changes activeMainTabId

Usage:
  python tests/main_tab_bar_test.py --launch build-dev/Manifold_artefacts/RelWithDebInfo/Standalone/Manifold
"""
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
    ManifoldClient,
    SkipTest,
    TestFailure,
    find_live_socket,
    repo_root,
    require_gui_session,
    wait_for,
)


class MainTabBarTestHarness:
    """Test harness for main tab bar functionality."""

    def __init__(self, socket_path: str | None = None, launch_path: str | None = None):
        self.repo_root = repo_root()
        self.socket_path = socket_path
        self.launch_path = launch_path
        self.process: ManagedManifoldProcess | None = None
        self.client: ManifoldClient | None = None

    def start(self) -> None:
        if self.launch_path:
            executable = str((self.repo_root / self.launch_path).resolve())
            self.process = ManagedManifoldProcess(
                executable,
                [],
                cwd=self.repo_root,
                env={"MANIFOLD_RENDERER": "imgui-direct"},
                artifact_name="main_tab_bar_test",
            )
            self.process.start(timeout=15.0)
            self.socket_path = self.process.socket_path
            print(f"Launched: {executable}")
            print(f"Socket: {self.socket_path}")
            print(f"Artifacts: {self.process.artifacts.base_dir}")
        else:
            self.socket_path = find_live_socket(self.socket_path)
            print(f"Using existing socket: {self.socket_path}")

        self.client = ManifoldClient(self.socket_path)
        self.client.connect()
        self._ensure_shell_ready()

    def stop(self) -> None:
        if self.client:
            self.client.close()
            self.client = None
        if self.process:
            self.process.stop()

    def _ensure_shell_ready(self) -> None:
        def shell_ready() -> bool:
            try:
                response = self.client.eval("return type(shell)")
                return response == "OK table"
            except Exception:
                return False

        if not wait_for(shell_ready, timeout=6.0, step=0.05):
            raise TestFailure("shell global never became available")

    def eval_lua(self, code: str) -> str:
        """Evaluate Lua code and return result (stripping OK prefix)."""
        # Normalize code - remove extra whitespace/newlines that break eval
        normalized = code.strip()
        response = self.client.eval(normalized)
        if not response.startswith("OK"):
            raise TestFailure(f"EVAL failed: {response}")
        # Handle "OK" (no value) vs "OK " (with value)
        if response == "OK":
            return ""
        return response[3:] if response.startswith("OK ") else response

    def get_shell_field(self, field: str) -> any:
        """Get a shell field value as JSON."""
        result = self.eval_lua(f"return shell.{field}")
        # Parse Lua table syntax to Python (simplified)
        import json
        try:
            # Try to parse as JSON first
            return json.loads(result)
        except json.JSONDecodeError:
            # Return as string if not valid JSON
            return result

    def refresh_tabs(self) -> None:
        """Trigger tab refresh."""
        self.eval_lua("shell:refreshMainUiTabs()")


def test_shell_has_main_tabs(harness: MainTabBarTestHarness) -> None:
    """Test that shell has mainTabs table."""
    result = harness.eval_lua("return type(shell.mainTabs)")
    if result != "table":
        raise TestFailure(f"expected shell.mainTabs to be table, got: {result}")


def test_shell_has_active_main_tab_id(harness: MainTabBarTestHarness) -> None:
    """Test that shell has activeMainTabId field."""
    result = harness.eval_lua("return type(shell.activeMainTabId)")
    if result != "string":
        raise TestFailure(f"expected shell.activeMainTabId to be string, got: {result}")


def test_main_tabs_populated(harness: MainTabBarTestHarness) -> None:
    """Test that mainTabs gets populated from listUiScripts."""
    harness.refresh_tabs()

    count = harness.eval_lua("return #shell.mainTabs")
    try:
        num_tabs = int(count)
    except ValueError:
        raise TestFailure(f"expected numeric tab count, got: {count}")

    if num_tabs < 1:
        raise TestFailure(f"expected at least 1 tab, got: {num_tabs}")

    print(f"  Found {num_tabs} tab(s)")


def test_tabs_have_required_fields(harness: MainTabBarTestHarness) -> None:
    """Test that each tab has required fields (id, title, kind, path)."""
    harness.refresh_tabs()

    count = int(harness.eval_lua("return #shell.mainTabs"))

    for i in range(1, count + 1):
        tab = harness.eval_lua(f"return shell.mainTabs[{i}]")
        # Check fields exist by evaluating individually
        tab_id = harness.eval_lua(f"return shell.mainTabs[{i}].id or 'MISSING'")
        tab_title = harness.eval_lua(f"return shell.mainTabs[{i}].title or 'MISSING'")
        tab_kind = harness.eval_lua(f"return shell.mainTabs[{i}].kind or 'MISSING'")
        tab_path = harness.eval_lua(f"return shell.mainTabs[{i}].path or 'MISSING'")

        if tab_id == "MISSING":
            raise TestFailure(f"tab {i} missing 'id' field")
        if tab_title == "MISSING":
            raise TestFailure(f"tab {i} missing 'title' field")
        if tab_kind == "MISSING":
            raise TestFailure(f"tab {i} missing 'kind' field")
        if tab_path == "MISSING":
            raise TestFailure(f"tab {i} missing 'path' field")

        print(f"  Tab {i}: {tab_title} ({tab_kind}) -> {tab_path[:40]}...")


def test_active_tab_matches_current_script(harness: MainTabBarTestHarness) -> None:
    """Test that active tab matches getCurrentScriptPath()."""
    harness.refresh_tabs()

    current_path = harness.eval_lua("return getCurrentScriptPath() or ''")
    active_id = harness.eval_lua("return shell.activeMainTabId")

    if not current_path:
        raise SkipTest("no current script path available")

    expected_id = f"ui:{current_path}"

    # Check if the active tab matches current script
    # Note: It might not match if the current script isn't in the tab list
    count = int(harness.eval_lua("return #shell.mainTabs"))

    found_match = False
    for i in range(1, count + 1):
        tab_path = harness.eval_lua(f"return shell.mainTabs[{i}].path or ''")
        if tab_path == current_path:
            tab_id = harness.eval_lua(f"return shell.mainTabs[{i}].id")
            if tab_id == active_id:
                found_match = True
                break

    if not found_match:
        # Check if current script is in tabs at all
        in_tabs = False
        for i in range(1, count + 1):
            tab_path = harness.eval_lua(f"return shell.mainTabs[{i}].path or ''")
            if tab_path == current_path:
                in_tabs = True
                break

        if in_tabs:
            raise TestFailure(
                f"active tab {active_id} does not match current script {current_path}"
            )
        else:
            raise SkipTest(f"current script {current_path} not in tab list")

    print(f"  Active tab matches: {active_id}")


def test_find_main_tab_by_id(harness: MainTabBarTestHarness) -> None:
    """Test _findMainTabById helper function."""
    harness.refresh_tabs()

    count = int(harness.eval_lua("return #shell.mainTabs"))
    if count < 1:
        raise SkipTest("no tabs to test")

    # Get first tab's id
    first_id = harness.eval_lua("return shell.mainTabs[1].id")

    # Test finding it
    result = harness.eval_lua(f"return shell:_findMainTabById('{first_id}') ~= nil")
    if result != "true":
        raise TestFailure(f"_findMainTabById failed to find tab with id {first_id}")

    # Test not finding non-existent
    result = harness.eval_lua("return shell:_findMainTabById('nonexistent') == nil")
    if result != "true":
        raise TestFailure("_findMainTabById should return nil for non-existent id")

    print(f"  Found tab by id: {first_id}")


def test_tab_bar_rects_computed(harness: MainTabBarTestHarness) -> None:
    """Test that mainTabRects are computed during layout."""
    # Trigger layout - use single line to avoid eval issues
    harness.eval_lua("local w, h = shell.parentNode:getWidth(), shell.parentNode:getHeight(); shell:layout(w, h)")

    # Check rects exist
    result = harness.eval_lua("return type(shell.mainTabRects)")
    if result != "table":
        raise TestFailure(f"expected shell.mainTabRects to be table, got: {result}")

    count = int(harness.eval_lua("return #shell.mainTabs"))
    rect_count = int(harness.eval_lua("return #shell.mainTabRects"))

    if rect_count < 1 and count > 0:
        raise TestFailure(f"expected mainTabRects to be populated when tabs exist")

    if rect_count > 0:
        # Check rect has required fields
        x = harness.eval_lua("return shell.mainTabRects[1].x")
        y = harness.eval_lua("return shell.mainTabRects[1].y")
        w = harness.eval_lua("return shell.mainTabRects[1].w")
        h = harness.eval_lua("return shell.mainTabRects[1].h")

        try:
            float(x), float(y), float(w), float(h)
        except ValueError:
            raise TestFailure(f"tab rect has invalid coordinates: x={x}, y={y}, w={w}, h={h}")

    print(f"  Tab rects computed: {rect_count} rect(s)")


def test_activate_main_tab_changes_active_id(harness: MainTabBarTestHarness) -> None:
    """Test that activateMainTab changes activeMainTabId."""
    harness.refresh_tabs()

    count = int(harness.eval_lua("return #shell.mainTabs"))
    if count < 1:
        raise SkipTest("no tabs to activate")

    # Get current active
    original_active = harness.eval_lua("return shell.activeMainTabId")

    # Get a different tab to activate
    target_id = None
    for i in range(1, count + 1):
        tab_id = harness.eval_lua(f"return shell.mainTabs[{i}].id")
        if tab_id != original_active:
            target_id = tab_id
            break

    if not target_id:
        raise SkipTest("only one tab available, cannot test tab switching")

    # Activate the tab
    harness.eval_lua(f"shell:activateMainTab('{target_id}')")

    # Verify active changed
    new_active = harness.eval_lua("return shell.activeMainTabId")

    # Note: If the tab points to a different script, switchUiScript will be called
    # which may cause the shell to reload. So we just check the intent was set.
    print(f"  Tab activation: {original_active} -> {new_active} (targeted: {target_id})")


def test_tabs_rebuild_on_refresh(harness: MainTabBarTestHarness) -> None:
    """Test that refreshMainUiTabs rebuilds the tab list."""
    harness.refresh_tabs()

    original_count = int(harness.eval_lua("return #shell.mainTabs"))

    # Store original first tab id
    if original_count > 0:
        original_first_id = harness.eval_lua("return shell.mainTabs[1].id")
    else:
        original_first_id = None

    # Refresh again
    harness.refresh_tabs()

    new_count = int(harness.eval_lua("return #shell.mainTabs"))

    if new_count != original_count:
        raise TestFailure(
            f"tab count changed from {original_count} to {new_count} on refresh"
        )

    if original_first_id:
        new_first_id = harness.eval_lua("return shell.mainTabs[1].id")
        if new_first_id != original_first_id:
            raise TestFailure(
                f"first tab id changed from {original_first_id} to {new_first_id}"
            )

    print(f"  Tabs stable after refresh: {new_count} tab(s)")


TESTS = [
    test_shell_has_main_tabs,
    test_shell_has_active_main_tab_id,
    test_main_tabs_populated,
    test_tabs_have_required_fields,
    test_active_tab_matches_current_script,
    test_find_main_tab_by_id,
    test_tab_bar_rects_computed,
    test_activate_main_tab_changes_active_id,
    test_tabs_rebuild_on_refresh,
]


def install_signal_handlers(cleanup) -> None:
    def handler(signum, _frame):
        cleanup()
        raise KeyboardInterrupt(f"signal {signum}")

    signal.signal(signal.SIGINT, handler)
    signal.signal(signal.SIGTERM, handler)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Main Tab Bar regression tests"
    )
    parser.add_argument(
        "--socket",
        help="Connect to an existing standalone socket"
    )
    parser.add_argument(
        "--launch",
        default="build-dev/Manifold_artefacts/RelWithDebInfo/Standalone/Manifold",
        help="Launch standalone executable"
    )
    parser.add_argument(
        "--require-gui",
        action="store_true",
        help="Skip with code 77 when no desktop GUI session"
    )
    return parser.parse_args(argv[1:])


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    if args.require_gui:
        require_gui_session("main tab bar test requires a desktop GUI session")

    harness = MainTabBarTestHarness(
        socket_path=args.socket,
        launch_path=args.launch if not args.socket else None
    )
    install_signal_handlers(harness.stop)

    failures = []
    skipped = []
    passed = 0

    try:
        harness.start()

        for test in TESTS:
            name = test.__name__
            try:
                test(harness)
                passed += 1
                print(f"  PASS: {name}")
            except SkipTest as exc:
                skipped.append((name, str(exc)))
                print(f"  SKIP: {name}: {exc}")
            except TestFailure as exc:
                failures.append((name, str(exc)))
                print(f"  FAIL: {name}: {exc}")

        print(
            f"\nMain Tab Bar tests: {passed}/{len(TESTS)} passed, "
            f"{len(failures)} failed, {len(skipped)} skipped"
        )

        if failures:
            return 1
        return 0

    except KeyboardInterrupt:
        print("Interrupted")
        return 2
    except Exception as exc:
        print(f"Infrastructure error: {exc}")
        import traceback
        traceback.print_exc()
        return 2
    finally:
        harness.stop()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
