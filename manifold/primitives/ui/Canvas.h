#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>
#include "CanvasStyle.h"
#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <unordered_map>
#include <string>
#include <vector>

// sol2 for Lua userdata storage
#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

class Canvas : public juce::Component, public juce::OpenGLRenderer {
public:
    struct PaintProfileEntry {
        std::string name;
        std::string widgetType;
        int64_t totalUs = 0;
        int64_t lastUs = 0;
        int paintCount = 0;
        int width = 0;
        int height = 0;
        bool openGL = false;
    };

    struct InputCapabilities {
        bool pointer = false;
        bool wheel = false;
        bool keyboard = false;
        bool focusable = false;
        bool interceptsChildren = false;
    };

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
    void setOnMouseWheel(std::function<void(const juce::MouseEvent&, const juce::MouseWheelDetails&)> fn) {
        onMouseWheel = fn;
        syncInputCapabilities();
    }
    
    // Enable/disable OpenGL rendering
    void setOpenGLEnabled(bool enabled);
    bool isOpenGLEnabled() const { return openGLEnabled; }
    
    // Get the OpenGL context (valid only when OpenGL is enabled)
    juce::OpenGLContext* getOpenGLContext() { return glContext.get(); }
    
    // Standard 2D paint
    void paint(juce::Graphics& g) override;

    std::atomic<int64_t> lastPaintDurationUs{0};
    
    // Accumulate paint time from ALL canvases in a frame (not just root)
    static std::atomic<int64_t> totalPaintAccumulatedUs;
    static void resetPaintAccumulation() { totalPaintAccumulatedUs.store(0, std::memory_order_relaxed); }
    static int64_t getAccumulatedPaintUs() { return totalPaintAccumulatedUs.load(std::memory_order_relaxed); }
    static void finishPaintProfilingFrame();
    static int64_t getLastFrameAccumulatedPaintUs();
    static std::vector<PaintProfileEntry> getLastFramePaintProfile(std::size_t maxEntries = 0);
    
    // OpenGLRenderer callbacks
    void newOpenGLContextCreated() override;
    void renderOpenGL() override;
    void openGLContextClosing() override;
    
    // Input handling
    bool hitTest(int x, int y) override;
    void mouseDown(const juce::MouseEvent& e) override;
    void mouseDrag(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;
    void mouseMove(const juce::MouseEvent& e) override;
    void mouseEnter(const juce::MouseEvent& e) override;
    void mouseExit(const juce::MouseEvent& e) override;
    void mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) override;
    bool keyPressed(const juce::KeyPress& key) override;
    
    // Component lifecycle
    void visibilityChanged() override;
    void resized() override;
    void moved() override;
    void parentHierarchyChanged() override;
    
    void setStyle(const CanvasStyle& s);

    // Retained node identity + payload (backend-neutral scene seam)
    void setNodeId(const std::string& id);
    const std::string& getNodeId() const { return nodeId_; }

    void setWidgetType(const std::string& type);
    const std::string& getWidgetType() const { return widgetType_; }

    InputCapabilities getInputCapabilities() const { return inputCapabilities_; }
    void syncInputCapabilities();

    void setDisplayList(const juce::var& displayList);
    const juce::var& getDisplayList() const { return displayList_; }
    bool hasDisplayList() const { return !displayList_.isVoid(); }
    void clearDisplayList();

    void setCustomRenderPayload(const juce::var& payload);
    const juce::var& getCustomRenderPayload() const { return customRenderPayload_; }
    bool hasCustomRenderPayload() const { return !customRenderPayload_.isVoid(); }
    void clearCustomRenderPayload();

    uint64_t getStructureVersion() const { return structureVersion_.load(std::memory_order_relaxed); }
    uint64_t getPropsVersion() const { return propsVersion_.load(std::memory_order_relaxed); }
    uint64_t getRenderVersion() const { return renderVersion_.load(std::memory_order_relaxed); }
    void markStructureDirty();
    void markPropsDirty();
    void markRenderDirty();
    
    Canvas* addChild(const juce::String& childName = "child");
    void adoptChild(Canvas* child);  // Take ownership from another parent
    void removeChild(Canvas* child);
    void clearChildren();
    
    int getNumChildren() const { return children.size(); }
    Canvas* getChild(int index) { return children[index]; }
    
    // User data storage for editor metadata and runtime properties
    void setUserData(const std::string& key, sol::object value);
    sol::object getUserData(const std::string& key) const;
    bool hasUserData(const std::string& key) const;
    std::vector<std::string> getUserDataKeys() const;
    void clearUserData(const std::string& key);
    void clearAllUserData();
    
private:
    juce::OwnedArray<Canvas> children;
    std::unique_ptr<juce::OpenGLContext> glContext;
    bool openGLEnabled = false;

    std::string nodeId_;
    std::string widgetType_;
    InputCapabilities inputCapabilities_;
    juce::var displayList_;
    juce::var customRenderPayload_;
    std::atomic<uint64_t> structureVersion_{1};
    std::atomic<uint64_t> propsVersion_{1};
    std::atomic<uint64_t> renderVersion_{1};
    
    // User data storage (editor metadata, widget properties, etc.)
    mutable std::unordered_map<std::string, sol::object> userData_;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Canvas)
};
