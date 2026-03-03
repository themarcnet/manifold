#include "Settings.h"

namespace {

bool isRepoRoot(const juce::File& dir) {
    return dir.isDirectory() &&
           dir.getChildFile("CMakeLists.txt").existsAsFile() &&
           dir.getChildFile("looper").isDirectory();
}

juce::File findRepoRoot(juce::File startDir) {
    if (!startDir.isDirectory()) {
        return {};
    }

    while (startDir.isDirectory()) {
        if (isRepoRoot(startDir)) {
            return startDir;
        }

        const auto parent = startDir.getParentDirectory();
        if (parent == startDir) {
            break;
        }
        startDir = parent;
    }

    return {};
}

juce::File detectRepoRoot() {
    const auto cwdRoot = findRepoRoot(juce::File::getCurrentWorkingDirectory());
    if (cwdRoot.isDirectory()) {
        return cwdRoot;
    }

    const auto exeDir = juce::File::getSpecialLocation(juce::File::currentExecutableFile)
                            .getParentDirectory();
    const auto exeRoot = findRepoRoot(exeDir);
    if (exeRoot.isDirectory()) {
        return exeRoot;
    }

    return {};
}

} // namespace

Settings& Settings::getInstance() {
    static Settings instance;
    if (!instance.loaded_) {
        instance.load();
    }
    return instance;
}

juce::File Settings::getConfigDir() const {
    return juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory)
           .getChildFile("Manifold");
}

juce::File Settings::getConfigFile() const {
    const auto repoRoot = detectRepoRoot();
    if (repoRoot.isDirectory()) {
        return repoRoot.getChildFile(".manifold.settings.json");
    }
    return getConfigDir().getChildFile("settings.json");
}

void Settings::load() {
    auto configFile = getConfigFile();
    if (!configFile.existsAsFile()) {
        loaded_ = true;
        return; // Use defaults
    }

    auto json = juce::JSON::parse(configFile);
    if (json.isObject()) {
        auto* obj = json.getDynamicObject();
        
        // OSC settings
        if (obj->hasProperty("oscPort")) {
            oscPort_ = obj->getProperty("oscPort");
        }
        if (obj->hasProperty("oscQueryPort")) {
            oscQueryPort_ = obj->getProperty("oscQueryPort");
        }
        
        // UI settings
        if (obj->hasProperty("defaultUiScript")) {
            defaultUiScript_ = obj->getProperty("defaultUiScript").toString();
        }
        
        // Development settings
        if (obj->hasProperty("devScriptsDir")) {
            devScriptsDir_ = obj->getProperty("devScriptsDir").toString();
        }
        
        // User scripts directory
        if (obj->hasProperty("userScriptsDir")) {
            userScriptsDir_ = obj->getProperty("userScriptsDir").toString();
        }
        
        // DSP scripts directory
        if (obj->hasProperty("dspScriptsDir")) {
            dspScriptsDir_ = obj->getProperty("dspScriptsDir").toString();
        }
    }
    
    loaded_ = true;
}

void Settings::save() const {
    juce::DynamicObject::Ptr obj = new juce::DynamicObject();
    
    // OSC settings
    obj->setProperty("oscPort", oscPort_);
    obj->setProperty("oscQueryPort", oscQueryPort_);
    
    // UI settings
    if (defaultUiScript_.isNotEmpty()) {
        obj->setProperty("defaultUiScript", defaultUiScript_);
    }
    
    // Development settings
    if (devScriptsDir_.isNotEmpty()) {
        obj->setProperty("devScriptsDir", devScriptsDir_);
    }
    
    // User scripts directory
    if (userScriptsDir_.isNotEmpty()) {
        obj->setProperty("userScriptsDir", userScriptsDir_);
    }
    
    // DSP scripts directory
    if (dspScriptsDir_.isNotEmpty()) {
        obj->setProperty("dspScriptsDir", dspScriptsDir_);
    }
    
    auto json = juce::var(obj.get());
    auto configFile = getConfigFile();
    configFile.getParentDirectory().createDirectory();
    configFile.replaceWithText(juce::JSON::toString(json));
}
