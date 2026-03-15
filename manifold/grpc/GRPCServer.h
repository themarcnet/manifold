#pragma once

#include "manifold.grpc.pb.h"

#include <grpc/grpc.h>
#include <grpcpp/server.h>
#include <grpcpp/server_builder.h>
#include <grpcpp/server_context.h>
#include <grpcpp/security/server_credentials.h>

#include "../primitives/scripting/ScriptableProcessor.h"
#include "../primitives/control/ControlServer.h"

#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

namespace manifold {
namespace grpc {

// ============================================================================
// gRPC Service Implementation
// ============================================================================

class ManifoldServiceImpl final : public manifold::proto::ManifoldControl::Service {
public:
    explicit ManifoldServiceImpl(ScriptableProcessor* processor);
    ~ManifoldServiceImpl() override;

    // Lifecycle
    void start(int port = 50051);
    void stop();
    bool isRunning() const { return running_.load(); }

    // -------------------------------------------------------------------------
    // Parameter Control
    // -------------------------------------------------------------------------
    ::grpc::Status SetParameter(
        ::grpc::ServerContext* context,
        const ::manifold::proto::SetParameterRequest* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status GetParameter(
        ::grpc::ServerContext* context,
        const ::manifold::proto::GetParameterRequest* request,
        ::manifold::proto::GetParameterResponse* response) override;

    ::grpc::Status Trigger(
        ::grpc::ServerContext* context,
        const ::manifold::proto::TriggerRequest* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SetParameters(
        ::grpc::ServerContext* context,
        ::grpc::ServerReader<::manifold::proto::SetParameterRequest>* reader,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status GetParameters(
        ::grpc::ServerContext* context,
        ::grpc::ServerReader<::manifold::proto::GetParameterRequest>* reader,
        ::grpc::ServerWriter<::manifold::proto::GetParameterResponse>* writer) override;

    // -------------------------------------------------------------------------
    // State Streaming
    // -------------------------------------------------------------------------
    ::grpc::Status SubscribeState(
        ::grpc::ServerContext* context,
        const ::manifold::proto::StateFilter* request,
        ::grpc::ServerWriter<::manifold::proto::FullState>* writer) override;

    ::grpc::Status SubscribeStateDeltas(
        ::grpc::ServerContext* context,
        const ::manifold::proto::StateFilter* request,
        ::grpc::ServerWriter<::manifold::proto::StateDelta>* writer) override;

    // -------------------------------------------------------------------------
    // Bidirectional Control Stream
    // -------------------------------------------------------------------------
    ::grpc::Status ControlStream(
        ::grpc::ServerContext* context,
        ::grpc::ServerReaderWriter<::manifold::proto::ControlEvent,
                                   ::manifold::proto::ControlCommand>* stream) override;

    // -------------------------------------------------------------------------
    // DSP Scripting
    // -------------------------------------------------------------------------
    ::grpc::Status LoadDspScript(
        ::grpc::ServerContext* context,
        const ::manifold::proto::DspScript* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status ReloadDspSlot(
        ::grpc::ServerContext* context,
        const ::manifold::proto::StringValue* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status UnloadDspSlot(
        ::grpc::ServerContext* context,
        const ::manifold::proto::StringValue* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status GetDspSlotInfo(
        ::grpc::ServerContext* context,
        const ::manifold::proto::StringValue* request,
        ::manifold::proto::DspSlotInfo* response) override;

    ::grpc::Status ListDspSlots(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::DspSlotList* response) override;

    // -------------------------------------------------------------------------
    // UI Scripting
    // -------------------------------------------------------------------------
    ::grpc::Status SwitchUiScript(
        ::grpc::ServerContext* context,
        const ::manifold::proto::UiScriptRequest* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status GetUiScriptInfo(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::UiScriptInfo* response) override;

    ::grpc::Status ListAvailableUiScripts(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::UiScriptList* response) override;

    // -------------------------------------------------------------------------
    // Audio Visualization
    // -------------------------------------------------------------------------
    ::grpc::Status GetWaveform(
        ::grpc::ServerContext* context,
        const ::manifold::proto::WaveformRequest* request,
        ::manifold::proto::WaveformData* response) override;

    ::grpc::Status StreamWaveform(
        ::grpc::ServerContext* context,
        const ::manifold::proto::WaveformRequest* request,
        ::grpc::ServerWriter<::manifold::proto::WaveformData>* writer) override;

    // -------------------------------------------------------------------------
    // MIDI
    // -------------------------------------------------------------------------
    ::grpc::Status SendMidi(
        ::grpc::ServerContext* context,
        const ::manifold::proto::MidiMessage* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SendNoteOn(
        ::grpc::ServerContext* context,
        const ::manifold::proto::NoteOnEvent* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SendNoteOff(
        ::grpc::ServerContext* context,
        const ::manifold::proto::NoteOffEvent* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SendCC(
        ::grpc::ServerContext* context,
        const ::manifold::proto::ControlChangeEvent* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SendPitchBend(
        ::grpc::ServerContext* context,
        const ::manifold::proto::PitchBendEvent* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SubscribeMidi(
        ::grpc::ServerContext* context,
        const ::manifold::proto::EventFilter* request,
        ::grpc::ServerWriter<::manifold::proto::MidiEvent>* writer) override;

    // -------------------------------------------------------------------------
    // Transport
    // -------------------------------------------------------------------------
    ::grpc::Status Play(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status Stop(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status Pause(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status Record(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status Commit(
        ::grpc::ServerContext* context,
        const ::manifold::proto::CommitRequest* request,
        ::manifold::proto::Ack* response) override;

    ::grpc::Status SetTempo(
        ::grpc::ServerContext* context,
        const ::manifold::proto::SetTempoRequest* request,
        ::manifold::proto::Ack* response) override;

    // -------------------------------------------------------------------------
    // Query/Introspection
    // -------------------------------------------------------------------------
    ::grpc::Status GetFullState(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::FullState* response) override;

    ::grpc::Status ListParameters(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::ParameterList* response) override;

    ::grpc::Status GetGraphTopology(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::GraphTopology* response) override;

    ::grpc::Status GetDiagnostics(
        ::grpc::ServerContext* context,
        const ::manifold::proto::Empty* request,
        ::manifold::proto::Diagnostics* response) override;

    // -------------------------------------------------------------------------
    // State Broadcasting (called from audio thread)
    // -------------------------------------------------------------------------
    void broadcastStateUpdate(const ::manifold::proto::StateDelta& delta);
    void broadcastMidiEvent(const ::manifold::proto::MidiEvent& event);
    void broadcastControlEvent(const ::manifold::proto::ControlEvent& event);

private:
    ScriptableProcessor* processor_;
    std::unique_ptr<::grpc::Server> server_;
    std::atomic<bool> running_{false};
    int port_ = 50051;

    // Subscription management
    std::mutex subscribersMutex_;
    std::vector<::grpc::ServerWriter<::manifold::proto::FullState>*> stateSubscribers_;
    std::vector<::grpc::ServerWriter<::manifold::proto::StateDelta>*> deltaSubscribers_;
    std::vector<::grpc::ServerWriter<::manifold::proto::MidiEvent>*> midiSubscribers_;
    std::vector<::grpc::ServerReaderWriter<::manifold::proto::ControlEvent,
                                           ::manifold::proto::ControlCommand>*> controlStreams_;

    // State caching for delta computation
    std::mutex lastStateMutex_;
    ::manifold::proto::FullState lastState_;

    // Helpers
    bool postControlCommand(const ControlCommand& cmd);
    ::manifold::proto::FullState captureFullState();
    ::manifold::proto::StateDelta computeDelta(const ::manifold::proto::FullState& current);
    void cleanupSubscribers();
};

// ============================================================================
// GRPCServer - Wrapper for integration with BehaviorCoreProcessor
// ============================================================================

class GRPCServer {
public:
    GRPCServer();
    ~GRPCServer();

    void start(ScriptableProcessor* processor, int port = 50051);
    void stop();
    bool isRunning() const;

    // Access to service for broadcasting from audio thread
    ManifoldServiceImpl* getService() { return service_.get(); }

private:
    std::unique_ptr<ManifoldServiceImpl> service_;
    std::thread serverThread_;
    std::atomic<bool> shouldStop_{false};
};

} // namespace grpc
} // namespace manifold
