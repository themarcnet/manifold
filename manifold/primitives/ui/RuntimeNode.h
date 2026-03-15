#pragma once

#include <juce_core/juce_core.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <sol/sol.hpp>

namespace manifold::ui::imgui {
struct CompiledDisplayList;
}

class RuntimeNode {
public:
    struct Rect {
        int x = 0;
        int y = 0;
        int w = 0;
        int h = 0;
    };

    struct StyleState {
        uint32_t background = 0x00000000;
        uint32_t border = 0x00000000;
        float borderWidth = 0.0f;
        float cornerRadius = 0.0f;
        float opacity = 1.0f;
        int padding = 0;
    };

    struct InputCapabilities {
        bool pointer = false;
        bool wheel = false;
        bool keyboard = false;
        bool focusable = false;
        bool interceptsChildren = false;
    };

    struct Transform {
        float scaleX = 1.0f;
        float scaleY = 1.0f;
        float translateX = 0.0f;
        float translateY = 0.0f;
        bool isIdentity() const {
            constexpr float eps = 1e-7f;
            return std::abs(scaleX - 1.0f) < eps && std::abs(scaleY - 1.0f) < eps
                && std::abs(translateX) < eps && std::abs(translateY) < eps;
        }
    };

    struct CallbackSlots {
        sol::function onMouseDown;
        sol::function onMouseDrag;
        sol::function onMouseUp;
        sol::function onMouseMove;
        sol::function onMouseWheel;
        sol::function onKeyPress;
        sol::function onClick;
        sol::function onDoubleClick;
        sol::function onMouseEnter;
        sol::function onMouseExit;
        sol::function onDraw;
        sol::function onGLRender;
        sol::function onGLContextCreated;
        sol::function onGLContextClosing;
        sol::function onValueChanged;
        sol::function onToggled;
    };

    RuntimeNode(const std::string& name = "Canvas");

    void setNodeId(const std::string& id);
    const std::string& getNodeId() const { return nodeId_; }
    uint64_t getStableId() const { return stableId_; }
    void setStableIdForClone(uint64_t stableId) { stableId_ = stableId; }

    void setWidgetType(const std::string& type);
    const std::string& getWidgetType() const { return widgetType_; }

    void setBounds(int x, int y, int w, int h);
    const Rect& getBounds() const { return bounds_; }

    void setClipRect(int x, int y, int w, int h);
    const Rect& getClipRect() const { return clipRect_; }
    bool hasClipRect() const { return hasClipRect_; }
    void clearClipRect();

    void setVisible(bool visible);
    bool isVisible() const { return visible_; }

    void setOpenGLEnabled(bool enabled);
    bool isOpenGLEnabled() const { return openGLEnabled_; }

    void setZOrder(int zOrder);
    int getZOrder() const { return zOrder_; }

    void setStyle(const StyleState& style);
    const StyleState& getStyle() const { return style_; }

    void setInputCapabilities(const InputCapabilities& capabilities);
    const InputCapabilities& getInputCapabilities() const { return inputCapabilities_; }

    void setTransform(float scaleX, float scaleY, float translateX, float translateY);
    const Transform& getTransform() const { return transform_; }
    void clearTransform();
    bool hasTransform() const { return !transform_.isIdentity(); }

    void setHovered(bool hovered);
    bool isHovered() const { return hovered_; }

    void setPressed(bool pressed);
    bool isPressed() const { return pressed_; }

    void setFocused(bool focused);
    bool isFocused() const { return focused_; }

    CallbackSlots& getCallbacks() { return callbacks_; }
    const CallbackSlots& getCallbacks() const { return callbacks_; }
    void clearCallbacks();

    void setDisplayList(const juce::var& displayList);
    const juce::var& getDisplayList() const { return displayList_; }
    bool hasDisplayList() const { return !displayList_.isVoid(); }
    std::shared_ptr<const manifold::ui::imgui::CompiledDisplayList> getCompiledDisplayList() const;
    void clearDisplayList();

    void setCustomSurfaceType(const std::string& type);
    const std::string& getCustomSurfaceType() const { return customSurfaceType_; }

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

    RuntimeNode* createChild(const std::string& name = "child");
    void addChild(RuntimeNode* child);
    void removeChild(RuntimeNode* child);
    void clearChildren();

    RuntimeNode* getParent() const { return parent_; }
    int getNumChildren() const { return static_cast<int>(children_.size()); }
    RuntimeNode* getChild(int index) const { return children_[static_cast<std::size_t>(index)]; }
    const std::vector<RuntimeNode*>& getChildren() const { return children_; }
    RuntimeNode* findById(const std::string& id);
    RuntimeNode* findByStableId(uint64_t stableId);

    void setUserData(const std::string& key, sol::object value);
    sol::object getUserData(const std::string& key) const;
    bool hasUserData(const std::string& key) const;
    std::vector<std::string> getUserDataKeys() const;
    void clearUserData(const std::string& key);
    void clearAllUserData();

private:
    RuntimeNode* parent_ = nullptr;
    std::vector<RuntimeNode*> children_;
    std::vector<std::unique_ptr<RuntimeNode>> ownedChildren_;

    uint64_t stableId_ = 0;
    std::string nodeId_;
    std::string widgetType_;
    Rect bounds_;
    Rect clipRect_;
    bool hasClipRect_ = false;
    bool visible_ = true;
    bool openGLEnabled_ = false;
    int zOrder_ = 0;
    Transform transform_;

    StyleState style_;
    InputCapabilities inputCapabilities_;
    bool hovered_ = false;
    bool pressed_ = false;
    bool focused_ = false;
    CallbackSlots callbacks_;

    juce::var displayList_;
    std::string customSurfaceType_;
    juce::var customRenderPayload_;

    std::atomic<uint64_t> structureVersion_{1};
    std::atomic<uint64_t> propsVersion_{1};
    std::atomic<uint64_t> renderVersion_{1};
    std::atomic<uint64_t> displayListVersion_{1};

    mutable std::shared_ptr<const manifold::ui::imgui::CompiledDisplayList> compiledDisplayList_;
    mutable uint64_t compiledDisplayListVersion_ = 0;
    mutable std::mutex compiledDisplayListMutex_;
    mutable std::unordered_map<std::string, sol::object> userData_;
};
