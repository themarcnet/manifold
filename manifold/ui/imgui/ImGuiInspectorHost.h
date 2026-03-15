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

class ImGuiInspectorHost : public juce::Component, private juce::OpenGLRenderer {
public:
    enum class Mode {
        HierarchyProperties,
        ScriptInspector,
    };

    struct BoundsInfo {
        bool enabled = false;
        int x = 0;
        int y = 0;
        int w = 1;
        int h = 1;
    };

    struct InspectorRow {
        int rowIndex = -1;
        bool section = false;
        bool interactive = false;
        bool selected = false;
        std::string key;
        std::string value;
    };

    struct ActiveProperty {
        bool valid = false;
        bool mixed = false;
        std::string key;
        std::string path;
        std::string editorType;
        std::string displayValue;
        double numberValue = 0.0;
        double minValue = 0.0;
        double maxValue = 0.0;
        double stepValue = 0.0;
        bool hasMin = false;
        bool hasMax = false;
        bool boolValue = false;
        std::string textValue;
        std::uint32_t colorValue = 0xff000000u;
        std::vector<std::string> enumLabels;
        int enumSelectedIndex = 1;
    };

    struct DeclaredParam {
        std::string path;
        std::string defaultValue;
    };

    struct RuntimeParam {
        std::string endpointPath;
        std::string path;
        std::string displayValue;
        bool active = false;
        bool hasValue = false;
        double value = 0.0;
        bool hasMin = false;
        bool hasMax = false;
        double minValue = 0.0;
        double maxValue = 1.0;
        double stepValue = 0.0;
    };

    struct GraphNode {
        std::string var;
        std::string prim;
    };

    struct GraphEdge {
        int fromIndex = -1;
        int toIndex = -1;
    };

    struct ScriptInspectorData {
        bool hasSelection = false;
        std::string name;
        std::string kind;
        std::string ownership;
        std::string path;
        std::string text;
        int64_t syncToken = -1;
        bool inlineReadOnly = true;
        bool hasStructuredStatus = false;
        bool structuredDirty = false;
        std::string projectLastError;
        std::vector<DeclaredParam> declaredParams;
        std::vector<RuntimeParam> runtimeParams;
        std::string runtimeStatus;
        bool editorCollapsed = false;
        bool graphCollapsed = false;
        int graphPanX = 0;
        int graphPanY = 0;
        std::vector<GraphNode> graphNodes;
        std::vector<GraphEdge> graphEdges;
    };

    struct ActionRequests {
        int selectRowIndex = -1;
        bool setBoundsX = false;
        bool setBoundsY = false;
        bool setBoundsW = false;
        bool setBoundsH = false;
        int boundsX = 0;
        int boundsY = 0;
        int boundsW = 1;
        int boundsH = 1;
        bool applyNumber = false;
        double numberValue = 0.0;
        bool applyBool = false;
        bool boolValue = false;
        bool applyText = false;
        std::string textValue;
        bool applyColor = false;
        std::uint32_t colorValue = 0xff000000u;
        int applyEnumIndex = -1;
        bool runPreview = false;
        bool stopPreview = false;
        bool setEditorCollapsed = false;
        bool editorCollapsed = false;
        bool setGraphCollapsed = false;
        bool graphCollapsed = false;
        bool setGraphPan = false;
        int graphPanX = 0;
        int graphPanY = 0;
        bool applyRuntimeParam = false;
        std::string runtimeParamEndpointPath;
        double runtimeParamValue = 0.0;
    };

    ImGuiInspectorHost();
    ~ImGuiInspectorHost() override;

    void configureData(const BoundsInfo& bounds,
                       const std::vector<InspectorRow>& rows,
                       const ActiveProperty& activeProperty);
    void configureScriptData(const ScriptInspectorData& scriptData);
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
    void updateInlineLanguageDefinitionForPathLocked(const juce::File& file);

    static int translateKeyCodeToImGuiKey(int keyCode);

    juce::OpenGLContext openGLContext;
    void* imguiContext = nullptr;

    std::mutex inputMutex;
    std::vector<PendingEvent> pendingEvents;

    mutable std::mutex dataMutex_;
    Mode mode_ = Mode::HierarchyProperties;
    BoundsInfo bounds_;
    std::vector<InspectorRow> rows_;
    ActiveProperty activeProperty_;
    ScriptInspectorData scriptData_;
    std::string textEditBuffer_;
    std::string textEditPath_;
    std::string textEditLastSourceValue_;
    std::unique_ptr<TextEditor> inlineTextEditor_;
    juce::File inlineDocumentFile_;
    int64_t inlineAppliedSyncToken_ = -1;

    bool leftMouseDown_ = false;
    bool rightMouseDown_ = false;
    bool middleMouseDown_ = false;
    bool ctrlDown_ = false;
    bool shiftDown_ = false;
    bool altDown_ = false;
    bool superDown_ = false;
    std::unordered_set<int> activeKeyCodes_;

    std::atomic<int> requestSelectRowIndex_{-1};
    std::atomic<bool> requestSetBoundsX_{false};
    std::atomic<bool> requestSetBoundsY_{false};
    std::atomic<bool> requestSetBoundsW_{false};
    std::atomic<bool> requestSetBoundsH_{false};
    std::atomic<int> requestBoundsX_{0};
    std::atomic<int> requestBoundsY_{0};
    std::atomic<int> requestBoundsW_{1};
    std::atomic<int> requestBoundsH_{1};
    std::atomic<bool> requestApplyNumber_{false};
    std::atomic<double> requestNumberValue_{0.0};
    std::atomic<bool> requestApplyBool_{false};
    std::atomic<bool> requestBoolValue_{false};
    std::atomic<bool> requestApplyText_{false};
    std::mutex textRequestMutex_;
    std::string requestTextValue_;
    std::atomic<bool> requestApplyColor_{false};
    std::atomic<std::uint32_t> requestColorValue_{0xff000000u};
    std::atomic<int> requestApplyEnumIndex_{-1};

    std::mutex scriptRequestMutex_;
    bool requestRunPreview_ = false;
    bool requestStopPreview_ = false;
    bool requestSetEditorCollapsed_ = false;
    bool requestEditorCollapsed_ = false;
    bool requestSetGraphCollapsed_ = false;
    bool requestGraphCollapsed_ = false;
    bool requestSetGraphPan_ = false;
    int requestGraphPanX_ = 0;
    int requestGraphPanY_ = 0;
    bool requestApplyRuntimeParam_ = false;
    std::string requestRuntimeParamEndpointPath_;
    double requestRuntimeParamValue_ = 0.0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ImGuiInspectorHost)
};
