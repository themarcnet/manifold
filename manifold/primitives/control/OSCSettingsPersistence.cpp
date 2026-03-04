#include "OSCSettingsPersistence.h"

juce::File OSCSettingsPersistence::getSettingsFile() {
    auto dir = juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory)
                   .getChildFile("Manifold");
    return dir.getChildFile("settings.json");
}

OSCSettings OSCSettingsPersistence::load() {
    OSCSettings settings;
    
    auto file = getSettingsFile();
    if (!file.existsAsFile()) {
        // No settings file yet, return defaults
        return settings;
    }
    
    auto json = juce::JSON::parse(file);
    if (json.isObject()) {
        auto* obj = json.getDynamicObject();
        
        if (obj->hasProperty("inputPort")) {
            settings.inputPort = obj->getProperty("inputPort");
        }
        if (obj->hasProperty("queryPort")) {
            settings.queryPort = obj->getProperty("queryPort");
        }
        if (obj->hasProperty("oscEnabled")) {
            settings.oscEnabled = obj->getProperty("oscEnabled");
        }
        if (obj->hasProperty("oscQueryEnabled")) {
            settings.oscQueryEnabled = obj->getProperty("oscQueryEnabled");
        }
        if (obj->hasProperty("outTargets")) {
            auto targetsArray = obj->getProperty("outTargets");
            if (targetsArray.isArray()) {
                for (auto& target : *targetsArray.getArray()) {
                    settings.outTargets.add(target.toString());
                }
            }
        }
    }
    
    return settings;
}

bool OSCSettingsPersistence::save(const OSCSettings& settings) {
    auto file = getSettingsFile();
    
    // Ensure directory exists
    if (!file.getParentDirectory().exists()) {
        file.getParentDirectory().createDirectory();
    }
    
    // Build JSON object
    juce::DynamicObject::Ptr obj = new juce::DynamicObject();
    obj->setProperty("inputPort", settings.inputPort);
    obj->setProperty("queryPort", settings.queryPort);
    obj->setProperty("oscEnabled", settings.oscEnabled);
    obj->setProperty("oscQueryEnabled", settings.oscQueryEnabled);
    
    juce::Array<juce::var> targetsArray;
    for (auto& target : settings.outTargets) {
        targetsArray.add(target);
    }
    obj->setProperty("outTargets", targetsArray);
    
    juce::var json(obj);
    auto jsonString = juce::JSON::toString(json, true);
    
    return file.replaceWithText(jsonString);
}

bool OSCSettingsPersistence::resetToDefaults() {
    OSCSettings defaults;
    return save(defaults);
}
