#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include "CanvasStyle.h"
#include <functional>

class Canvas : public juce::Component {
public:
    Canvas(const juce::String& name = "Canvas") 
        : juce::Component(name) 
    {}
    
    CanvasStyle style;
    
    std::function<void(Canvas&, juce::Graphics&)> onDraw;
    std::function<void(const juce::MouseEvent&)> onMouseDown;
    std::function<void(const juce::MouseEvent&)> onMouseDrag;
    std::function<void(const juce::MouseEvent&)> onMouseUp;
    std::function<void(const juce::MouseEvent&)> onMouseMove;
    std::function<void()> onClick;
    std::function<void(float)> onValueChanged;
    std::function<void(bool)> onToggled;
    
    void paint(juce::Graphics& g) override {
        if (style.opacity < 0.001f) return;
        
        auto bounds = getLocalBounds().toFloat();
        
        g.setColour(style.background.withMultipliedAlpha(style.opacity));
        if (style.cornerRadius > 0.001f)
            g.fillRoundedRectangle(bounds, style.cornerRadius);
        else
            g.fillRect(bounds);
        
        if (style.borderWidth > 0.001f) {
            g.setColour(style.border.withMultipliedAlpha(style.opacity));
            if (style.cornerRadius > 0.001f)
                g.drawRoundedRectangle(bounds, style.cornerRadius, style.borderWidth);
            else
                g.drawRect(bounds, static_cast<int>(style.borderWidth));
        }
        
        if (onDraw) onDraw(*this, g);
    }
    
    void mouseDown(const juce::MouseEvent& e) override {
        if (onMouseDown) onMouseDown(e);
    }
    
    void mouseDrag(const juce::MouseEvent& e) override {
        if (onMouseDrag) onMouseDrag(e);
    }
    
    void mouseUp(const juce::MouseEvent& e) override {
        if (onClick && !e.mouseWasDraggedSinceMouseDown()) {
            onClick();
        }
        if (onMouseUp) onMouseUp(e);
    }
    
    void mouseMove(const juce::MouseEvent& e) override {
        if (onMouseMove) onMouseMove(e);
    }
    
    void setStyle(const CanvasStyle& s) {
        style = s;
        repaint();
    }
    
    Canvas* addChild(const juce::String& childName = "child") {
        auto* child = new Canvas(childName);
        children.add(child);
        addAndMakeVisible(child);
        return child;
    }
    
    void removeChild(Canvas* child) {
        removeChildComponent(child);
        children.removeObject(child);
    }
    
    void clearChildren() {
        removeAllChildren();
        children.clear();
    }
    
    int getNumChildren() const { return children.size(); }
    Canvas* getChild(int index) { return children[index]; }
    
private:
    juce::OwnedArray<Canvas> children;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Canvas)
};
