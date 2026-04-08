#pragma once

#include <juce_core/juce_core.h>
#include <string>

/**
 * Persistent settings management for Manifold plugin.
 *
 * Config file selection:
 *  - Repo-local: <repo>/.manifold.settings.json (when running from inside repo)
 *  - User-local: ~/.config/Manifold/settings.json
 */
class Settings {
public:
    static Settings& getInstance();
    
    // Load settings from disk (called on startup)
    void load();
    
    // Save settings to disk (called when settings change)
    void save() const;

    // Resolve the active settings file path.
    juce::String getConfigPath() const { return getConfigFile().getFullPathName(); }
    
    // OSC settings
    int getOscPort() const { return oscPort_; }
    int getOscQueryPort() const { return oscQueryPort_; }
    void setOscPort(int port) { oscPort_ = port; }
    void setOscQueryPort(int port) { oscQueryPort_ = port; }
    
    // UI settings
    juce::String getDefaultUiScript() const {
#ifdef MANIFOLD_DEFAULT_PROJECT
        return juce::String(JUCE_STRINGIFY(MANIFOLD_DEFAULT_PROJECT));
#else
        return defaultUiScript_;
#endif
    }
    void setDefaultUiScript(const juce::String& path) { defaultUiScript_ = path; }
    
    // Development settings
    juce::String getDevScriptsDir() const { return devScriptsDir_; }
    void setDevScriptsDir(const juce::String& path) { devScriptsDir_ = path; }
    
    // User scripts directory (for custom/prototype UIs)
    juce::String getUserScriptsDir() const { return userScriptsDir_; }
    void setUserScriptsDir(const juce::String& path) { userScriptsDir_ = path; }
    
    // DSP scripts directory (for custom DSP nodes)
    juce::String getDspScriptsDir() const { return dspScriptsDir_; }
    void setDspScriptsDir(const juce::String& path) { dspScriptsDir_ = path; }
    
private:
    Settings() = default;
    
    juce::File getConfigFile() const;
    juce::File getConfigDir() const;
    
    // Core settings (not user scripts)
    int oscPort_ = 9000;
    int oscQueryPort_ = 9001;
    
    // Core UI script (looper_ui.lua is core for now)
    juce::String defaultUiScript_;
    
    // Development paths
    juce::String devScriptsDir_;
    
    // User scripts directory
    juce::String userScriptsDir_;
    
    // DSP scripts directory
    juce::String dspScriptsDir_;
    
    bool loaded_ = false;
};
