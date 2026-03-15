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

int64_t nowSteadyUs() {
    return std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count();
}

void updateTrackedLeadMetric(std::atomic<int64_t>& currentUs,
                             std::atomic<int64_t>& peakUs,
                             std::atomic<int64_t>& avgUsX100,
                             int64_t durationUs) {
    currentUs.store(durationUs, std::memory_order_relaxed);

    const int64_t previousPeak = peakUs.load(std::memory_order_relaxed);
    if (durationUs > previousPeak) {
        peakUs.store(durationUs, std::memory_order_relaxed);
    }

    constexpr int64_t kAlphaNum = 5;
    constexpr int64_t kAlphaDen = 100;
    const int64_t previousAvgX100 = avgUsX100.load(std::memory_order_relaxed);
    const int64_t durationX100 = durationUs * 100;
    const int64_t nextAvgX100 = (previousAvgX100 == 0)
        ? durationX100
        : ((previousAvgX100 * (kAlphaDen - kAlphaNum)) + (durationX100 * kAlphaNum)) / kAlphaDen;
    avgUsX100.store(nextAvgX100, std::memory_order_relaxed);
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
      node_(std::make_unique<RuntimeNode>(name.toStdString()))
{
    syncRuntimeBounds();
    syncRuntimeVisibility();
    syncRuntimeStyle();
    syncInputCapabilities();
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
    syncRuntimeVisibility();
    markPropsDirty();

    // Auto-create OpenGL context when component becomes visible
    if (openGLEnabled && isShowing() && !glContext && getWidth() > 0 && getHeight() > 0) {
        glContext = std::make_unique<juce::OpenGLContext>();
        glContext->setRenderer(this);
        glContext->attachTo(*this);
    }
}

void Canvas::resized() {
    syncRuntimeBounds();
    markPropsDirty();

    // Auto-create OpenGL context when component gets size
    if (openGLEnabled && isShowing() && !glContext && getWidth() > 0 && getHeight() > 0) {
        glContext = std::make_unique<juce::OpenGLContext>();
        glContext->setRenderer(this);
        glContext->attachTo(*this);
    }
}

void Canvas::moved() {
    syncRuntimeBounds();
    markPropsDirty();
}

void Canvas::parentHierarchyChanged() {
    // If this canvas was removed from its parent, disable OpenGL
    if (openGLEnabled && glContext && getParentComponent() == nullptr) {
        setOpenGLEnabled(false);
    }
}

void Canvas::requestTrackedRepaint() {
    const int64_t nowUs = nowSteadyUs();
    int64_t expected = 0;
    trackedRepaintRequestedAtUs_.compare_exchange_strong(expected, nowUs, std::memory_order_relaxed);
    repaint();
}

void Canvas::paint(juce::Graphics& g) {
    const auto startTime = std::chrono::steady_clock::now();
    const int64_t paintStartUs = nowSteadyUs();
    const int64_t requestedAtUs = trackedRepaintRequestedAtUs_.exchange(0, std::memory_order_relaxed);
    if (requestedAtUs > 0 && paintStartUs >= requestedAtUs) {
        updateTrackedLeadMetric(trackedRepaintLeadCurrentUs_,
                                trackedRepaintLeadPeakUs_,
                                trackedRepaintLeadAvgUsX100_,
                                paintStartUs - requestedAtUs);
    }

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

    node_->setPressed(true);

    if (getWantsKeyboardFocus()) {
        grabKeyboardFocus();
        node_->setFocused(true);
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

    node_->setPressed(false);

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

    node_->setHovered(true);

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

    node_->setHovered(false);
    node_->setPressed(false);

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
    node_->setFocused(true);
    if (onKeyPress) {
        return onKeyPress(key);
    }
    return juce::Component::keyPressed(key);
}

Canvas::InputCapabilities Canvas::getInputCapabilities() const {
    const auto& caps = node_->getInputCapabilities();
    return InputCapabilities{
        caps.pointer,
        caps.wheel,
        caps.keyboard,
        caps.focusable,
        caps.interceptsChildren,
    };
}

void Canvas::setNodeId(const std::string& id) {
    node_->setNodeId(id);
}

void Canvas::setWidgetType(const std::string& type) {
    node_->setWidgetType(type);
}

void Canvas::syncInputCapabilities() {
    bool clicks = false;
    bool childrenClicks = false;
    getInterceptsMouseClicks(clicks, childrenClicks);

    RuntimeNode::InputCapabilities next;
    next.pointer = clicks && (static_cast<bool>(onMouseDown)
        || static_cast<bool>(onMouseDrag)
        || static_cast<bool>(onMouseUp)
        || static_cast<bool>(onClick)
        || static_cast<bool>(onDoubleClick));
    next.wheel = static_cast<bool>(onMouseWheel);
    next.keyboard = static_cast<bool>(onKeyPress);
    next.focusable = getWantsKeyboardFocus();
    next.interceptsChildren = childrenClicks;

    node_->setInputCapabilities(next);
}

void Canvas::setDisplayList(const juce::var& displayList) {
    node_->setDisplayList(displayList);
}

void Canvas::clearDisplayList() {
    node_->clearDisplayList();
}

void Canvas::setCustomRenderPayload(const juce::var& payload) {
    node_->setCustomRenderPayload(payload);
}

void Canvas::clearCustomRenderPayload() {
    node_->clearCustomRenderPayload();
}

void Canvas::markStructureDirty() {
    node_->markStructureDirty();
}

void Canvas::markPropsDirty() {
    node_->markPropsDirty();
}

void Canvas::markRenderDirty() {
    node_->markRenderDirty();
}

void Canvas::setStyle(const CanvasStyle& s) {
    style = s;
    syncRuntimeStyle();
    markRenderDirty();
    repaint();
}

Canvas* Canvas::addChild(const juce::String& childName) {
    auto* child = new Canvas(childName);
    children.add(child);
    addAndMakeVisible(child);
    node_->addChild(child->getRuntimeNode());
    markStructureDirty();
    return child;
}

void Canvas::adoptChild(Canvas* child) {
    if (child == nullptr) return;
    
    // Remove from current parent's children array (but don't delete)
    if (auto* oldParent = dynamic_cast<Canvas*>(child->getParentComponent())) {
        oldParent->children.removeObject(child, false);  // false = don't delete
        oldParent->getRuntimeNode()->removeChild(child->getRuntimeNode());
        oldParent->markStructureDirty();
    }
    
    // Add to this canvas
    children.add(child);
    addAndMakeVisible(child);
    node_->addChild(child->getRuntimeNode());
    markStructureDirty();
}

void Canvas::removeChild(Canvas* child) {
    // Ensure OpenGL is disabled before removal to prevent rendering issues
    child->setOpenGLEnabled(false);
    node_->removeChild(child->getRuntimeNode());
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
    
    node_->clearChildren();
    removeAllChildren();
    children.clear();
    markStructureDirty();
}

// ============================================================================
// User Data Storage
// ============================================================================

void Canvas::setUserData(const std::string& key, sol::object value) {
    node_->setUserData(key, value);
}

sol::object Canvas::getUserData(const std::string& key) const {
    return node_->getUserData(key);
}

bool Canvas::hasUserData(const std::string& key) const {
    return node_->hasUserData(key);
}

std::vector<std::string> Canvas::getUserDataKeys() const {
    return node_->getUserDataKeys();
}

void Canvas::clearUserData(const std::string& key) {
    node_->clearUserData(key);
}

void Canvas::clearAllUserData() {
    node_->clearAllUserData();
}

void Canvas::syncRuntimeBounds() {
    node_->setBounds(getX(), getY(), getWidth(), getHeight());
}

void Canvas::syncRuntimeVisibility() {
    node_->setVisible(isVisible());
}

void Canvas::syncRuntimeStyle() {
    RuntimeNode::StyleState runtimeStyle;
    runtimeStyle.background = static_cast<uint32_t>(style.background.getARGB());
    runtimeStyle.border = static_cast<uint32_t>(style.border.getARGB());
    runtimeStyle.borderWidth = style.borderWidth;
    runtimeStyle.cornerRadius = style.cornerRadius;
    runtimeStyle.opacity = style.opacity;
    runtimeStyle.padding = style.padding;
    node_->setStyle(runtimeStyle);
}
