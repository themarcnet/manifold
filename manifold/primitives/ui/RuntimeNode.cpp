#include "RuntimeNode.h"

#include "../../ui/imgui/RuntimeNodeRenderer.h"

#include <algorithm>
#include <cmath>

namespace {
std::atomic<uint64_t> gNextRuntimeNodeStableId{1};

struct DisplayListDebugState {
    std::mutex mutex;
    uint64_t setCalls = 0;
    uint64_t skippedSetCalls = 0;
    uint64_t clearCalls = 0;
    uint64_t compileCalls = 0;
    uint64_t setCommands = 0;
    uint64_t compiledCommands = 0;
    uint64_t compileMicros = 0;
    std::unordered_map<std::string, uint64_t> setByKey;
    std::unordered_map<std::string, uint64_t> skippedSetByKey;
    std::unordered_map<std::string, uint64_t> compileByKey;
};

DisplayListDebugState& displayListDebugState() {
    static DisplayListDebugState state;
    return state;
}

bool nearlyEqual(double a, double b) {
    return std::abs(a - b) < 1.0e-9;
}

std::string displayListDebugKey(const RuntimeNode& node) {
    const auto& widgetType = node.getWidgetType();
    const auto& nodeId = node.getNodeId();
    if (!widgetType.empty() && !nodeId.empty()) {
        return widgetType + ":" + nodeId;
    }
    if (!widgetType.empty()) {
        return widgetType;
    }
    if (!nodeId.empty()) {
        return nodeId;
    }
    return "<anonymous>";
}

uint64_t displayListCommandCount(const juce::var& displayList) {
    auto* arr = displayList.getArray();
    return arr != nullptr ? static_cast<uint64_t>(arr->size()) : 0;
}

void recordDisplayListSet(const RuntimeNode& node, const juce::var& displayList) {
    auto& stats = displayListDebugState();
    const auto key = displayListDebugKey(node);
    const auto commandCount = displayListCommandCount(displayList);
    std::lock_guard<std::mutex> lock(stats.mutex);
    ++stats.setCalls;
    stats.setCommands += commandCount;
    ++stats.setByKey[key];
}

void recordDisplayListSetSkipped(const RuntimeNode& node) {
    auto& stats = displayListDebugState();
    const auto key = displayListDebugKey(node);
    std::lock_guard<std::mutex> lock(stats.mutex);
    ++stats.skippedSetCalls;
    ++stats.skippedSetByKey[key];
}

void recordDisplayListClear() {
    auto& stats = displayListDebugState();
    std::lock_guard<std::mutex> lock(stats.mutex);
    ++stats.clearCalls;
}

void recordDisplayListCompile(const RuntimeNode& node, uint64_t commandCount, uint64_t elapsedMicros) {
    auto& stats = displayListDebugState();
    const auto key = displayListDebugKey(node);
    std::lock_guard<std::mutex> lock(stats.mutex);
    ++stats.compileCalls;
    stats.compiledCommands += commandCount;
    stats.compileMicros += elapsedMicros;
    ++stats.compileByKey[key];
}

std::vector<std::pair<std::string, uint64_t>> topEntries(const std::unordered_map<std::string, uint64_t>& source,
                                                         size_t limit = 12) {
    std::vector<std::pair<std::string, uint64_t>> out(source.begin(), source.end());
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
        if (a.second != b.second) {
            return a.second > b.second;
        }
        return a.first < b.first;
    });
    if (out.size() > limit) {
        out.resize(limit);
    }
    return out;
}

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

bool varsSemanticallyEqual(const juce::var& a, const juce::var& b);

bool arraysSemanticallyEqual(const juce::Array<juce::var>& a, const juce::Array<juce::var>& b) {
    if (a.size() != b.size()) {
        return false;
    }
    for (int i = 0; i < a.size(); ++i) {
        if (!varsSemanticallyEqual(a.getReference(i), b.getReference(i))) {
            return false;
        }
    }
    return true;
}

bool objectsSemanticallyEqual(const juce::DynamicObject* a, const juce::DynamicObject* b) {
    if (a == b) {
        return true;
    }
    if (a == nullptr || b == nullptr) {
        return false;
    }

    const auto& aProps = a->getProperties();
    const auto& bProps = b->getProperties();
    if (aProps.size() != bProps.size()) {
        return false;
    }

    for (const auto& property : aProps) {
        if (!b->hasProperty(property.name)) {
            return false;
        }
        if (!varsSemanticallyEqual(property.value, b->getProperty(property.name))) {
            return false;
        }
    }
    return true;
}

bool varsSemanticallyEqual(const juce::var& a, const juce::var& b) {
    if (a.isVoid() || a.isUndefined()) {
        return b.isVoid() || b.isUndefined();
    }
    if (b.isVoid() || b.isUndefined()) {
        return false;
    }
    if (a.isBool() || b.isBool()) {
        return a.isBool() && b.isBool() && static_cast<bool>(a) == static_cast<bool>(b);
    }
    if ((a.isInt() || a.isInt64() || a.isDouble()) && (b.isInt() || b.isInt64() || b.isDouble())) {
        return nearlyEqual(static_cast<double>(a), static_cast<double>(b));
    }
    if (a.isString() || b.isString()) {
        return a.toString() == b.toString();
    }
    if (auto* aArr = a.getArray()) {
        auto* bArr = b.getArray();
        return bArr != nullptr && arraysSemanticallyEqual(*aArr, *bArr);
    }
    if (auto* aObj = a.getDynamicObject()) {
        return objectsSemanticallyEqual(aObj, b.getDynamicObject());
    }
    return a.equalsWithSameType(b);
}

int64_t estimateVarBytes(const juce::var& value) {
    if (value.isVoid() || value.isUndefined()) {
        return 0;
    }
    if (value.isString()) {
        return static_cast<int64_t>(value.toString().getNumBytesAsUTF8());
    }
    if (auto* arr = value.getArray()) {
        int64_t total = static_cast<int64_t>(sizeof(juce::var)) * arr->size();
        for (const auto& item : *arr) {
            total += estimateVarBytes(item);
        }
        return total;
    }
    if (auto* obj = value.getDynamicObject()) {
        int64_t total = sizeof(juce::DynamicObject);
        for (const auto& prop : obj->getProperties()) {
            total += static_cast<int64_t>(prop.name.toString().getNumBytesAsUTF8());
            total += estimateVarBytes(prop.value);
        }
        return total;
    }
    return sizeof(juce::var);
}

int countValidCallbacks(const RuntimeNode::CallbackSlots& callbacks) {
    int count = 0;
    if (callbacks.onMouseDown.valid()) ++count;
    if (callbacks.onMouseDrag.valid()) ++count;
    if (callbacks.onMouseUp.valid()) ++count;
    if (callbacks.onMouseMove.valid()) ++count;
    if (callbacks.onMouseWheel.valid()) ++count;
    if (callbacks.onKeyPress.valid()) ++count;
    if (callbacks.onClick.valid()) ++count;
    if (callbacks.onDoubleClick.valid()) ++count;
    if (callbacks.onMouseEnter.valid()) ++count;
    if (callbacks.onMouseExit.valid()) ++count;
    if (callbacks.onDraw.valid()) ++count;
    if (callbacks.onGLRender.valid()) ++count;
    if (callbacks.onGLContextCreated.valid()) ++count;
    if (callbacks.onGLContextClosing.valid()) ++count;
    if (callbacks.onValueChanged.valid()) ++count;
    if (callbacks.onToggled.valid()) ++count;
    return count;
}

int64_t estimateCompiledDisplayListBytes(const manifold::ui::imgui::CompiledDisplayList& compiled,
                                         uint64_t& commandCountOut) {
    int64_t total = sizeof(manifold::ui::imgui::CompiledDisplayList);
    total += static_cast<int64_t>(compiled.commands.capacity()) *
             static_cast<int64_t>(sizeof(manifold::ui::imgui::CompiledDrawCmd));
    commandCountOut = static_cast<uint64_t>(compiled.commands.size());
    for (const auto& cmd : compiled.commands) {
        total += static_cast<int64_t>(cmd.text.capacity());
        total += static_cast<int64_t>(cmd.align.capacity());
        total += static_cast<int64_t>(cmd.valign.capacity());
    }
    return total;
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
        || !nearlyEqual(style_.borderWidth, style.borderWidth)
        || !nearlyEqual(style_.cornerRadius, style.cornerRadius)
        || !nearlyEqual(style_.opacity, style.opacity)
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
    recordDisplayListSet(*this, displayList);
    const bool hadCustomRenderState = !customSurfaceType_.empty() || !customRenderPayload_.isVoid();
    if (!hadCustomRenderState && varsSemanticallyEqual(displayList_, displayList)) {
        recordDisplayListSetSkipped(*this);
        return;
    }

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

    const auto startTicks = juce::Time::getHighResolutionTicks();
    auto compiled = compileDisplayList(displayList_);
    const auto elapsedMicros = static_cast<uint64_t>(juce::Time::highResolutionTicksToSeconds(
        juce::Time::getHighResolutionTicks() - startTicks) * 1000000.0);
    recordDisplayListCompile(*this,
                             compiled ? static_cast<uint64_t>(compiled->commands.size()) : 0,
                             elapsedMicros);
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
    recordDisplayListClear();
    displayList_ = juce::var();
    displayListVersion_.fetch_add(1, std::memory_order_relaxed);
    markRenderDirty();
}

RuntimeNode::DisplayListDebugStats RuntimeNode::getDisplayListDebugStats(bool reset) {
    auto& state = displayListDebugState();
    std::lock_guard<std::mutex> lock(state.mutex);

    DisplayListDebugStats stats;
    stats.setCalls = state.setCalls;
    stats.skippedSetCalls = state.skippedSetCalls;
    stats.clearCalls = state.clearCalls;
    stats.compileCalls = state.compileCalls;
    stats.setCommands = state.setCommands;
    stats.compiledCommands = state.compiledCommands;
    stats.compileMicros = state.compileMicros;
    stats.topSetByKey = topEntries(state.setByKey);
    stats.topSkippedSetByKey = topEntries(state.skippedSetByKey);
    stats.topCompileByKey = topEntries(state.compileByKey);

    if (reset) {
        state.setCalls = 0;
        state.skippedSetCalls = 0;
        state.clearCalls = 0;
        state.compileCalls = 0;
        state.setCommands = 0;
        state.compiledCommands = 0;
        state.compileMicros = 0;
        state.setByKey.clear();
        state.skippedSetByKey.clear();
        state.compileByKey.clear();
    }

    return stats;
}

RuntimeNode::MemoryStats RuntimeNode::estimateMemoryUsage() const {
    MemoryStats stats;
    std::unordered_set<const manifold::ui::imgui::CompiledDisplayList*> seenCompiled;

    std::function<void(const RuntimeNode&)> visit = [&](const RuntimeNode& node) {
        stats.nodeCount += 1;
        stats.nodeBytes += sizeof(RuntimeNode);
        stats.stringBytes += static_cast<int64_t>(node.nodeId_.capacity());
        stats.stringBytes += static_cast<int64_t>(node.widgetType_.capacity());
        stats.stringBytes += static_cast<int64_t>(node.customSurfaceType_.capacity());
        stats.vectorBytes += static_cast<int64_t>(node.children_.capacity()) * static_cast<int64_t>(sizeof(RuntimeNode*));
        stats.vectorBytes += static_cast<int64_t>(node.ownedChildren_.capacity()) * static_cast<int64_t>(sizeof(std::unique_ptr<RuntimeNode>));
        stats.callbackCount += static_cast<uint64_t>(countValidCallbacks(node.callbacks_));

        stats.userDataEntries += static_cast<uint64_t>(node.userData_.size());
        stats.userDataBytes += static_cast<int64_t>(node.userData_.size()) * static_cast<int64_t>(sizeof(std::pair<std::string, sol::object>));
        for (const auto& [key, value] : node.userData_) {
            stats.userDataBytes += static_cast<int64_t>(key.capacity());
            stats.userDataBytes += sizeof(sol::object);
            juce::ignoreUnused(value);
        }

        stats.customPayloadBytes += estimateVarBytes(node.customRenderPayload_);
        stats.customPayloadBytes += estimateVarBytes(node.displayList_);

        auto compiled = node.getCompiledDisplayList();
        if (compiled && seenCompiled.insert(compiled.get()).second) {
            stats.compiledDisplayListCount += 1;
            uint64_t commandCount = 0;
            stats.compiledDisplayListBytes += estimateCompiledDisplayListBytes(*compiled, commandCount);
            stats.compiledDisplayListCommands += commandCount;
        }

        for (auto* child : node.children_) {
            if (child != nullptr) {
                visit(*child);
            }
        }
    };

    visit(*this);
    return stats;
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
