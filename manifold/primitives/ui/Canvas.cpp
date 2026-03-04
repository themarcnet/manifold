#include "Canvas.h"

using namespace juce::gl;

Canvas::Canvas(const juce::String& name) 
    : juce::Component(name) 
{
}

Canvas::~Canvas() {
    setOpenGLEnabled(false);
}

void Canvas::setOpenGLEnabled(bool enabled) {
    if (enabled == openGLEnabled)
        return;
    
    openGLEnabled = enabled;
    
    if (enabled) {
        // Only create context if component is showing and has size
        if (isShowing() && getWidth() > 0 && getHeight() > 0) {
            glContext = std::make_unique<juce::OpenGLContext>();
            glContext->setRenderer(this);
            glContext->attachTo(*this);
        }
    } else {
        if (glContext) {
            glContext->detach();
            glContext.reset();
        }
    }
}

void Canvas::visibilityChanged() {
    // Auto-create OpenGL context when component becomes visible
    if (openGLEnabled && isShowing() && !glContext && getWidth() > 0 && getHeight() > 0) {
        glContext = std::make_unique<juce::OpenGLContext>();
        glContext->setRenderer(this);
        glContext->attachTo(*this);
    }
}

void Canvas::resized() {
    // Auto-create OpenGL context when component gets size
    if (openGLEnabled && isShowing() && !glContext && getWidth() > 0 && getHeight() > 0) {
        glContext = std::make_unique<juce::OpenGLContext>();
        glContext->setRenderer(this);
        glContext->attachTo(*this);
    }
}

void Canvas::parentHierarchyChanged() {
    // If this canvas was removed from its parent, disable OpenGL
    if (openGLEnabled && glContext && getParentComponent() == nullptr) {
        setOpenGLEnabled(false);
    }
}

void Canvas::paint(juce::Graphics& g) {
    // Don't paint background if OpenGL is enabled - it handles its own background
    if (openGLEnabled)
        return;
    
    // Standard 2D rendering
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

void Canvas::newOpenGLContextCreated() {
    if (onGLContextCreated)
        onGLContextCreated(*this);
}

void Canvas::renderOpenGL() {
    // Make sure we have a valid context
    if (!glContext || !glContext->isActive())
        return;
    
    // Set viewport
    auto bounds = getLocalBounds();
    if (bounds.getWidth() <= 0 || bounds.getHeight() <= 0)
        return;
    
    glViewport(0, 0, bounds.getWidth(), bounds.getHeight());
    
    // Clear to background color
    auto bg = style.background;
    glClearColor(bg.getFloatRed(), bg.getFloatGreen(), bg.getFloatBlue(), bg.getFloatAlpha());
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Call user render callback
    if (onGLRender)
        onGLRender(*this);
}

void Canvas::openGLContextClosing() {
    if (onGLContextClosing)
        onGLContextClosing(*this);
}

void Canvas::mouseDown(const juce::MouseEvent& e) {
    if (getWantsKeyboardFocus()) {
        grabKeyboardFocus();
    }
    if (onMouseDown) onMouseDown(e);
}

void Canvas::mouseDrag(const juce::MouseEvent& e) {
    if (onMouseDrag) onMouseDrag(e);
}

void Canvas::mouseUp(const juce::MouseEvent& e) {
    if (e.getNumberOfClicks() >= 2 && onDoubleClick) {
        onDoubleClick();
    } else if (onClick && !e.mouseWasDraggedSinceMouseDown()) {
        onClick();
    }
    if (onMouseUp) onMouseUp(e);
}

void Canvas::mouseMove(const juce::MouseEvent& e) {
    if (onMouseMove) onMouseMove(e);
}

void Canvas::mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) {
    if (onMouseWheel) {
        onMouseWheel(e, wheel);
    } else if (getParentComponent()) {
        getParentComponent()->mouseWheelMove(e, wheel);
    }
}

bool Canvas::keyPressed(const juce::KeyPress& key) {
    if (onKeyPress) {
        return onKeyPress(key);
    }
    return juce::Component::keyPressed(key);
}

void Canvas::setStyle(const CanvasStyle& s) {
    style = s;
    repaint();
}

Canvas* Canvas::addChild(const juce::String& childName) {
    auto* child = new Canvas(childName);
    children.add(child);
    addAndMakeVisible(child);
    return child;
}

void Canvas::removeChild(Canvas* child) {
    // Ensure OpenGL is disabled before removal to prevent rendering issues
    child->setOpenGLEnabled(false);
    removeChildComponent(child);
    children.removeObject(child);
}

void Canvas::clearChildren() {
    // Recursively disable OpenGL on ALL descendants (not just direct children)
    // This must happen before removeAllChildren() to prevent rendering issues
    std::function<void(Canvas*)> disableAllGL = [&](Canvas* canvas) {
        // First recurse into children (depth-first)
        for (int i = 0; i < canvas->getNumChildren(); ++i) {
            if (auto* childCanvas = dynamic_cast<Canvas*>(canvas->getChild(i))) {
                disableAllGL(childCanvas);
            }
        }
        // Then disable OpenGL on this canvas
        canvas->setOpenGLEnabled(false);
    };
    
    // Disable OpenGL on all descendants
    for (auto* child : children) {
        disableAllGL(child);
    }
    
    // Now safe to remove all children
    removeAllChildren();
    children.clear();
}
