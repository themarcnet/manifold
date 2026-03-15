#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

class TextEditor;

class ImGuiHost : public juce::Component, private juce::OpenGLRenderer {
public:
    struct StatsSnapshot {
        bool contextReady = false;
        bool testWindowVisible = false;
        bool wantCaptureMouse = false;
        bool wantCaptureKeyboard = false;
        bool documentLoaded = false;
        bool documentDirty = false;
        int64_t frameCount = 0;
        int64_t lastRenderUs = 0;
        int64_t lastVertexCount = 0;
        int64_t lastIndexCount = 0;
        int64_t buttonClicks = 0;
        int64_t documentLineCount = 0;
    };

    struct ActionRequests {
        bool save = false;
        bool reload = false;
        bool close = false;
    };

    struct DocumentIdentity {
        std::string path;
        int64_t syncToken = -1;
        bool loaded = false;
    };

    ImGuiHost();
    ~ImGuiHost() override;

    StatsSnapshot getStatsSnapshot() const;
    ActionRequests consumeActionRequests();
    DocumentIdentity getDocumentIdentity() const;

    void configureDocument(const juce::File& file,
                           const std::string& text,
                           int64_t syncToken,
                           bool readOnly);
    void setRenderActive(bool active);
    bool isRenderActive() const;

    std::string getCurrentText() const;

    void paint(juce::Graphics& g) override;
    void resized() override;
    void visibilityChanged() override;

    void mouseMove(const juce::MouseEvent& e) override;
    void mouseDrag(const juce::MouseEvent& e) override;
    void mouseDown(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;
    void mouseExit(const juce::MouseEvent& e) override;
    void mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) override;

    bool keyPressed(const juce::KeyPress& key) override;
    bool keyStateChanged(bool isKeyDown) override;
    void focusGained(FocusChangeType cause) override;
    void focusLost(FocusChangeType cause) override;

private:
    void newOpenGLContextCreated() override;
    void renderOpenGL() override;
    void openGLContextClosing() override;

    enum class EventType {
        MousePos,
        MouseButton,
        MouseWheel,
        Key,
        Char,
        Focus,
    };

    struct PendingEvent {
        EventType type = EventType::MousePos;
        float x = 0.0f;
        float y = 0.0f;
        int button = 0;
        bool down = false;
        int key = 0;
        unsigned int codepoint = 0;
        bool focused = false;
    };

    void attachContextIfNeeded();
    void queueMousePosition(juce::Point<float> position);
    void queueCurrentMousePosition();
    void syncMouseButtons(const juce::ModifierKeys& mods);
    void syncModifierKeys(const juce::ModifierKeys& mods);
    void releaseAllMouseButtons();
    void releaseInactiveKeys();
    void releaseAllActiveKeys();
    void queueFocus(bool focused);
    void refreshDocumentStatsLocked();
    void updateLanguageDefinitionForPathLocked(const juce::File& file);

    static int translateKeyCodeToImGuiKey(int keyCode);

    juce::OpenGLContext openGLContext;
    void* imguiContext = nullptr;

    std::unique_ptr<TextEditor> textEditor_;
    juce::File documentFile_;
    std::string documentOriginalText_;
    int64_t appliedSyncToken_ = -1;
    bool readOnly_ = false;

    mutable std::mutex inputMutex;
    mutable std::recursive_mutex documentMutex_;
    std::vector<PendingEvent> pendingEvents;

    bool leftMouseDown_ = false;
    bool rightMouseDown_ = false;
    bool middleMouseDown_ = false;
    bool ctrlDown = false;
    bool shiftDown = false;
    bool altDown = false;
    bool superDown = false;
    std::unordered_set<int> activeKeyCodes_;

    std::atomic<bool> contextReady_{false};
    std::atomic<bool> renderActive_{true};
    std::atomic<bool> wantCaptureMouse_{false};
    std::atomic<bool> wantCaptureKeyboard_{false};
    std::atomic<bool> documentLoaded_{false};
    std::atomic<bool> documentDirty_{false};
    std::atomic<int64_t> frameCount_{0};
    std::atomic<int64_t> lastRenderUs_{0};
    std::atomic<int64_t> lastVertexCount_{0};
    std::atomic<int64_t> lastIndexCount_{0};
    std::atomic<int64_t> buttonClicks_{0};
    std::atomic<int64_t> documentLineCount_{0};

    std::atomic<bool> requestSave_{false};
    std::atomic<bool> requestReload_{false};
    std::atomic<bool> requestClose_{false};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ImGuiHost)
};
