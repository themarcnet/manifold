#pragma once

#include <juce_core/juce_core.h>

/**
 * Path resolution for system and user script directories.
 *
 * SystemScripts: Bundled with the application (read-only)
 * UserScripts: User-created content (read-write)
 */
class SystemPaths {
public:
    /** Get the SystemScripts directory (bundled with app). */
    static juce::File getSystemScriptsDir();

    /** Get the UserScripts directory (user-created). */
    static juce::File getUserScriptsDir();

    /** Get SystemScripts/projects subdirectory. */
    static juce::File getSystemProjectsDir();

    /** Get UserScripts/projects subdirectory. */
    static juce::File getUserProjectsDir();

private:
    SystemPaths() = delete;

    static juce::File getExecutableDir();
    static bool isRunningFromBuildDirectory();
};
