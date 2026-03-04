#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>
#include "CanvasStyle.h"
#include <functional>
#include <memory>

class Canvas : public juce::Component, public juce::OpenGLRenderer {
public:
    Canvas(const juce::String& name = "Canvas");
    ~Canvas() override;
    
    CanvasStyle style;
    
    // Standard 2D rendering callback
    std::function<void(Canvas&, juce::Graphics&)> onDraw;
    
    // OpenGL rendering callbacks
    std::function<void(Canvas&)> onGLRender;
    std::function<void(Canvas&)> onGLContextCreated;
    std::function<void(Canvas&)> onGLContextClosing;
    
    // Input callbacks
    std::function<void(const juce::MouseEvent&)> onMouseDown;
    std::function<void(const juce::MouseEvent&)> onMouseDrag;
    std::function<void(const juce::MouseEvent&)> onMouseUp;
    std::function<void(const juce::MouseEvent&)> onMouseMove;
    std::function<void(const juce::MouseEvent&, const juce::MouseWheelDetails&)> onMouseWheel;
    std::function<bool(const juce::KeyPress&)> onKeyPress;
    std::function<void()> onClick;
    std::function<void()> onDoubleClick;
    std::function<void()> onMouseEnter;
    std::function<void()> onMouseExit;
    std::function<void(float)> onValueChanged;
    std::function<void(bool)> onToggled;
    
    // Input setter methods (callable from Lua)
    void setOnMouseWheel(std::function<void(const juce::MouseEvent&, const juce::MouseWheelDetails&)> fn) { onMouseWheel = fn; }
    
    // Enable/disable OpenGL rendering
    void setOpenGLEnabled(bool enabled);
    bool isOpenGLEnabled() const { return openGLEnabled; }
    
    // Get the OpenGL context (valid only when OpenGL is enabled)
    juce::OpenGLContext* getOpenGLContext() { return glContext.get(); }
    
    // Standard 2D paint
    void paint(juce::Graphics& g) override;
    
    // OpenGLRenderer callbacks
    void newOpenGLContextCreated() override;
    void renderOpenGL() override;
    void openGLContextClosing() override;
    
    // Input handling
    void mouseDown(const juce::MouseEvent& e) override;
    void mouseDrag(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;
    void mouseMove(const juce::MouseEvent& e) override;
    void mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) override;
    bool keyPressed(const juce::KeyPress& key) override;
    
    // Component lifecycle
    void visibilityChanged() override;
    void resized() override;
    void parentHierarchyChanged() override;
    
    void setStyle(const CanvasStyle& s);
    
    Canvas* addChild(const juce::String& childName = "child");
    void removeChild(Canvas* child);
    void clearChildren();
    
    int getNumChildren() const { return children.size(); }
    Canvas* getChild(int index) { return children[index]; }
    
private:
    juce::OwnedArray<Canvas> children;
    std::unique_ptr<juce::OpenGLContext> glContext;
    bool openGLEnabled = false;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Canvas)
};
