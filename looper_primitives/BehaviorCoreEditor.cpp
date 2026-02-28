#include "BehaviorCoreEditor.h"
#include "BehaviorCoreProcessor.h"

#include <cstdio>

BehaviorCoreEditor::BehaviorCoreEditor(BehaviorCoreProcessor& ownerProcessor)
    : juce::AudioProcessorEditor(&ownerProcessor), processorRef(ownerProcessor) {
    setSize(1000, 640);

    addAndMakeVisible(rootCanvas);
    luaEngine.initialise(&processorRef, &rootCanvas);

    juce::File scriptFile;
    auto binaryDir = juce::File::getSpecialLocation(juce::File::currentExecutableFile)
                         .getParentDirectory();
    auto candidate1 = binaryDir.getChildFile("looper_ui.lua");
    auto candidate2 = binaryDir.getParentDirectory().getChildFile("looper_ui.lua");
    auto candidate3 = juce::File("/home/shamanic/dev/my-plugin/looper/ui/looper_ui.lua");

    if (candidate3.existsAsFile())
        scriptFile = candidate3;
    else if (candidate1.existsAsFile())
        scriptFile = candidate1;
    else if (candidate2.existsAsFile())
        scriptFile = candidate2;

    if (scriptFile.existsAsFile()) {
        usingLuaUi = luaEngine.loadScript(scriptFile);
        if (usingLuaUi) {
            std::fprintf(stderr, "BehaviorCoreEditor: Using Lua UI from %s\n",
                         scriptFile.getFullPathName().toRawUTF8());
        } else {
            std::fprintf(stderr, "BehaviorCoreEditor: Lua script failed: %s\n",
                         luaEngine.getLastError().c_str());
            showError("Lua UI failed to load:\n" + luaEngine.getLastError());
        }
    } else {
        showError("No looper_ui.lua found.");
    }

    startTimerHz(30);
    resized();
}

BehaviorCoreEditor::~BehaviorCoreEditor() = default;

void BehaviorCoreEditor::timerCallback() {
    auto pendingPath = processorRef.getAndClearPendingUISwitch();
    if (!pendingPath.empty()) {
        juce::File newScript(pendingPath);
        if (newScript.existsAsFile()) {
            std::fprintf(stderr, "BehaviorCoreEditor: Switching UI to %s\n",
                         pendingPath.c_str());
            luaEngine.switchScript(newScript);
        } else {
            std::fprintf(stderr,
                         "BehaviorCoreEditor: UI switch failed - file not found: %s\n",
                         pendingPath.c_str());
        }
    }

    // Process pending Link tempo requests from main thread
    processorRef.processLinkPendingRequests();

    // Drain any deferred DSP-slot host destruction after UI switch/update.
    // This avoids destroying slot Lua VMs from inside ui_cleanup call stacks.
    processorRef.drainPendingSlotDestroy();

    if (usingLuaUi) {
        luaEngine.notifyUpdate();
        rootCanvas.repaint();
    }
}

void BehaviorCoreEditor::paint(juce::Graphics& g) {
    juce::ignoreUnused(processorRef);

    juce::ColourGradient bg(juce::Colour(0xff161b26), 0.0f, 0.0f,
                            juce::Colour(0xff0c1019), 0.0f, (float)getHeight(), false);
    bg.addColour(0.35, juce::Colour(0xff1e2533));
    g.setGradientFill(bg);
    g.fillAll();
}

void BehaviorCoreEditor::resized() {
    rootCanvas.setBounds(getLocalBounds().reduced(12));
    if (usingLuaUi) {
        luaEngine.notifyResized(rootCanvas.getWidth(), rootCanvas.getHeight());
    } else if (errorNode != nullptr) {
        errorNode->setBounds(rootCanvas.getLocalBounds());
    }
}

void BehaviorCoreEditor::showError(const std::string& message) {
    errorMessage = message;
    rootCanvas.clearChildren();

    errorNode = rootCanvas.addChild("error");
    errorNode->onDraw = [this](Canvas& c, juce::Graphics& g) {
        auto b = c.getLocalBounds().reduced(40);

        g.setColour(juce::Colour(0xff1a0000));
        g.fillRoundedRectangle(b.toFloat(), 12.0f);
        g.setColour(juce::Colour(0xff6b2020));
        g.drawRoundedRectangle(b.toFloat(), 12.0f, 1.5f);

        auto inner = b.reduced(24);

        g.setColour(juce::Colour(0xffef4444));
        g.setFont(20.0f);
        g.drawText("Lua UI Error", inner.removeFromTop(32), juce::Justification::centredLeft);

        inner.removeFromTop(12);
        g.setColour(juce::Colour(0xffcbd5e1));
        g.setFont(13.0f);
        g.drawMultiLineText(juce::String(errorMessage), inner.getX(), inner.getY() + 14,
                            inner.getWidth());
    };
}
