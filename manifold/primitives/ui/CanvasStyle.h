#pragma once

#include <juce_graphics/juce_graphics.h>

struct CanvasStyle {
    juce::Colour background{0x00000000};
    juce::Colour border{0x00000000};
    float borderWidth{0.0f};
    float cornerRadius{0.0f};
    float opacity{1.0f};
    float padding{0.0f};
    
    CanvasStyle withBackground(juce::Colour c) const {
        CanvasStyle s = *this;
        s.background = c;
        return s;
    }
    
    CanvasStyle withBorder(juce::Colour c, float w = 1.0f) const {
        CanvasStyle s = *this;
        s.border = c;
        s.borderWidth = w;
        return s;
    }
    
    CanvasStyle withCornerRadius(float r) const {
        CanvasStyle s = *this;
        s.cornerRadius = r;
        return s;
    }
    
    CanvasStyle withPadding(float p) const {
        CanvasStyle s = *this;
        s.padding = p;
        return s;
    }
};
