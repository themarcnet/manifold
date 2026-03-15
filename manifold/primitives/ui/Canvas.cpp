#include "Canvas.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>

using namespace juce::gl;

namespace {
using Clock = std::chrono::steady_clock;

struct PaintProfileAccumulator {
    Canvas::PaintProfileEntry entry;
};

std::unordered_map<std::uintptr_t, PaintProfileAccumulator> currentPaintProfile;
std::vector<Canvas::PaintProfileEntry> lastFramePaintProfile;
std::atomic<int64_t> lastFrameAccumulatedPaintUs{0};

std::string getCanvasWidgetType(const Canvas& canvas) {
    if (!canvas.getWidgetType().empty()) {
        return canvas.getWidgetType();
    }

    auto widgetTypeObj = canvas.getUserData("_widgetType");
    if (widgetTypeObj.valid() && widgetTypeObj.is<std::string>()) {
        return widgetTypeObj.as<std::string>();
    }

    auto editorMetaObj = canvas.getUserData("_editorMeta");
    if (editorMetaObj.valid() && editorMetaObj.is<sol::table>()) {
        sol::table editorMeta = editorMetaObj.as<sol::table>();
        return editorMeta["type"].get_or(std::string{});
    }

    return {};
}

void recordCanvasPaint(const Canvas& canvas, int64_t elapsedUs) {
    const auto key = reinterpret_cast<std::uintptr_t>(&canvas);
    auto& acc = currentPaintProfile[key];
    acc.entry.name = canvas.getName().toStdString();
    acc.entry.widgetType = getCanvasWidgetType(canvas);
    acc.entry.totalUs += elapsedUs;
    acc.entry.lastUs = elapsedUs;
    acc.entry.paintCount += 1;
    acc.entry.width = canvas.getWidth();
    acc.entry.height = canvas.getHeight();
    acc.entry.openGL = canvas.isOpenGLEnabled();
}

bool isInterestingCanvasName(const juce::String& name) {
    return name == "treeTabHierarchy"
        || name == "treeTabScripts"
        || name == "treePanel"
        || name == "treeCanvas"
        || name == "scriptCanvas"
        || name == "inspectorCanvas"
        || name == "mainTabBar"
        || name == "mainTabContent"
        || name == "script_content_root"
        || name == "editorPreviewOverlay";
}

double elapsedMs(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

void logCanvasInputEvent(const Canvas& canvas,
                         const char* eventName,
                         const juce::MouseEvent* mouseEvent,
                         double callbackMs,
                         double totalMs) {
    juce::ignoreUnused(canvas, eventName, mouseEvent, callbackMs, totalMs);
}
}

// Static paint accumulation across all canvases
std::atomic<int64_t> Canvas::totalPaintAccumulatedUs{0};

Canvas::Canvas(const juce::String& name) 
    : juce::Component(name),
      nodeId_(name.toStdString())
{
    bool clicks = false;
    bool children = false;
    getInterceptsMouseClicks(clicks, children);
    inputCapabilities_.pointer = clicks && (static_cast<bool>(onMouseDown)
        || static_cast<bool>(onMouseDrag)
        || static_cast<bool>(onMouseUp)
        || static_cast<bool>(onClick)
        || static_cast<bool>(onDoubleClick));
    inputCapabilities_.wheel = static_cast<bool>(onMouseWheel);
    inputCapabilities_.keyboard = static_cast<bool>(onKeyPress);
    inputCapabilities_.focusable = getWantsKeyboardFocus();
    inputCapabilities_.interceptsChildren = children;
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
    markPropsDirty();

    // Auto-create OpenGL context when component becomes visible
    if (openGLEnabled && isShowing() && !glContext && getWidth() > 0 && getHeight() > 0) {
        glContext = std::make_unique<juce::OpenGLContext>();
        glContext->setRenderer(this);
        glContext->attachTo(*this);
    }
}

void Canvas::resized() {
    markPropsDirty();

    // Auto-create OpenGL context when component gets size
    if (openGLEnabled && isShowing() && !glContext && getWidth() > 0 && getHeight() > 0) {
        glContext = std::make_unique<juce::OpenGLContext>();
        glContext->setRenderer(this);
        glContext->attachTo(*this);
    }
}

void Canvas::moved() {
    markPropsDirty();
}

void Canvas::parentHierarchyChanged() {
    // If this canvas was removed from its parent, disable OpenGL
    if (openGLEnabled && glContext && getParentComponent() == nullptr) {
        setOpenGLEnabled(false);
    }
}

void Canvas::paint(juce::Graphics& g) {
    const auto startTime = std::chrono::steady_clock::now();

    if (openGLEnabled) {
        const auto elapsedUs = std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - startTime).count();
        lastPaintDurationUs.store(elapsedUs, std::memory_order_relaxed);
        totalPaintAccumulatedUs.fetch_add(elapsedUs, std::memory_order_relaxed);
        recordCanvasPaint(*this, elapsedUs);
        return;
    }

    if (style.opacity >= 0.001f) {
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
    }

    if (onDraw) onDraw(*this, g);

    const auto elapsedUs = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - startTime).count();
    lastPaintDurationUs.store(elapsedUs, std::memory_order_relaxed);
    totalPaintAccumulatedUs.fetch_add(elapsedUs, std::memory_order_relaxed);
    recordCanvasPaint(*this, elapsedUs);
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

void Canvas::finishPaintProfilingFrame() {
    lastFrameAccumulatedPaintUs.store(totalPaintAccumulatedUs.exchange(0, std::memory_order_relaxed),
                                      std::memory_order_relaxed);

    lastFramePaintProfile.clear();
    lastFramePaintProfile.reserve(currentPaintProfile.size());
    for (auto& [_, acc] : currentPaintProfile) {
        lastFramePaintProfile.push_back(acc.entry);
    }

    std::sort(lastFramePaintProfile.begin(), lastFramePaintProfile.end(),
              [](const PaintProfileEntry& a, const PaintProfileEntry& b) {
                  if (a.totalUs != b.totalUs) {
                      return a.totalUs > b.totalUs;
                  }
                  return a.name < b.name;
              });

    currentPaintProfile.clear();
}

int64_t Canvas::getLastFrameAccumulatedPaintUs() {
    return lastFrameAccumulatedPaintUs.load(std::memory_order_relaxed);
}

std::vector<Canvas::PaintProfileEntry> Canvas::getLastFramePaintProfile(std::size_t maxEntries) {
    if (maxEntries == 0 || maxEntries >= lastFramePaintProfile.size()) {
        return lastFramePaintProfile;
    }
    return std::vector<PaintProfileEntry>(lastFramePaintProfile.begin(),
                                          lastFramePaintProfile.begin() + static_cast<std::ptrdiff_t>(maxEntries));
}

bool Canvas::hitTest(int x, int y) {
    return juce::Component::hitTest(x, y);
}

void Canvas::mouseDown(const juce::MouseEvent& e) {
    const auto totalStart = Clock::now();

    if (getWantsKeyboardFocus()) {
        grabKeyboardFocus();
    }

    double callbackMs = 0.0;
    if (onMouseDown) {
        const auto callbackStart = Clock::now();
        onMouseDown(e);
        callbackMs = elapsedMs(callbackStart);
    }

    logCanvasInputEvent(*this, "mouseDown", &e, callbackMs, elapsedMs(totalStart));
}

void Canvas::mouseDrag(const juce::MouseEvent& e) {
    if (!onMouseDrag) return;

    const auto totalStart = Clock::now();

    // Throttle to ~60Hz max (16ms interval) to prevent message thread saturation
    static thread_local auto lastDragTime = std::chrono::steady_clock::now();
    const auto now = std::chrono::steady_clock::now();
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - lastDragTime).count();

    if (elapsed < 16000) {  // Skip if < 16ms since last drag
        return;
    }
    lastDragTime = now;

    const auto callbackStart = Clock::now();
    onMouseDrag(e);
    logCanvasInputEvent(*this, "mouseDrag", &e, elapsedMs(callbackStart), elapsedMs(totalStart));
}

void Canvas::mouseUp(const juce::MouseEvent& e) {
    const auto totalStart = Clock::now();

    if (e.getNumberOfClicks() >= 2 && onDoubleClick) {
        const auto callbackStart = Clock::now();
        onDoubleClick();
        logCanvasInputEvent(*this, "doubleClick", &e, elapsedMs(callbackStart), elapsedMs(totalStart));
    } else if (onClick && !e.mouseWasDraggedSinceMouseDown()) {
        const auto callbackStart = Clock::now();
        onClick();
        logCanvasInputEvent(*this, "click", &e, elapsedMs(callbackStart), elapsedMs(totalStart));
    }

    double callbackMs = 0.0;
    if (onMouseUp) {
        const auto callbackStart = Clock::now();
        onMouseUp(e);
        callbackMs = elapsedMs(callbackStart);
    }

    logCanvasInputEvent(*this, "mouseUp", &e, callbackMs, elapsedMs(totalStart));
}

void Canvas::mouseMove(const juce::MouseEvent& e) {
    const auto totalStart = Clock::now();

    double callbackMs = 0.0;
    if (onMouseMove) {
        const auto callbackStart = Clock::now();
        onMouseMove(e);
        callbackMs = elapsedMs(callbackStart);
    }

    if (onMouseMove || isInterestingCanvasName(getName())) {
        logCanvasInputEvent(*this, "mouseMove", &e, callbackMs, elapsedMs(totalStart));
    }
}

void Canvas::mouseEnter(const juce::MouseEvent& e) {
    const auto totalStart = Clock::now();

    double callbackMs = 0.0;
    if (onMouseEnter) {
        const auto callbackStart = Clock::now();
        onMouseEnter();
        callbackMs = elapsedMs(callbackStart);
    }

    logCanvasInputEvent(*this, "mouseEnter", &e, callbackMs, elapsedMs(totalStart));
}

void Canvas::mouseExit(const juce::MouseEvent& e) {
    const auto totalStart = Clock::now();

    double callbackMs = 0.0;
    if (onMouseExit) {
        const auto callbackStart = Clock::now();
        onMouseExit();
        callbackMs = elapsedMs(callbackStart);
    }

    logCanvasInputEvent(*this, "mouseExit", &e, callbackMs, elapsedMs(totalStart));
}

void Canvas::mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) {
    const auto totalStart = Clock::now();

    if (onMouseWheel) {
        const auto callbackStart = Clock::now();
        onMouseWheel(e, wheel);
        logCanvasInputEvent(*this, "mouseWheel", &e, elapsedMs(callbackStart), elapsedMs(totalStart));
    } else if (getParentComponent()) {
        getParentComponent()->mouseWheelMove(e, wheel);
        logCanvasInputEvent(*this, "mouseWheelBubble", &e, 0.0, elapsedMs(totalStart));
    }
}

bool Canvas::keyPressed(const juce::KeyPress& key) {
    if (onKeyPress) {
        return onKeyPress(key);
    }
    return juce::Component::keyPressed(key);
}

void Canvas::setNodeId(const std::string& id) {
    nodeId_ = id;
    markPropsDirty();
}

void Canvas::setWidgetType(const std::string& type) {
    if (widgetType_ == type) {
        return;
    }
    widgetType_ = type;
    markPropsDirty();
}

void Canvas::syncInputCapabilities() {
    bool clicks = false;
    bool children = false;
    getInterceptsMouseClicks(clicks, children);

    InputCapabilities next;
    next.pointer = clicks && (static_cast<bool>(onMouseDown)
        || static_cast<bool>(onMouseDrag)
        || static_cast<bool>(onMouseUp)
        || static_cast<bool>(onClick)
        || static_cast<bool>(onDoubleClick));
    next.wheel = static_cast<bool>(onMouseWheel);
    next.keyboard = static_cast<bool>(onKeyPress);
    next.focusable = getWantsKeyboardFocus();
    next.interceptsChildren = children;

    const bool changed = next.pointer != inputCapabilities_.pointer
        || next.wheel != inputCapabilities_.wheel
        || next.keyboard != inputCapabilities_.keyboard
        || next.focusable != inputCapabilities_.focusable
        || next.interceptsChildren != inputCapabilities_.interceptsChildren;

    if (!changed) {
        return;
    }

    inputCapabilities_ = next;
    markPropsDirty();
}

void Canvas::setDisplayList(const juce::var& displayList) {
    displayList_ = displayList;
    customRenderPayload_ = juce::var();
    markRenderDirty();
}

void Canvas::clearDisplayList() {
    displayList_ = juce::var();
    markRenderDirty();
}

void Canvas::setCustomRenderPayload(const juce::var& payload) {
    customRenderPayload_ = payload;
    displayList_ = juce::var();
    markRenderDirty();
}

void Canvas::clearCustomRenderPayload() {
    customRenderPayload_ = juce::var();
    markRenderDirty();
}

void Canvas::markStructureDirty() {
    structureVersion_.fetch_add(1, std::memory_order_relaxed);
}

void Canvas::markPropsDirty() {
    propsVersion_.fetch_add(1, std::memory_order_relaxed);
}

void Canvas::markRenderDirty() {
    renderVersion_.fetch_add(1, std::memory_order_relaxed);
}

void Canvas::setStyle(const CanvasStyle& s) {
    style = s;
    markRenderDirty();
    repaint();
}

Canvas* Canvas::addChild(const juce::String& childName) {
    auto* child = new Canvas(childName);
    children.add(child);
    addAndMakeVisible(child);
    markStructureDirty();
    return child;
}

void Canvas::adoptChild(Canvas* child) {
    if (child == nullptr) return;
    
    // Remove from current parent's children array (but don't delete)
    if (auto* oldParent = dynamic_cast<Canvas*>(child->getParentComponent())) {
        oldParent->children.removeObject(child, false);  // false = don't delete
        oldParent->markStructureDirty();
    }
    
    // Add to this canvas
    children.add(child);
    addAndMakeVisible(child);
    markStructureDirty();
}

void Canvas::removeChild(Canvas* child) {
    // Ensure OpenGL is disabled before removal to prevent rendering issues
    child->setOpenGLEnabled(false);
    removeChildComponent(child);
    children.removeObject(child);
    markStructureDirty();
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
    markStructureDirty();
}

// ============================================================================
// User Data Storage
// ============================================================================

void Canvas::setUserData(const std::string& key, sol::object value) {
    userData_[key] = value;
    markPropsDirty();
}

sol::object Canvas::getUserData(const std::string& key) const {
    auto it = userData_.find(key);
    if (it != userData_.end()) {
        return it->second;
    }
    return sol::lua_nil;
}

bool Canvas::hasUserData(const std::string& key) const {
    return userData_.find(key) != userData_.end();
}

std::vector<std::string> Canvas::getUserDataKeys() const {
    std::vector<std::string> keys;
    keys.reserve(userData_.size());
    for (const auto& pair : userData_) {
        keys.push_back(pair.first);
    }
    return keys;
}

void Canvas::clearUserData(const std::string& key) {
    if (userData_.erase(key) > 0) {
        markPropsDirty();
    }
}

void Canvas::clearAllUserData() {
    if (!userData_.empty()) {
        userData_.clear();
        markPropsDirty();
    }
}
