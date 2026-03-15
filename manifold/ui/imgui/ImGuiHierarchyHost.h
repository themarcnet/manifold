#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

class ImGuiHierarchyHost : public juce::Component, private juce::OpenGLRenderer {
public:
    struct TreeRow {
        int depth = 0;
        bool selected = false;
        std::string type;
        std::string name;
        std::string path;
    };

    struct ActionRequests {
        int selectIndex = -1;
    };

    ImGuiHierarchyHost();
    ~ImGuiHierarchyHost() override;

    void configureRows(const std::vector<TreeRow>& rows);
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
    std::vector<TreeRow> rows_;

    bool leftMouseDown_ = false;
    bool rightMouseDown_ = false;
    bool middleMouseDown_ = false;

    std::atomic<int> requestSelectIndex_{-1};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ImGuiHierarchyHost)
};
