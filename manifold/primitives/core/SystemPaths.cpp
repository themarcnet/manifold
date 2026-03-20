#include "SystemPaths.h"

#include <juce_core/juce_core.h>

juce::File SystemPaths::getExecutableDir() {
    return juce::File::getSpecialLocation(juce::File::currentExecutableFile)
        .getParentDirectory();
}

bool SystemPaths::isRunningFromBuildDirectory() {
    // Check for build directory markers
    auto exeDir = getExecutableDir();

    // Look for CMakeFiles or typical build artifacts next to executable
    if (exeDir.getChildFile("CMakeFiles").exists() ||
        exeDir.getChildFile("cmake_install.cmake").exists()) {
        return true;
    }

    // Check if we're in a CMake build subdirectory (e.g., build/Manifold_artefacts/...)
    // Search up several levels for CMakeCache.txt
    auto dir = exeDir;
    for (int i = 0; i < 5; ++i) {
        if (dir.getChildFile("CMakeCache.txt").exists()) {
            return true;
        }
        dir = dir.getParentDirectory();
    }

    return false;
}

juce::File SystemPaths::getSystemScriptsDir() {
    auto exeDir = getExecutableDir();

    // If running from build directory, CMake copies SystemScripts to the build output dir
    // which is typically the parent of the executable's directory
    if (isRunningFromBuildDirectory()) {
        // First check parent directory (where CMake copies to for standalone builds)
        auto parentDir = exeDir.getParentDirectory();
        auto parentSystemScripts = parentDir.getChildFile("SystemScripts");
        if (parentSystemScripts.exists()) {
            return parentSystemScripts;
        }

        // Then try to find source root (look for CMakeLists.txt with manifold/ subdirectory)
        auto dir = exeDir;
        for (int i = 0; i < 8; ++i) {  // Search up 8 levels (deep build dirs)
            if (dir.getChildFile("manifold/SystemScripts").exists()) {
                return dir.getChildFile("manifold/SystemScripts");
            }
            if (dir.getChildFile("CMakeLists.txt").exists() && 
                dir.getChildFile("manifold").exists()) {
                auto systemScripts = dir.getChildFile("manifold/SystemScripts");
                if (systemScripts.exists()) {
                    return systemScripts;
                }
            }
            dir = dir.getParentDirectory();
        }
    }

    // Otherwise, use executable-relative path
    // SystemScripts should be next to the executable or in Resources (macOS)
    auto systemScripts = exeDir.getChildFile("SystemScripts");
    if (systemScripts.exists()) {
        return systemScripts;
    }

    // macOS app bundle: Manifold.app/Contents/Resources/SystemScripts
    auto resourcesDir = exeDir.getParentDirectory().getChildFile("Resources");
    systemScripts = resourcesDir.getChildFile("SystemScripts");
    if (systemScripts.exists()) {
        return systemScripts;
    }

    // Fallback: executable directory
    return exeDir.getChildFile("SystemScripts");
}

juce::File SystemPaths::getUserScriptsDir() {
    // Use Settings to get the configured user scripts directory
    // For now, fall back to standard locations

    // Check for UserScripts next to executable (dev mode)
    auto exeDir = getExecutableDir();
    auto userScripts = exeDir.getChildFile("UserScripts");
    if (userScripts.exists()) {
        return userScripts;
    }

    // Standard user data location
    auto userAppData = juce::File::getSpecialLocation(
        juce::File::userApplicationDataDirectory);

#if JUCE_MAC
    auto appDataDir = userAppData.getChildFile("Application Support/Manifold");
#elif JUCE_WINDOWS
    auto appDataDir = userAppData.getChildFile("Manifold");
#else
    auto appDataDir = userAppData.getChildFile("manifold");
#endif

    return appDataDir.getChildFile("UserScripts");
}

juce::File SystemPaths::getSystemProjectsDir() {
    return getSystemScriptsDir().getChildFile("projects");
}

juce::File SystemPaths::getUserProjectsDir() {
    return getUserScriptsDir().getChildFile("projects");
}
