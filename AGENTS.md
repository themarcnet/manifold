

## Build Commands

```bash
# IMPORTANT: For fast iteration, use the dev build directory.
# It avoids LTO/IPO link-time overhead and is dramatically faster.

# Dev (fast iteration)
cmake -S . -B build-dev -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build-dev --target Manifold_Standalone

# Release-style (slow clean links due to LTO)
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target Manifold_Standalone
```

## Running

### Standalone Manifold
```bash
./build-dev/Manifold_artefacts/RelWithDebInfo/Standalone/Manifold
```

### VST3
```bash
./build-dev/Manifold_artefacts/RelWithDebInfo/VST3/Manifold.vst3
```


## IPC + CLI

You have access to the running Application via IPC (Unix domain sockets) and CLI (command line interface). this should give you full observability and control over the application, if there is an area you cannot test, you should add it to the introspection. this enables deep debugging and testing of the application.

## UI System

The UI is entirely Lua-based with two main files:

- `manifold/ui/looper_ui.lua` - **Default UI** (minimal, modern)

### Widget Library (`ui_widgets.lua`)



**Built-in widgets:**
- `BaseWidget` (extendable), `Button`, `Label`, `Panel`
- `Slider`, `VSlider`, `Knob` (rotary), `Toggle`
- `Dropdown`, `WaveformView` (with scrubbing), `Meter`, `SegmentedControl`, `NumberBox`

**Critical:** All coordinates use `math.floor()` to satisfy sol2's strict typing (Lua doubles → C++ ints).


### Tmux Workflow (Long-running Processes)

Use **tmux session Manifold** with **windows 1 and 2** for all long-running commands. if this session doesnt exist create it:

```bash
# Check current sessions
ls -t /tmp/manifold_*.sock

# Capture pane output (before/after commands)
tmux capture-pane -p -t 0:1
tmux capture-pane -p -t 0:2

# Send commands to windows
tmux send-keys -t 0:1 'command here' Enter
tmux send-keys -t 0:2 'make -j$(nproc)' Enter

# Kill/restart standalone
tmux send-keys -t 0:1 C-c
sleep 2
tmux send-keys -t 0:1 './Manifold_artefacts/Release/Standalone/Manifold 2>&1' Enter
```

**Window assignments:**
- **Window 1 (0:1)**: Manifold standalone process
- **Window 2 (0:2)**: Build commands, tests, other processes

**Never use head/tail** on tmux capture output - it obfuscates the shell state.

### JJ Version Control Workflow

This project uses **Jujutsu (jj)** for version control. The working copy is often a merge commit; preserve that shape and split changes out of `@` with `-A`.

```bash
# 1) Inspect state before rewriting
jj st
jj diff --name-only
jj obslog -r @ --limit 20

# 2) Remove build noise first (if present)
jj file untrack build-dev

# 3) Split docs onto docs lineage, code onto code lineage
jj split -r @ -A <docs_parent> -m "docs(scope): description" <docs files...>
jj split -r @ -A <code_parent> -m "feat(scope): description" <code files...>

# 4) Keep splitting @ until only intended remainder (often empty merge)
jj split -r @ -A <latest_code_commit> -m "feat(scope): next chunk" <files...>

# 5) Verify each split and final graph
jj show --name-only <change_id>
jj log -r "@ | @- | @-- | bookmarks()" --limit 20
jj st

# 6) Move docs bookmark when docs split advances
jj bookmark move agent-docs --to <docs_change_id>
```

If you find yourself facing merge conflicts , you are doing it wrong. JJ undo and refer to the above instructions.

**Key points:**
- Use `jj obslog -r @` to understand operation history before and after big rewrites
- Use `jj split -r @ -A <parent>` to insert commits without collapsing the merge working head
- For  Agent focussed documentation, such planning files, PRD etc , split after docs parent and move `agent-docs` bookmark to the new docs commit
- Validate file grouping with `jj show --name-only <change_id>` after each split
- Recovery is cheap: `jj undo` reverts the last operation safely



