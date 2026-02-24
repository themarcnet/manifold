#include "LooperEditor.h"

LooperEditor::LooperEditor(LooperProcessor &p)
    : juce::AudioProcessorEditor(p), processor(p) {
  setSize(980, 680);

  addAndMakeVisible(rootCanvas);

  // Initialise Lua engine with processor and root canvas
  luaEngine.initialise(&processor, &rootCanvas);

  // Look for looper_ui.lua next to the plugin binary, or in project root
  juce::File scriptFile;
  auto binaryDir =
      juce::File::getSpecialLocation(juce::File::currentExecutableFile)
          .getParentDirectory();
  auto candidate1 = binaryDir.getChildFile("looper_ui.lua");
  auto candidate2 = binaryDir.getParentDirectory().getChildFile("looper_ui.lua");
  auto candidate3 =
      juce::File("/home/shamanic/dev/my-plugin/looper/ui/looper_ui.lua");

  if (candidate1.existsAsFile())
    scriptFile = candidate1;
  else if (candidate2.existsAsFile())
    scriptFile = candidate2;
  else if (candidate3.existsAsFile())
    scriptFile = candidate3;

  if (scriptFile.existsAsFile()) {
    usingLuaUi = luaEngine.loadScript(scriptFile);
    if (usingLuaUi) {
      std::fprintf(stderr, "LooperEditor: Using Lua UI from %s\n",
                   scriptFile.getFullPathName().toRawUTF8());
    } else {
      std::fprintf(stderr, "LooperEditor: Lua script failed: %s\n",
                   luaEngine.getLastError().c_str());
      showError("Lua UI failed to load:\n" + luaEngine.getLastError());
    }
  } else {
    std::fprintf(stderr, "LooperEditor: No looper_ui.lua found\n");
    showError("No looper_ui.lua found.\nSearched:\n  " +
              candidate1.getFullPathName().toStdString() + "\n  " +
              candidate2.getFullPathName().toStdString() + "\n  " +
              candidate3.getFullPathName().toStdString());
  }

  startTimerHz(30);
  resized();
}

void LooperEditor::timerCallback() {
  if (usingLuaUi) {
    luaEngine.notifyUpdate();
    rootCanvas.repaint();
  }
}

void LooperEditor::paint(juce::Graphics &g) {
  juce::ColourGradient bg(juce::Colour(0xff161b26), 0.0f, 0.0f,
                          juce::Colour(0xff0c1019), 0.0f, (float)getHeight(),
                          false);
  bg.addColour(0.35, juce::Colour(0xff1e2533));
  g.setGradientFill(bg);
  g.fillAll();
}

void LooperEditor::resized() {
  rootCanvas.setBounds(getLocalBounds().reduced(12));
  if (usingLuaUi) {
    luaEngine.notifyResized(rootCanvas.getWidth(), rootCanvas.getHeight());
  } else if (errorNode != nullptr) {
    errorNode->setBounds(rootCanvas.getLocalBounds());
  }
}

void LooperEditor::showError(const std::string &message) {
  errorMessage = message;
  rootCanvas.clearChildren();

  errorNode = rootCanvas.addChild("error");
  errorNode->onDraw = [this](Canvas &c, juce::Graphics &g) {
    auto b = c.getLocalBounds().reduced(40);

    g.setColour(juce::Colour(0xff1a0000));
    g.fillRoundedRectangle(b.toFloat(), 12.0f);
    g.setColour(juce::Colour(0xff6b2020));
    g.drawRoundedRectangle(b.toFloat(), 12.0f, 1.5f);

    auto inner = b.reduced(24);

    g.setColour(juce::Colour(0xffef4444));
    g.setFont(juce::Font("Avenir Next", 22.0f, juce::Font::bold));
    g.drawText("Lua UI Error", inner.removeFromTop(32),
               juce::Justification::centredLeft);

    inner.removeFromTop(12);
    g.setColour(juce::Colour(0xffcbd5e1));
    g.setFont(juce::Font("Avenir Next", 13.0f, juce::Font::plain));
    g.drawMultiLineText(juce::String(errorMessage), inner.getX(),
                        inner.getY() + 14, inner.getWidth());
  };
}
