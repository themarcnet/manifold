# SystemScripts Proposal

**Date:** 2026-03-20  
**Context:** System vs User project organization

---

## Current State

System-level functionality (Settings) lives in user space:

```
UserScripts/
  projects/
    Settings/          # System config, but in user land
    Main/              # Actual user project
    DspLiveScripting/  # Demo project
```

This is conceptually wrong - Settings configures the system (OSC ports, MIDI devices, Link, paths) but lives alongside user-created projects.

---

## Proposed Structure

Parallel hierarchy to UserScripts:

```
manifold/
  SystemScripts/
    projects/
      Settings/          # OSC, Link, MIDI, paths configuration
      Welcome/           # First-run experience (optional)
      Template/          # Starter project for "new project" command
    dsp/                 # System DSP modules (if needed)
    themes/              # Built-in themes (dark, light, high-contrast)
    ui/                  # System UI components (if distinct from shell)

UserScripts/
  projects/              # Only user-created projects
    Main/
    MyCustomLooper/
  dsp/                   # User DSP modules
  themes/                # User themes
```

---

## Key Points

1. **Settings stays a project** - The project format is good. Declarative UI, behavior separation, hot-reload - all of this works well for system configuration.

2. **SystemScripts is read-only** - These are bundled with the app, not user-modifiable. Users can copy them to UserScripts if they want to fork.

3. **Project loader checks both** - System projects appear in the script list, possibly tagged or in a separate section.

4. **Extensible** - Other folders can be added to SystemScripts as needed (behaviors, components, etc.).

---

## Integration

### Project Discovery

```lua
-- In project_loader.lua or equivalent
local function discoverProjects()
  local projects = {}
  
  -- System projects first
  local systemRoot = getSystemScriptsDir() .. "/projects"
  for _, dir in ipairs(listDirectories(systemRoot)) do
    table.insert(projects, {
      path = dir,
      name = readProjectName(dir),
      type = "system",  -- Marked as system
      readOnly = true
    })
  end
  
  -- User projects
  local userRoot = getUserScriptsDir() .. "/projects"
  for _, dir in ipairs(listDirectories(userRoot)) do
    table.insert(projects, {
      path = dir,
      name = readProjectName(dir),
      type = "user",
      readOnly = false
    })
  end
  
  return projects
end
```

### UI Indication

System projects could show:
- Different icon (lock or gear)
- "System" badge
- Separate section in dropdown
- No "delete" option

---

## Future System Projects

| Project | Purpose |
|---------|---------|
| Settings | OSC/Link/MIDI/Paths configuration |
| Welcome | First-run onboarding, tutorial |
| Template | Base project for "new project" command |
| Diagnostics | Audio/MIDI test signals, latency checker |
| Calibration | Input gain staging, monitor calibration |

---

## Migration

1. Create `manifold/SystemScripts/` directory
2. Move `UserScripts/projects/Settings/` → `manifold/SystemScripts/projects/Settings/`
3. Update project loader to check both locations
4. Update build scripts to bundle SystemScripts
5. (Optional) Add UI indication for system vs user projects

---

## Relation to Shell

The shell remains the host. SystemScripts are just projects that ship with the system rather than created by users. The shell doesn't care - it loads whatever the project loader gives it.

This keeps the boundary clean:
- **Shell**: The app, the chrome, the dev tools
- **SystemScripts**: Bundled content (settings, templates, etc.)
- **UserScripts**: User-created content
