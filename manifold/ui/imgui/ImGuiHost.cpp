#include "ImGuiHost.h"

#include "TextEditor.h"
#include "backends/imgui_impl_opengl3.h"
#include "imgui.h"

#include <algorithm>
#include <chrono>
#include <cfloat>
#include <functional>
#include <thread>

using namespace juce::gl;

namespace {
size_t traceThreadId() {
    return std::hash<std::thread::id>{}(std::this_thread::get_id());
}

void logMainImGuiHostEvent(const char* event, ImGuiHost* host, juce::OpenGLContext* context = nullptr) {
    juce::ignoreUnused(event, host, context);
}
}

ImGuiHost::ImGuiHost() {
    setOpaque(false);
    setWantsKeyboardFocus(true);
    setMouseClickGrabsKeyboardFocus(true);
    setFocusContainerType(juce::Component::FocusContainerType::focusContainer);

    textEditor_ = std::make_unique<TextEditor>();
    textEditor_->SetPalette(TextEditor::PaletteId::Mariana);
    textEditor_->SetShowLineNumbersEnabled(true);
    textEditor_->SetShowWhitespacesEnabled(false);
    textEditor_->SetAutoIndentEnabled(true);
    textEditor_->SetTabSize(4);
    textEditor_->SetLineSpacing(1.15f);

    openGLContext.setRenderer(this);
    openGLContext.setComponentPaintingEnabled(false);
#ifndef __ANDROID__
    openGLContext.setPersistentAttachment(true);
#endif
    openGLContext.setContinuousRepainting(true);
    openGLContext.setSwapInterval(1);

    refreshDocumentStatsLocked();
}

ImGuiHost::~ImGuiHost() {
    openGLContext.detach();
}

ImGuiHost::StatsSnapshot ImGuiHost::getStatsSnapshot() const {
    StatsSnapshot snapshot;
    snapshot.contextReady = contextReady_.load(std::memory_order_relaxed);
    snapshot.testWindowVisible = isVisible();
    snapshot.wantCaptureMouse = wantCaptureMouse_.load(std::memory_order_relaxed);
    snapshot.wantCaptureKeyboard = wantCaptureKeyboard_.load(std::memory_order_relaxed);
    snapshot.documentLoaded = documentLoaded_.load(std::memory_order_relaxed);
    snapshot.documentDirty = documentDirty_.load(std::memory_order_relaxed);
    snapshot.frameCount = frameCount_.load(std::memory_order_relaxed);
    snapshot.lastRenderUs = lastRenderUs_.load(std::memory_order_relaxed);
    snapshot.lastVertexCount = lastVertexCount_.load(std::memory_order_relaxed);
    snapshot.lastIndexCount = lastIndexCount_.load(std::memory_order_relaxed);
    snapshot.buttonClicks = buttonClicks_.load(std::memory_order_relaxed);
    snapshot.documentLineCount = documentLineCount_.load(std::memory_order_relaxed);
    return snapshot;
}

ImGuiHost::ActionRequests ImGuiHost::consumeActionRequests() {
    ActionRequests requests;
    requests.save = requestSave_.exchange(false, std::memory_order_relaxed);
    requests.reload = requestReload_.exchange(false, std::memory_order_relaxed);
    requests.close = requestClose_.exchange(false, std::memory_order_relaxed);
    return requests;
}

ImGuiHost::DocumentIdentity ImGuiHost::getDocumentIdentity() const {
    std::lock_guard<std::recursive_mutex> lock(documentMutex_);

    DocumentIdentity identity;
    identity.path = documentFile_.getFullPathName().toStdString();
    identity.syncToken = appliedSyncToken_;
    identity.loaded = textEditor_ != nullptr && !identity.path.empty();
    return identity;
}

void ImGuiHost::configureDocument(const juce::File& file,
                                  const std::string& text,
                                  int64_t syncToken,
                                  bool readOnly) {
    std::lock_guard<std::recursive_mutex> lock(documentMutex_);

    documentFile_ = file;
    readOnly_ = readOnly;
    if (textEditor_ != nullptr) {
        textEditor_->SetReadOnlyEnabled(readOnly_);
    }

    const bool shouldReload = (appliedSyncToken_ != syncToken);
    if (shouldReload && textEditor_ != nullptr) {
        appliedSyncToken_ = syncToken;
        updateLanguageDefinitionForPathLocked(file);
        textEditor_->SetText(text);
        documentOriginalText_ = text;
    }

    if (textEditor_ != nullptr) {
        textEditor_->SetReadOnlyEnabled(readOnly_);
    }

    refreshDocumentStatsLocked();
}

void ImGuiHost::setRenderActive(bool active) {
    renderActive_.store(active, std::memory_order_relaxed);
    if (!active) {
        wantCaptureMouse_.store(false, std::memory_order_relaxed);
        wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
    }
}

bool ImGuiHost::isRenderActive() const {
    return renderActive_.load(std::memory_order_relaxed);
}

std::string ImGuiHost::getCurrentText() const {
    std::lock_guard<std::recursive_mutex> lock(documentMutex_);
    if (textEditor_ == nullptr) {
        return {};
    }
    return textEditor_->GetText();
}

void ImGuiHost::paint(juce::Graphics& g) {
    juce::ignoreUnused(g);
}

void ImGuiHost::resized() {
    logMainImGuiHostEvent("resized", this, &openGLContext);
    releaseAllMouseButtons();
    syncModifierKeys(juce::ModifierKeys::getCurrentModifiersRealtime());
    queueCurrentMousePosition();
    attachContextIfNeeded();
}

void ImGuiHost::visibilityChanged() {
    logMainImGuiHostEvent("visibilityChanged", this, &openGLContext);
    if (!isVisible()) {
        releaseAllMouseButtons();
        releaseAllActiveKeys();
        syncModifierKeys(juce::ModifierKeys::noModifiers);
        queueFocus(false);
    }
    attachContextIfNeeded();
}

void ImGuiHost::setVisible(bool shouldBeVisible) {
    Component::setVisible(shouldBeVisible);
    if (shouldBeVisible) {
        attachContextIfNeeded();
    }
}

void ImGuiHost::mouseMove(const juce::MouseEvent& e) {
    queueMousePosition(e.position);
    syncModifierKeys(e.mods);
}

void ImGuiHost::mouseDrag(const juce::MouseEvent& e) {
    queueMousePosition(e.position);
    syncModifierKeys(e.mods);
}

void ImGuiHost::mouseDown(const juce::MouseEvent& e) {
    grabKeyboardFocus();
    queueMousePosition(e.position);
    syncModifierKeys(e.mods);
}

void ImGuiHost::mouseUp(const juce::MouseEvent& e) {
    queueMousePosition(e.position);
    syncModifierKeys(e.mods);
}

void ImGuiHost::mouseExit(const juce::MouseEvent& e) {
    juce::ignoreUnused(e);

    if (leftMouseDown_ || rightMouseDown_ || middleMouseDown_) {
        return;
    }

    PendingEvent event;
    event.type = EventType::MousePos;
    event.x = -1.0f;
    event.y = -1.0f;

    std::lock_guard<std::mutex> lock(inputMutex);
    pendingEvents.push_back(std::move(event));
}

void ImGuiHost::mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) {
    queueMousePosition(e.position);
    syncModifierKeys(e.mods);

    PendingEvent event;
    event.type = EventType::MouseWheel;
    event.x = wheel.deltaX;
    event.y = wheel.deltaY;

    std::lock_guard<std::mutex> lock(inputMutex);
    pendingEvents.push_back(std::move(event));
}

bool ImGuiHost::keyPressed(const juce::KeyPress& key) {
    syncModifierKeys(key.getModifiers());

    if (const int imguiKey = translateKeyCodeToImGuiKey(key.getKeyCode()); imguiKey != 0) {
        if (activeKeyCodes_.insert(key.getKeyCode()).second) {
            PendingEvent event;
            event.type = EventType::Key;
            event.key = imguiKey;
            event.down = true;

            std::lock_guard<std::mutex> lock(inputMutex);
            pendingEvents.push_back(std::move(event));
        }
    }

    const auto textCharacter = key.getTextCharacter();
    if (textCharacter >= 32 && !key.getModifiers().isCtrlDown() && !key.getModifiers().isCommandDown()) {
        PendingEvent event;
        event.type = EventType::Char;
        event.codepoint = static_cast<unsigned int>(textCharacter);

        std::lock_guard<std::mutex> lock(inputMutex);
        pendingEvents.push_back(std::move(event));
    }

    return true;
}

bool ImGuiHost::keyStateChanged(bool isKeyDown) {
    juce::ignoreUnused(isKeyDown);
    syncModifierKeys(juce::ModifierKeys::getCurrentModifiersRealtime());
    releaseInactiveKeys();
    return true;
}

void ImGuiHost::focusGained(FocusChangeType cause) {
    juce::ignoreUnused(cause);
    queueFocus(true);
}

void ImGuiHost::focusLost(FocusChangeType cause) {
    juce::ignoreUnused(cause);
    queueFocus(false);
    releaseAllMouseButtons();
    releaseAllActiveKeys();
    syncModifierKeys(juce::ModifierKeys::noModifiers);
}

void ImGuiHost::newOpenGLContextCreated() {
    logMainImGuiHostEvent("newOpenGLContextCreated", this, &openGLContext);
    IMGUI_CHECKVERSION();
    auto* context = ImGui::CreateContext();
    imguiContext = context;
    ImGui::SetCurrentContext(context);

    auto& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.BackendPlatformName = "manifold_juce";

    ImGui::StyleColorsDark();
    auto& style = ImGui::GetStyle();
    style.WindowRounding = 0.0f;
    style.FrameRounding = 4.0f;
    style.GrabRounding = 4.0f;
    style.ScrollbarRounding = 4.0f;
    style.TabRounding = 4.0f;
    style.WindowBorderSize = 0.0f;
    style.WindowPadding = ImVec2(0.0f, 0.0f);

    ImGui_ImplOpenGL3_Init("#version 150");

    contextReady_.store(true, std::memory_order_relaxed);
    queueFocus(hasKeyboardFocus(true));
}

void ImGuiHost::renderOpenGL() {
    if (getWidth() <= 0 || getHeight() <= 0 || !isShowing()) {
        wantCaptureMouse_.store(false, std::memory_order_relaxed);
        wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
        lastVertexCount_.store(0, std::memory_order_relaxed);
        lastIndexCount_.store(0, std::memory_order_relaxed);
        return;
    }

    auto* context = reinterpret_cast<ImGuiContext*>(imguiContext);
    if (context == nullptr) {
        return;
    }

    const auto start = std::chrono::steady_clock::now();
    ImGui::SetCurrentContext(context);

    auto& io = ImGui::GetIO();
    const auto scale = static_cast<float>(openGLContext.getRenderingScale());
    const auto width = std::max(1, getWidth());
    const auto height = std::max(1, getHeight());
    const auto framebufferWidth = std::max(1, juce::roundToInt(scale * static_cast<float>(width)));
    const auto framebufferHeight = std::max(1, juce::roundToInt(scale * static_cast<float>(height)));

    io.DisplaySize = ImVec2(static_cast<float>(width), static_cast<float>(height));
    io.DisplayFramebufferScale = ImVec2(scale, scale);

    {
        std::lock_guard<std::mutex> lock(inputMutex);
        for (const auto& event : pendingEvents) {
            switch (event.type) {
                case EventType::MousePos:
                    io.AddMousePosEvent(event.x, event.y);
                    break;
                case EventType::MouseButton:
                    io.AddMouseButtonEvent(event.button, event.down);
                    break;
                case EventType::MouseWheel:
                    io.AddMouseWheelEvent(event.x, event.y);
                    break;
                case EventType::Key:
                    io.AddKeyEvent(static_cast<ImGuiKey>(event.key), event.down);
                    break;
                case EventType::Char:
                    io.AddInputCharacter(event.codepoint);
                    break;
                case EventType::Focus:
                    io.AddFocusEvent(event.focused);
                    break;
            }
        }
        pendingEvents.clear();
    }

    syncMouseButtons(juce::ModifierKeys::getCurrentModifiersRealtime());

    {
        std::lock_guard<std::mutex> lock(inputMutex);
        for (const auto& event : pendingEvents) {
            if (event.type == EventType::MouseButton) {
                io.AddMouseButtonEvent(event.button, event.down);
            }
        }
        pendingEvents.clear();
    }

    glViewport(0, 0, framebufferWidth, framebufferHeight);
    glDisable(GL_SCISSOR_TEST);

    if (!renderActive_.load(std::memory_order_relaxed)) {
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        wantCaptureMouse_.store(false, std::memory_order_relaxed);
        wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
        lastVertexCount_.store(0, std::memory_order_relaxed);
        lastIndexCount_.store(0, std::memory_order_relaxed);
        lastRenderUs_.store(std::chrono::duration_cast<std::chrono::microseconds>(
                                 std::chrono::steady_clock::now() - start)
                                 .count(),
                             std::memory_order_relaxed);
        frameCount_.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    glClearColor(0.07f, 0.09f, 0.13f, 0.96f);
    glClear(GL_COLOR_BUFFER_BIT);

    ImGui_ImplOpenGL3_NewFrame();
    ImGui::NewFrame();

    ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(static_cast<float>(width), static_cast<float>(height)), ImGuiCond_Always);

    constexpr ImGuiWindowFlags windowFlags = ImGuiWindowFlags_NoDecoration
                                           | ImGuiWindowFlags_NoMove
                                           | ImGuiWindowFlags_NoResize
                                           | ImGuiWindowFlags_NoSavedSettings
                                           | ImGuiWindowFlags_NoBringToFrontOnFocus
                                           | ImGuiWindowFlags_NoBackground;

    ImGui::Begin("##ManifoldImGuiEditorHost", nullptr, windowFlags);

    {
        std::lock_guard<std::recursive_mutex> lock(documentMutex_);

        const bool windowFocused = ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows);
        if (windowFocused && ImGui::Shortcut(ImGuiMod_Ctrl | ImGuiKey_S)) {
            requestSave_.store(true, std::memory_order_relaxed);
        }
        if (windowFocused && ImGui::Shortcut(ImGuiMod_Ctrl | ImGuiKey_R)) {
            requestReload_.store(true, std::memory_order_relaxed);
        }
        if (windowFocused && ImGui::Shortcut(ImGuiMod_Ctrl | ImGuiKey_W)) {
            requestClose_.store(true, std::memory_order_relaxed);
        }

        if (documentLoaded_.load(std::memory_order_relaxed) && textEditor_ != nullptr) {
            const ImVec2 contentSize = ImGui::GetContentRegionAvail();
            textEditor_->Render("##ManifoldCodeEditor", windowFocused, contentSize, false);
        } else {
            ImGui::Dummy(ImVec2(12.0f, 12.0f));
            ImGui::SetCursorPos(ImVec2(12.0f, 12.0f));
            ImGui::TextUnformatted("No script loaded.");
        }

        refreshDocumentStatsLocked();
    }

    ImGui::End();

    ImGui::Render();
    auto* drawData = ImGui::GetDrawData();
    ImGui_ImplOpenGL3_RenderDrawData(drawData);

    int64_t vertexCount = 0;
    int64_t indexCount = 0;
    if (drawData != nullptr) {
        for (int listIndex = 0; listIndex < drawData->CmdListsCount; ++listIndex) {
            const auto* cmdList = drawData->CmdLists[listIndex];
            vertexCount += cmdList->VtxBuffer.Size;
            indexCount += cmdList->IdxBuffer.Size;
        }
    }

    wantCaptureMouse_.store(io.WantCaptureMouse, std::memory_order_relaxed);
    wantCaptureKeyboard_.store(io.WantCaptureKeyboard, std::memory_order_relaxed);
    frameCount_.fetch_add(1, std::memory_order_relaxed);
    lastVertexCount_.store(vertexCount, std::memory_order_relaxed);
    lastIndexCount_.store(indexCount, std::memory_order_relaxed);
    lastRenderUs_.store(std::chrono::duration_cast<std::chrono::microseconds>(
                             std::chrono::steady_clock::now() - start)
                             .count(),
                        std::memory_order_relaxed);
}

void ImGuiHost::openGLContextClosing() {
    logMainImGuiHostEvent("openGLContextClosing", this, &openGLContext);
    auto* context = reinterpret_cast<ImGuiContext*>(imguiContext);
    if (context != nullptr) {
        ImGui::SetCurrentContext(context);
        ImGui_ImplOpenGL3_Shutdown();
        ImGui::DestroyContext(context);
        imguiContext = nullptr;
    }

    contextReady_.store(false, std::memory_order_relaxed);
    wantCaptureMouse_.store(false, std::memory_order_relaxed);
    wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
}

void ImGuiHost::attachContextIfNeeded() {
    if (openGLContext.isAttached()) {
        return;
    }

    if (!isShowing() || getWidth() <= 0 || getHeight() <= 0) {
        return;
    }

    logMainImGuiHostEvent("attachContext", this, &openGLContext);
    openGLContext.attachTo(*this);
}

void ImGuiHost::queueMousePosition(juce::Point<float> position) {
    PendingEvent event;
    event.type = EventType::MousePos;
    event.x = position.x;
    event.y = position.y;

    std::lock_guard<std::mutex> lock(inputMutex);
    pendingEvents.push_back(std::move(event));
}

void ImGuiHost::queueCurrentMousePosition() {
    if (!isShowing()) {
        return;
    }

    const auto screenPos = juce::Desktop::getInstance().getMainMouseSource().getScreenPosition();
    const juce::Point<int> screenPosInt(juce::roundToInt(screenPos.x), juce::roundToInt(screenPos.y));
    const auto localPos = getLocalPoint(nullptr, screenPosInt).toFloat();
    queueMousePosition(localPos);
}

void ImGuiHost::syncMouseButtons(const juce::ModifierKeys& mods) {
    const bool nextLeft = mods.isLeftButtonDown();
    const bool nextRight = mods.isRightButtonDown();
    const bool nextMiddle = mods.isMiddleButtonDown();

    std::lock_guard<std::mutex> lock(inputMutex);

    const auto pushMouseButton = [&](bool& current, int button, bool nextState) {
        if (current == nextState) {
            return;
        }

        current = nextState;
        PendingEvent event;
        event.type = EventType::MouseButton;
        event.button = button;
        event.down = nextState;
        pendingEvents.push_back(std::move(event));
    };

    pushMouseButton(leftMouseDown_, 0, nextLeft);
    pushMouseButton(rightMouseDown_, 1, nextRight);
    pushMouseButton(middleMouseDown_, 2, nextMiddle);
}

void ImGuiHost::syncModifierKeys(const juce::ModifierKeys& mods) {
    const bool nextCtrl = mods.isCtrlDown();
    const bool nextShift = mods.isShiftDown();
    const bool nextAlt = mods.isAltDown();
    const bool nextSuper = mods.isCommandDown();

    std::lock_guard<std::mutex> lock(inputMutex);

    const auto syncMod = [&](bool& state, int key, bool nextState) {
        if (state == nextState) {
            return;
        }

        state = nextState;
        PendingEvent event;
        event.type = EventType::Key;
        event.key = key;
        event.down = nextState;
        pendingEvents.push_back(std::move(event));
    };

    syncMod(ctrlDown, ImGuiMod_Ctrl, nextCtrl);
    syncMod(shiftDown, ImGuiMod_Shift, nextShift);
    syncMod(altDown, ImGuiMod_Alt, nextAlt);
    syncMod(superDown, ImGuiMod_Super, nextSuper);
}

void ImGuiHost::releaseAllMouseButtons() {
    std::lock_guard<std::mutex> lock(inputMutex);

    const auto releaseButton = [&](bool& current, int button) {
        if (!current) {
            return;
        }

        current = false;
        PendingEvent event;
        event.type = EventType::MouseButton;
        event.button = button;
        event.down = false;
        pendingEvents.push_back(std::move(event));
    };

    releaseButton(leftMouseDown_, 0);
    releaseButton(rightMouseDown_, 1);
    releaseButton(middleMouseDown_, 2);
}

void ImGuiHost::releaseInactiveKeys() {
    if (activeKeyCodes_.empty()) {
        return;
    }

    std::lock_guard<std::mutex> lock(inputMutex);
    for (auto it = activeKeyCodes_.begin(); it != activeKeyCodes_.end();) {
        if (juce::KeyPress::isKeyCurrentlyDown(*it)) {
            ++it;
            continue;
        }

        const int imguiKey = translateKeyCodeToImGuiKey(*it);
        if (imguiKey != 0) {
            PendingEvent event;
            event.type = EventType::Key;
            event.key = imguiKey;
            event.down = false;
            pendingEvents.push_back(std::move(event));
        }
        it = activeKeyCodes_.erase(it);
    }
}

void ImGuiHost::releaseAllActiveKeys() {
    if (activeKeyCodes_.empty()) {
        return;
    }

    std::lock_guard<std::mutex> lock(inputMutex);
    for (const int keyCode : activeKeyCodes_) {
        const int imguiKey = translateKeyCodeToImGuiKey(keyCode);
        if (imguiKey == 0) {
            continue;
        }

        PendingEvent event;
        event.type = EventType::Key;
        event.key = imguiKey;
        event.down = false;
        pendingEvents.push_back(std::move(event));
    }
    activeKeyCodes_.clear();
}

void ImGuiHost::queueFocus(bool focused) {
    PendingEvent event;
    event.type = EventType::Focus;
    event.focused = focused;

    std::lock_guard<std::mutex> lock(inputMutex);
    pendingEvents.push_back(std::move(event));
}

void ImGuiHost::refreshDocumentStatsLocked() {
    const bool loaded = textEditor_ != nullptr && documentFile_.getFullPathName().isNotEmpty();
    documentLoaded_.store(loaded, std::memory_order_relaxed);

    if (!loaded || textEditor_ == nullptr) {
        documentDirty_.store(false, std::memory_order_relaxed);
        documentLineCount_.store(0, std::memory_order_relaxed);
        return;
    }

    const auto currentText = textEditor_->GetText();
    documentDirty_.store(currentText != documentOriginalText_, std::memory_order_relaxed);
    documentLineCount_.store(textEditor_->GetLineCount(), std::memory_order_relaxed);
}

void ImGuiHost::updateLanguageDefinitionForPathLocked(const juce::File& file) {
    if (textEditor_ == nullptr) {
        return;
    }

    const auto extension = file.getFileExtension().toLowerCase();
    if (extension == ".lua") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Lua);
    } else if (extension == ".json" || extension == ".json5") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Json);
    } else if (extension == ".sql") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Sql);
    } else if (extension == ".glsl") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Glsl);
    } else if (extension == ".hlsl") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Hlsl);
    } else if (extension == ".py") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Python);
    } else if (extension == ".cs") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Cs);
    } else if (extension == ".c") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::C);
    } else if (extension == ".cpp" || extension == ".cxx" || extension == ".cc"
               || extension == ".h" || extension == ".hpp" || extension == ".hh") {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::Cpp);
    } else {
        textEditor_->SetLanguageDefinition(TextEditor::LanguageDefinitionId::None);
    }
}

int ImGuiHost::translateKeyCodeToImGuiKey(int keyCode) {
    if (keyCode == juce::KeyPress::tabKey) return ImGuiKey_Tab;
    if (keyCode == juce::KeyPress::leftKey) return ImGuiKey_LeftArrow;
    if (keyCode == juce::KeyPress::rightKey) return ImGuiKey_RightArrow;
    if (keyCode == juce::KeyPress::upKey) return ImGuiKey_UpArrow;
    if (keyCode == juce::KeyPress::downKey) return ImGuiKey_DownArrow;
    if (keyCode == juce::KeyPress::pageUpKey) return ImGuiKey_PageUp;
    if (keyCode == juce::KeyPress::pageDownKey) return ImGuiKey_PageDown;
    if (keyCode == juce::KeyPress::homeKey) return ImGuiKey_Home;
    if (keyCode == juce::KeyPress::endKey) return ImGuiKey_End;
    if (keyCode == juce::KeyPress::insertKey) return ImGuiKey_Insert;
    if (keyCode == juce::KeyPress::deleteKey) return ImGuiKey_Delete;
    if (keyCode == juce::KeyPress::backspaceKey) return ImGuiKey_Backspace;
    if (keyCode == juce::KeyPress::returnKey) return ImGuiKey_Enter;
    if (keyCode == juce::KeyPress::escapeKey) return ImGuiKey_Escape;
    if (keyCode == juce::KeyPress::spaceKey) return ImGuiKey_Space;

    if (keyCode >= '0' && keyCode <= '9') {
        return ImGuiKey_0 + (keyCode - '0');
    }

    if (keyCode >= 'a' && keyCode <= 'z') {
        return ImGuiKey_A + (keyCode - 'a');
    }

    if (keyCode >= 'A' && keyCode <= 'Z') {
        return ImGuiKey_A + (keyCode - 'A');
    }

    if (keyCode == ';') return ImGuiKey_Semicolon;
    if (keyCode == '\'') return ImGuiKey_Apostrophe;
    if (keyCode == ',') return ImGuiKey_Comma;
    if (keyCode == '-') return ImGuiKey_Minus;
    if (keyCode == '.') return ImGuiKey_Period;
    if (keyCode == '/') return ImGuiKey_Slash;
    if (keyCode == '=') return ImGuiKey_Equal;
    if (keyCode == '[') return ImGuiKey_LeftBracket;
    if (keyCode == '\\') return ImGuiKey_Backslash;
    if (keyCode == ']') return ImGuiKey_RightBracket;
    if (keyCode == '`') return ImGuiKey_GraveAccent;

    return 0;
}
