#include "RuntimeNode.h"

#include "../../ui/imgui/RuntimeNodeRenderer.h"

#include <algorithm>
#include <cmath>

namespace {
std::atomic<uint64_t> gNextRuntimeNodeStableId{1};

int varToInt(const juce::var& value, int fallback = 0) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    return static_cast<int>(value);
}

double varToDouble(const juce::var& value, double fallback = 0.0) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    return static_cast<double>(value);
}

uint32_t varToColor(const juce::var& value, uint32_t fallback = 0xffffffffu) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    if (value.isInt() || value.isInt64() || value.isDouble()) {
        return static_cast<uint32_t>(value.toString().getLargeIntValue());
    }
    return fallback;
}

uintptr_t varToTextureId(const juce::var& value, uintptr_t fallback = 0) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    if (value.isInt() || value.isInt64() || value.isDouble()) {
        return static_cast<uintptr_t>(value.toString().getLargeIntValue());
    }
    return fallback;
}

std::shared_ptr<const manifold::ui::imgui::CompiledDisplayList> compileDisplayList(const juce::var& displayList) {
    auto compiled = std::make_shared<manifold::ui::imgui::CompiledDisplayList>();
    auto* arr = displayList.getArray();
    if (arr == nullptr) {
        return compiled;
    }

    compiled->commands.reserve(static_cast<std::size_t>(arr->size()));

    for (const auto& item : *arr) {
        auto* obj = item.getDynamicObject();
        if (obj == nullptr) {
            continue;
        }

        const auto cmdName = obj->getProperty("cmd").toString().toStdString();
        const bool hasColor = obj->hasProperty("color");
        const bool hasFontSize = obj->hasProperty("fontSize");

        manifold::ui::imgui::CompiledDrawCmd cmd;
        cmd.hasColor = hasColor;
        if (hasColor) {
            const auto argb = varToColor(obj->getProperty("color"));
            const auto a = static_cast<uint32_t>((argb >> 24) & 0xffu);
            const auto r = static_cast<uint32_t>((argb >> 16) & 0xffu);
            const auto g = static_cast<uint32_t>((argb >> 8) & 0xffu);
            const auto b = static_cast<uint32_t>(argb & 0xffu);
            cmd.color = (a << 24) | (b << 16) | (g << 8) | r;
        } else {
            cmd.color = 0xffffffffu;
        }
        cmd.hasFontSize = hasFontSize;
        cmd.fontSize = static_cast<float>(varToDouble(obj->getProperty("fontSize"), 13.0));
        cmd.x = static_cast<float>(varToInt(obj->getProperty("x")));
        cmd.y = static_cast<float>(varToInt(obj->getProperty("y")));
        cmd.w = static_cast<float>(varToInt(obj->getProperty("w")));
        cmd.h = static_cast<float>(varToInt(obj->getProperty("h")));
        cmd.radius = static_cast<float>(varToDouble(obj->getProperty("radius"), 0.0));
        cmd.thickness = static_cast<float>(varToDouble(obj->getProperty("thickness"), 1.0));
        cmd.x1 = static_cast<float>(varToDouble(obj->getProperty("x1"), cmd.x));
        cmd.y1 = static_cast<float>(varToDouble(obj->getProperty("y1"), cmd.y));
        cmd.x2 = static_cast<float>(varToDouble(obj->getProperty("x2"), cmd.x + cmd.w));
        cmd.y2 = static_cast<float>(varToDouble(obj->getProperty("y2"), cmd.y + cmd.h));
        cmd.cx1 = static_cast<float>(varToDouble(obj->getProperty("cx1"), cmd.x));
        cmd.cy1 = static_cast<float>(varToDouble(obj->getProperty("cy1"), cmd.y));
        cmd.cx2 = static_cast<float>(varToDouble(obj->getProperty("cx2"), cmd.x + cmd.w));
        cmd.cy2 = static_cast<float>(varToDouble(obj->getProperty("cy2"), cmd.y + cmd.h));
        cmd.segments = varToInt(obj->getProperty("segments"), 0);
        cmd.text = obj->getProperty("text").toString().toStdString();
        cmd.align = obj->getProperty("align").toString().toStdString();
        cmd.valign = obj->getProperty("valign").toString().toStdString();
        cmd.textureId = varToTextureId(obj->getProperty("textureId"), varToTextureId(obj->getProperty("texture")));
        cmd.u0 = static_cast<float>(varToDouble(obj->getProperty("u0"), 0.0));
        cmd.v0 = static_cast<float>(varToDouble(obj->getProperty("v0"), 0.0));
        cmd.u1 = static_cast<float>(varToDouble(obj->getProperty("u1"), 1.0));
        cmd.v1 = static_cast<float>(varToDouble(obj->getProperty("v1"), 1.0));

        bool recognized = true;
        if (cmdName == "save") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::Save;
            cmd.hasColor = false;
            cmd.hasFontSize = false;
        } else if (cmdName == "restore") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::Restore;
            cmd.hasColor = false;
            cmd.hasFontSize = false;
        } else if (cmdName == "fillRect") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::FillRect;
        } else if (cmdName == "drawRect") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::DrawRect;
        } else if (cmdName == "fillRoundedRect") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::FillRoundedRect;
        } else if (cmdName == "drawRoundedRect") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::DrawRoundedRect;
        } else if (cmdName == "drawLine") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::DrawLine;
        } else if (cmdName == "drawBezier") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::DrawBezier;
        } else if (cmdName == "drawText") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::DrawText;
        } else if (cmdName == "drawImage") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::DrawImage;
        } else if (cmdName == "clipRect") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::ClipRect;
        } else if (cmdName == "popClipRect") {
            cmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::PopClipRect;
        } else {
            recognized = false;
        }

        if (recognized) {
            compiled->commands.push_back(std::move(cmd));
            continue;
        }

        if (hasColor) {
            manifold::ui::imgui::CompiledDrawCmd setColorCmd;
            setColorCmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::SetColor;
            setColorCmd.hasColor = true;
            setColorCmd.color = cmd.color;
            compiled->commands.push_back(std::move(setColorCmd));
        }
        if (hasFontSize) {
            manifold::ui::imgui::CompiledDrawCmd setFontSizeCmd;
            setFontSizeCmd.type = manifold::ui::imgui::CompiledDrawCmd::Type::SetFontSize;
            setFontSizeCmd.hasFontSize = true;
            setFontSizeCmd.fontSize = cmd.fontSize;
            compiled->commands.push_back(std::move(setFontSizeCmd));
        }
    }

    return compiled;
}
}

RuntimeNode::RuntimeNode(const std::string& name)
    : stableId_(gNextRuntimeNodeStableId.fetch_add(1, std::memory_order_relaxed)),
      nodeId_(name) {
}

void RuntimeNode::setNodeId(const std::string& id) {
    if (nodeId_ == id) {
        return;
    }
    nodeId_ = id;
    markPropsDirty();
}

void RuntimeNode::setWidgetType(const std::string& type) {
    if (widgetType_ == type) {
        return;
    }
    widgetType_ = type;
    markPropsDirty();
}

void RuntimeNode::setBounds(int x, int y, int w, int h) {
    if (bounds_.x == x && bounds_.y == y && bounds_.w == w && bounds_.h == h) {
        return;
    }
    bounds_ = {x, y, w, h};
    markPropsDirty();
}

void RuntimeNode::setClipRect(int x, int y, int w, int h) {
    if (hasClipRect_ && clipRect_.x == x && clipRect_.y == y && clipRect_.w == w && clipRect_.h == h) {
        return;
    }
    clipRect_ = {x, y, w, h};
    hasClipRect_ = true;
    markPropsDirty();
}

void RuntimeNode::clearClipRect() {
    if (!hasClipRect_) {
        return;
    }
    hasClipRect_ = false;
    clipRect_ = {};
    markPropsDirty();
}

void RuntimeNode::setVisible(bool visible) {
    if (visible_ == visible) {
        return;
    }
    visible_ = visible;
    markPropsDirty();
}

void RuntimeNode::setOpenGLEnabled(bool enabled) {
    if (openGLEnabled_ == enabled) {
        return;
    }

    openGLEnabled_ = enabled;
    if (enabled) {
        customSurfaceType_ = "opengl";
    } else if (customSurfaceType_ == "opengl") {
        customSurfaceType_.clear();
        customRenderPayload_ = juce::var();
    }
    markRenderDirty();
}

void RuntimeNode::setZOrder(int zOrder) {
    if (zOrder_ == zOrder) {
        return;
    }
    zOrder_ = zOrder;
    markPropsDirty();
}

void RuntimeNode::setStyle(const StyleState& style) {
    const bool changed = style_.background != style.background
        || style_.border != style.border
        || style_.borderWidth != style.borderWidth
        || style_.cornerRadius != style.cornerRadius
        || style_.opacity != style.opacity
        || style_.padding != style.padding;

    if (!changed) {
        return;
    }

    style_ = style;
    markRenderDirty();
}

void RuntimeNode::setInputCapabilities(const InputCapabilities& capabilities) {
    const bool changed = inputCapabilities_.pointer != capabilities.pointer
        || inputCapabilities_.wheel != capabilities.wheel
        || inputCapabilities_.keyboard != capabilities.keyboard
        || inputCapabilities_.focusable != capabilities.focusable
        || inputCapabilities_.interceptsChildren != capabilities.interceptsChildren;

    if (!changed) {
        return;
    }

    inputCapabilities_ = capabilities;
    markPropsDirty();
}

void RuntimeNode::setTransform(float scaleX, float scaleY, float translateX, float translateY) {
    constexpr float eps = 1e-7f;
    const bool changed = std::abs(transform_.scaleX - scaleX) > eps
        || std::abs(transform_.scaleY - scaleY) > eps
        || std::abs(transform_.translateX - translateX) > eps
        || std::abs(transform_.translateY - translateY) > eps;

    if (!changed) {
        return;
    }

    transform_.scaleX = scaleX;
    transform_.scaleY = scaleY;
    transform_.translateX = translateX;
    transform_.translateY = translateY;
    markPropsDirty();
}

void RuntimeNode::clearTransform() {
    if (transform_.isIdentity()) {
        return;
    }

    transform_ = Transform{};
    markPropsDirty();
}

void RuntimeNode::setHovered(bool hovered) {
    if (hovered_ == hovered) {
        return;
    }
    hovered_ = hovered;
    markRenderDirty();
}

void RuntimeNode::setPressed(bool pressed) {
    if (pressed_ == pressed) {
        return;
    }
    pressed_ = pressed;
    markRenderDirty();
}

void RuntimeNode::setFocused(bool focused) {
    if (focused_ == focused) {
        return;
    }
    focused_ = focused;
    markRenderDirty();
}

void RuntimeNode::clearCallbacks() {
    callbacks_ = {};
    markPropsDirty();
}

void RuntimeNode::setDisplayList(const juce::var& displayList) {
    displayList_ = displayList;
    customSurfaceType_.clear();
    customRenderPayload_ = juce::var();
    displayListVersion_.fetch_add(1, std::memory_order_relaxed);
    markRenderDirty();
}

std::shared_ptr<const manifold::ui::imgui::CompiledDisplayList> RuntimeNode::getCompiledDisplayList() const {
    const auto currentVersion = displayListVersion_.load(std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(compiledDisplayListMutex_);
        if (compiledDisplayList_ && compiledDisplayListVersion_ == currentVersion) {
            return compiledDisplayList_;
        }
    }

    auto compiled = compileDisplayList(displayList_);
    {
        std::lock_guard<std::mutex> lock(compiledDisplayListMutex_);
        if (!compiledDisplayList_ || compiledDisplayListVersion_ != currentVersion) {
            compiledDisplayList_ = compiled;
            compiledDisplayListVersion_ = currentVersion;
        }
        return compiledDisplayList_;
    }
}

void RuntimeNode::clearDisplayList() {
    if (displayList_.isVoid()) {
        return;
    }
    displayList_ = juce::var();
    displayListVersion_.fetch_add(1, std::memory_order_relaxed);
    markRenderDirty();
}

void RuntimeNode::setCustomSurfaceType(const std::string& type) {
    if (customSurfaceType_ == type) {
        return;
    }
    customSurfaceType_ = type;
    markRenderDirty();
}

void RuntimeNode::setCustomRenderPayload(const juce::var& payload) {
    customRenderPayload_ = payload;
    displayList_ = juce::var();
    displayListVersion_.fetch_add(1, std::memory_order_relaxed);
    markRenderDirty();
}

void RuntimeNode::clearCustomRenderPayload() {
    const bool hadPayload = !customRenderPayload_.isVoid() || !customSurfaceType_.empty();
    customRenderPayload_ = juce::var();
    customSurfaceType_.clear();
    if (hadPayload) {
        markRenderDirty();
    }
}

void RuntimeNode::markStructureDirty() {
    structureVersion_.fetch_add(1, std::memory_order_relaxed);
    if (parent_ != nullptr) {
        parent_->markStructureDirty();
    }
}

void RuntimeNode::markPropsDirty() {
    propsVersion_.fetch_add(1, std::memory_order_relaxed);
    if (parent_ != nullptr) {
        parent_->markPropsDirty();
    }
}

void RuntimeNode::markRenderDirty() {
    renderVersion_.fetch_add(1, std::memory_order_relaxed);
    if (parent_ != nullptr) {
        parent_->markRenderDirty();
    }
}

RuntimeNode* RuntimeNode::createChild(const std::string& name) {
    auto child = std::make_unique<RuntimeNode>(name);
    auto* childPtr = child.get();
    childPtr->parent_ = this;
    children_.push_back(childPtr);
    ownedChildren_.push_back(std::move(child));
    markStructureDirty();
    return childPtr;
}

void RuntimeNode::addChild(RuntimeNode* child) {
    if (child == nullptr || child == this) {
        return;
    }

    if (child->parent_ == this) {
        return;
    }

    if (child->parent_ != nullptr) {
        child->parent_->removeChild(child);
    }

    child->parent_ = this;
    children_.push_back(child);
    markStructureDirty();
}

void RuntimeNode::removeChild(RuntimeNode* child) {
    if (child == nullptr) {
        return;
    }

    auto it = std::find(children_.begin(), children_.end(), child);
    if (it == children_.end()) {
        return;
    }

    child->parent_ = nullptr;
    children_.erase(it);

    auto ownedIt = std::find_if(ownedChildren_.begin(), ownedChildren_.end(),
                                [child](const std::unique_ptr<RuntimeNode>& owned) {
                                    return owned.get() == child;
                                });
    if (ownedIt != ownedChildren_.end()) {
        ownedChildren_.erase(ownedIt);
    }

    markStructureDirty();
}

void RuntimeNode::clearChildren() {
    if (children_.empty() && ownedChildren_.empty()) {
        return;
    }

    for (auto* child : children_) {
        if (child != nullptr) {
            child->parent_ = nullptr;
        }
    }

    children_.clear();
    ownedChildren_.clear();
    markStructureDirty();
}

RuntimeNode* RuntimeNode::findById(const std::string& id) {
    if (nodeId_ == id) {
        return this;
    }

    for (auto* child : children_) {
        if (child == nullptr) {
            continue;
        }
        if (auto* match = child->findById(id)) {
            return match;
        }
    }

    return nullptr;
}

RuntimeNode* RuntimeNode::findByStableId(uint64_t stableId) {
    if (stableId_ == stableId) {
        return this;
    }

    for (auto* child : children_) {
        if (child == nullptr) {
            continue;
        }
        if (auto* match = child->findByStableId(stableId)) {
            return match;
        }
    }

    return nullptr;
}

void RuntimeNode::setUserData(const std::string& key, sol::object value) {
    userData_[key] = value;
    markPropsDirty();
}

sol::object RuntimeNode::getUserData(const std::string& key) const {
    auto it = userData_.find(key);
    if (it != userData_.end()) {
        return it->second;
    }
    return sol::lua_nil;
}

bool RuntimeNode::hasUserData(const std::string& key) const {
    return userData_.find(key) != userData_.end();
}

std::vector<std::string> RuntimeNode::getUserDataKeys() const {
    std::vector<std::string> keys;
    keys.reserve(userData_.size());
    for (const auto& pair : userData_) {
        keys.push_back(pair.first);
    }
    return keys;
}

void RuntimeNode::clearUserData(const std::string& key) {
    if (userData_.erase(key) > 0) {
        markPropsDirty();
    }
}

void RuntimeNode::clearAllUserData() {
    if (!userData_.empty()) {
        userData_.clear();
        markPropsDirty();
    }
}
