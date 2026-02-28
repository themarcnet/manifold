#include "TempusEditor.h"
#include "TempusPlugin.h"

#include <cstdio>

TempusEditor::TempusEditor(juce::AudioProcessor* ownerProcessor, TempusPlugin& plugin)
    : juce::AudioProcessorEditor(ownerProcessor), processorRef(plugin) {
    setSize(420, 320);  // Wider aspect ratio, shorter height

    addAndMakeVisible(rootCanvas);
    luaEngine.initialise(&processorRef, &rootCanvas);

    // Find UI script
    juce::File scriptFile;
    auto binaryDir = juce::File::getSpecialLocation(juce::File::currentExecutableFile)
                         .getParentDirectory();
    auto candidate1 = binaryDir.getChildFile("firstloop_ui.lua");
    auto candidate2 = binaryDir.getParentDirectory().getChildFile("firstloop_ui.lua");
    auto candidate3 = juce::File::getCurrentWorkingDirectory()
                         .getChildFile("test_plugins/Tempus/firstloop_ui.lua");

    if (candidate3.existsAsFile())
        scriptFile = candidate3;
    else if (candidate1.existsAsFile())
        scriptFile = candidate1;
    else if (candidate2.existsAsFile())
        scriptFile = candidate2;

    if (scriptFile.existsAsFile()) {
        usingLuaUi = luaEngine.loadScript(scriptFile);
        if (usingLuaUi) {
            std::fprintf(stderr, "TempusEditor: Using Lua UI from %s\n",
                         scriptFile.getFullPathName().toRawUTF8());
        } else {
            std::fprintf(stderr, "TempusEditor: Lua script failed: %s\n",
                         luaEngine.getLastError().c_str());
            showError("Lua UI failed to load:\n" + luaEngine.getLastError());
        }
    } else {
        showError("No firstloop_ui.lua found.\nSearched:\n" +
                  candidate1.getFullPathName().toStdString() + "\n" +
                  candidate2.getFullPathName().toStdString() + "\n" +
                  candidate3.getFullPathName().toStdString());
    }

    startTimerHz(30);
    resized();
}

TempusEditor::~TempusEditor() = default;

void TempusEditor::timerCallback() {
    // Process Link tempo requests
    processorRef.processLinkPendingRequests();
    
    // Poll Link for peer updates (since we have no audio thread)
    processorRef.processPendingChanges();

    if (usingLuaUi) {
        luaEngine.notifyUpdate();
        rootCanvas.repaint();
    }
}

void TempusEditor::paint(juce::Graphics& g) {
    juce::ColourGradient bg(juce::Colour(0xff161b26), 0.0f, 0.0f,
                            juce::Colour(0xff0c1019), 0.0f, (float)getHeight(), false);
    bg.addColour(0.35, juce::Colour(0xff1e2533));
    g.setGradientFill(bg);
    g.fillAll();
}

void TempusEditor::resized() {
    rootCanvas.setBounds(getLocalBounds());
    if (usingLuaUi) {
        luaEngine.notifyResized(rootCanvas.getWidth(), rootCanvas.getHeight());
    } else if (errorNode != nullptr) {
        errorNode->setBounds(rootCanvas.getLocalBounds());
    }
}

void TempusEditor::showError(const std::string& message) {
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
        g.drawText("UI Error", inner.removeFromTop(32), juce::Justification::centredLeft);

        inner.removeFromTop(12);
        g.setColour(juce::Colour(0xffcbd5e1));
        g.setFont(13.0f);
        g.drawMultiLineText(juce::String(errorMessage), inner.getX(), inner.getY() + 14,
                            inner.getWidth());
    };
}
