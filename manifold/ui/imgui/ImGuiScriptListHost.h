#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

class ImGuiScriptListHost : public juce::Component, private juce::OpenGLRenderer {
public:
    struct ScriptRow {
        bool section = false;
        bool nonInteractive = false;
        bool selected = false;
        bool active = false;
        bool dirty = false;
        std::string kind;
        std::string ownership;
        std::string name;
        std::string label;
        std::string path;
    };

    struct ActionRequests {
        int selectIndex = -1;
        int openIndex = -1;
    };

    ImGuiScriptListHost();
    ~ImGuiScriptListHost() override;

    void configureRows(const std::vector<ScriptRow>& rows);
    ActionRequests consumeActionRequests();

    void paint(juce::Graphics& g) override;
    void resized() override;
    void visibilityChanged() override;

    void mouseMove(const juce::MouseEvent& e) override;
    void mouseDrag(const juce::MouseEvent& e) override;
    void mouseDown(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;
    void mouseExit(const juce::MouseEvent& e) override;
    void mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) override;
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
        Focus,
    };

    struct PendingEvent {
        EventType type = EventType::MousePos;
        float x = 0.0f;
        float y = 0.0f;
        int button = 0;
        bool down = false;
        bool focused = false;
    };

    void attachContextIfNeeded();
    void queueMousePosition(juce::Point<float> position);
    void queueCurrentMousePosition();
    void syncMouseButtons(const juce::ModifierKeys& mods);
    void releaseAllMouseButtons();
    void queueFocus(bool focused);

    juce::OpenGLContext openGLContext;
    void* imguiContext = nullptr;

    std::mutex inputMutex;
    std::vector<PendingEvent> pendingEvents;

    std::mutex rowsMutex_;
    std::vector<ScriptRow> rows_;

    bool leftMouseDown_ = false;
    bool rightMouseDown_ = false;
    bool middleMouseDown_ = false;

    std::atomic<int> requestSelectIndex_{-1};
    std::atomic<int> requestOpenIndex_{-1};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ImGuiScriptListHost)
};
