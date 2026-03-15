#include "GRPCServer.h"

#include <grpc/grpc.h>
#include <grpcpp/server_builder.h>
#include <grpcpp/server_context.h>

#include <juce_core/juce_core.h>

namespace manifold {
namespace grpc {

// ============================================================================
// ManifoldServiceImpl
// ============================================================================

ManifoldServiceImpl::ManifoldServiceImpl(ScriptableProcessor* processor)
    : processor_(processor) {
}

ManifoldServiceImpl::~ManifoldServiceImpl() {
    stop();
}

void ManifoldServiceImpl::start(int port) {
    if (running_.load()) {
        return;
    }
    port_ = port;

    ::grpc::ServerBuilder builder;
    builder.AddListeningPort("[::]:" + std::to_string(port), 
                             ::grpc::InsecureServerCredentials());
    builder.RegisterService(this);
    
    server_ = builder.BuildAndStart();
    running_.store(true);
    
    std::fprintf(stderr, "gRPC server listening on port %d\n", port);
}

void ManifoldServiceImpl::stop() {
    if (!running_.load()) {
        return;
    }
    running_.store(false);
    
    if (server_) {
        server_->Shutdown();
        server_->Wait();
        server_.reset();
    }
}

// -------------------------------------------------------------------------
// Parameter Control
// -------------------------------------------------------------------------

::grpc::Status ManifoldServiceImpl::SetParameter(
    ::grpc::ServerContext* context,
    const ::manifold::proto::SetParameterRequest* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    
    if (!processor_) {
        response->set_success(false);
        response->set_error_message("Processor not available");
        return ::grpc::Status(::grpc::StatusCode::UNAVAILABLE, "Processor not available");
    }

    float value = 0.0f;
    switch (request->value().value_case()) {
        case ::manifold::proto::ParameterValue::kFloatValue:
            value = request->value().float_value();
            break;
        case ::manifold::proto::ParameterValue::kIntValue:
            value = static_cast<float>(request->value().int_value());
            break;
        case ::manifold::proto::ParameterValue::kBoolValue:
            value = request->value().bool_value() ? 1.0f : 0.0f;
            break;
        default:
            response->set_success(false);
            response->set_error_message("Unsupported value type");
            response->set_error_code("E_UNSUPPORTED_VALUE_TYPE");
            return ::grpc::Status::OK;
    }

    bool success = processor_->setParamByPath(request->path(), value);
    response->set_success(success);
    
    if (!success) {
        response->set_error_message("Failed to set parameter: " + request->path());
        response->set_error_code("E_SET_REJECTED");
    }
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::GetParameter(
    ::grpc::ServerContext* context,
    const ::manifold::proto::GetParameterRequest* request,
    ::manifold::proto::GetParameterResponse* response) {
    
    juce::ignoreUnused(context);
    
    if (!processor_) {
        response->set_exists(false);
        return ::grpc::Status(::grpc::StatusCode::UNAVAILABLE, "Processor not available");
    }

    response->set_path(request->path());
    
    if (!processor_->hasEndpoint(request->path())) {
        response->set_exists(false);
        return ::grpc::Status::OK;
    }

    float value = processor_->getParamByPath(request->path());
    response->mutable_value()->set_float_value(value);
    response->set_exists(true);
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::Trigger(
    ::grpc::ServerContext* context,
    const ::manifold::proto::TriggerRequest* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    
    // Trigger is just a SET with value 1.0f
    bool success = processor_->setParamByPath(request->path(), 1.0f);
    response->set_success(success);
    
    if (!success) {
        response->set_error_message("Failed to trigger: " + request->path());
        response->set_error_code("E_TRIGGER_REJECTED");
    }
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::SetParameters(
    ::grpc::ServerContext* context,
    ::grpc::ServerReader<::manifold::proto::SetParameterRequest>* reader,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    
    ::manifold::proto::SetParameterRequest request;
    bool allSuccess = true;
    std::string lastError;
    
    while (reader->Read(&request)) {
        bool success = processor_->setParamByPath(request.path(), 
            request.value().has_float_value() ? request.value().float_value() : 
            request.value().has_int_value() ? static_cast<float>(request.value().int_value()) :
            request.value().has_bool_value() ? (request.value().bool_value() ? 1.0f : 0.0f) : 0.0f);
        
        if (!success) {
            allSuccess = false;
            lastError = "Failed to set: " + request.path();
        }
    }
    
    response->set_success(allSuccess);
    if (!allSuccess) {
        response->set_error_message(lastError);
    }
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::GetParameters(
    ::grpc::ServerContext* context,
    ::grpc::ServerReader<::manifold::proto::GetParameterRequest>* reader,
    ::grpc::ServerWriter<::manifold::proto::GetParameterResponse>* writer) {
    
    juce::ignoreUnused(context);
    
    ::manifold::proto::GetParameterRequest request;
    ::manifold::proto::GetParameterResponse response;
    
    while (reader->Read(&request)) {
        response.Clear();
        response.set_path(request.path());
        
        if (processor_->hasEndpoint(request.path())) {
            response.set_exists(true);
            response.mutable_value()->set_float_value(processor_->getParamByPath(request.path()));
        } else {
            response.set_exists(false);
        }
        
        writer->Write(response);
    }
    
    return ::grpc::Status::OK;
}

// -------------------------------------------------------------------------
// State Streaming
// -------------------------------------------------------------------------

::grpc::Status ManifoldServiceImpl::SubscribeState(
    ::grpc::ServerContext* context,
    const ::manifold::proto::StateFilter* request,
    ::grpc::ServerWriter<::manifold::proto::FullState>* writer) {
    
    juce::ignoreUnused(request);
    
    {
        std::lock_guard<std::mutex> lock(subscribersMutex_);
        stateSubscribers_.push_back(writer);
    }
    
    // Send initial state
    writer->Write(captureFullState());
    
    // Keep connection alive until client disconnects
    while (!context->IsCancelled() && running_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    {
        std::lock_guard<std::mutex> lock(subscribersMutex_);
        auto it = std::find(stateSubscribers_.begin(), stateSubscribers_.end(), writer);
        if (it != stateSubscribers_.end()) {
            stateSubscribers_.erase(it);
        }
    }
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::SubscribeStateDeltas(
    ::grpc::ServerContext* context,
    const ::manifold::proto::StateFilter* request,
    ::grpc::ServerWriter<::manifold::proto::StateDelta>* writer) {
    
    juce::ignoreUnused(request);
    
    {
        std::lock_guard<std::mutex> lock(subscribersMutex_);
        deltaSubscribers_.push_back(writer);
    }
    
    // Keep connection alive
    while (!context->IsCancelled() && running_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    
    {
        std::lock_guard<std::mutex> lock(subscribersMutex_);
        auto it = std::find(deltaSubscribers_.begin(), deltaSubscribers_.end(), writer);
        if (it != deltaSubscribers_.end()) {
            deltaSubscribers_.erase(it);
        }
    }
    
    return ::grpc::Status::OK;
}

// -------------------------------------------------------------------------
// Bidirectional Control Stream
// -------------------------------------------------------------------------

::grpc::Status ManifoldServiceImpl::ControlStream(
    ::grpc::ServerContext* context,
    ::grpc::ServerReaderWriter<::manifold::proto::ControlEvent,
                               ::manifold::proto::ControlCommand>* stream) {
    
    {
        std::lock_guard<std::mutex> lock(subscribersMutex_);
        controlStreams_.push_back(stream);
    }
    
    // Read commands from client
    ::manifold::proto::ControlCommand cmd;
    while (stream->Read(&cmd)) {
        // Process command
        if (cmd.has_set_param()) {
            const auto& set = cmd.set_param();
            float value = set.value().has_float_value() ? set.value().float_value() :
                         set.value().has_int_value() ? static_cast<float>(set.value().int_value()) :
                         set.value().has_bool_value() ? (set.value().bool_value() ? 1.0f : 0.0f) : 0.0f;
            processor_->setParamByPath(set.path(), value);
        } else if (cmd.has_trigger()) {
            processor_->setParamByPath(cmd.trigger().path(), 1.0f);
        }
    }
    
    {
        std::lock_guard<std::mutex> lock(subscribersMutex_);
        auto it = std::find(controlStreams_.begin(), controlStreams_.end(), stream);
        if (it != controlStreams_.end()) {
            controlStreams_.erase(it);
        }
    }
    
    return ::grpc::Status::OK;
}

// -------------------------------------------------------------------------
// DSP Scripting
// -------------------------------------------------------------------------

::grpc::Status ManifoldServiceImpl::LoadDspScript(
    ::grpc::ServerContext* context,
    const ::manifold::proto::DspScript* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    
    bool success = processor_->loadDspScriptFromString(
        request->source(), 
        request->source_name(),
        request->slot()
    );
    
    response->set_success(success);
    if (!success) {
        response->set_error_message(processor_->getDspScriptLastError());
    }
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::ReloadDspSlot(
    ::grpc::ServerContext* context,
    const ::google::protobuf::StringValue* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    
    bool success = processor_->reloadDspScript(request->value());
    response->set_success(success);
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::UnloadDspSlot(
    ::grpc::ServerContext* context,
    const ::google::protobuf::StringValue* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    
    bool success = processor_->unloadDspSlot(request->value());
    response->set_success(success);
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::GetDspSlotInfo(
    ::grpc::ServerContext* context,
    const ::google::protobuf::StringValue* request,
    ::manifold::proto::DspSlotInfo* response) {
    
    juce::ignoreUnused(context);
    
    response->set_slot(request->value());
    response->set_loaded(processor_->isDspSlotLoaded(request->value()));
    
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::ListDspSlots(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::DspSlotList* response) {
    
    juce::ignoreUnused(context, request);
    
    // Always includes "default"
    auto* defaultSlot = response->add_slots();
    defaultSlot->set_slot("default");
    defaultSlot->set_loaded(processor_->isDspScriptLoaded());
    
    return ::grpc::Status::OK;
}

// -------------------------------------------------------------------------
// Transport
// -------------------------------------------------------------------------

::grpc::Status ManifoldServiceImpl::Play(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context, request);
    processor_->setParamByPath("/core/behavior/transport", 1.0f);
    response->set_success(true);
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::Stop(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context, request);
    processor_->setParamByPath("/core/behavior/transport", 0.0f);
    response->set_success(true);
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::Pause(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context, request);
    processor_->setParamByPath("/core/behavior/transport", 2.0f);
    response->set_success(true);
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::Record(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context, request);
    processor_->setParamByPath("/core/behavior/recording", 1.0f);
    response->set_success(true);
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::Commit(
    ::grpc::ServerContext* context,
    const ::manifold::proto::CommitRequest* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    processor_->setParamByPath("/core/behavior/commit", request->bars());
    response->set_success(true);
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::SetTempo(
    ::grpc::ServerContext* context,
    const ::manifold::proto::SetTempoRequest* request,
    ::manifold::proto::Ack* response) {
    
    juce::ignoreUnused(context);
    processor_->setParamByPath("/core/behavior/tempo", request->bpm());
    response->set_success(true);
    return ::grpc::Status::OK;
}

// -------------------------------------------------------------------------
// Query/Introspection
// -------------------------------------------------------------------------

::grpc::Status ManifoldServiceImpl::GetFullState(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::FullState* response) {
    
    juce::ignoreUnused(context, request);
    *response = captureFullState();
    return ::grpc::Status::OK;
}

::grpc::Status ManifoldServiceImpl::GetDiagnostics(
    ::grpc::ServerContext* context,
    const ::manifold::proto::Empty* request,
    ::manifold::proto::Diagnostics* response) {
    
    juce::ignoreUnused(context, request);
    
    response->set_uptime_seconds(processor_->getPlayTimeSamples() / processor_->getSampleRate());
    
    return ::grpc::Status::OK;
}

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------

::manifold::proto::FullState ManifoldServiceImpl::captureFullState() {
    ::manifold::proto::FullState state;
    
    state.set_tempo(processor_->getTempo());
    state.set_target_bpm(processor_->getTargetBPM());
    state.set_samples_per_bar(processor_->getSamplesPerBar());
    state.set_sample_rate(processor_->getSampleRate());
    state.set_master_volume(processor_->getMasterVolume());
    state.set_input_volume(processor_->getInputVolume());
    state.set_passthrough(processor_->isPassthroughEnabled());
    state.set_recording(processor_->isRecording());
    state.set_overdub(processor_->isOverdubEnabled());
    state.set_active_layer(processor_->getActiveLayerIndex());
    state.set_forward_armed(processor_->isForwardCommitArmed());
    state.set_forward_bars(processor_->getForwardCommitBars());
    state.set_graph_enabled(processor_->isGraphProcessingEnabled());
    
    // Link state
    auto* link = state.mutable_link();
    link->set_enabled(processor_->isLinkEnabled());
    link->set_tempo_sync(processor_->isLinkTempoSyncEnabled());
    link->set_start_stop_sync(processor_->isLinkStartStopSyncEnabled());
    link->set_peers(processor_->getLinkNumPeers());
    link->set_playing(processor_->isLinkPlaying());
    link->set_beat(processor_->getLinkBeat());
    link->set_phase(processor_->getLinkPhase());
    
    return state;
}

void ManifoldServiceImpl::broadcastStateUpdate(const ::manifold::proto::StateDelta& delta) {
    std::lock_guard<std::mutex> lock(subscribersMutex_);
    for (auto* writer : deltaSubscribers_) {
        writer->Write(delta);
    }
}

// -------------------------------------------------------------------------
// GRPCServer
// -------------------------------------------------------------------------

GRPCServer::GRPCServer() = default;

GRPCServer::~GRPCServer() {
    stop();
}

void GRPCServer::start(ScriptableProcessor* processor, int port) {
    if (service_ && service_->isRunning()) {
        return;
    }
    
    service_ = std::make_unique<ManifoldServiceImpl>(processor);
    
    serverThread_ = std::thread([this, port]() {
        service_->start(port);
        
        // Keep thread alive while service runs
        while (!shouldStop_.load() && service_->isRunning()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    });
}

void GRPCServer::stop() {
    shouldStop_.store(true);
    if (service_) {
        service_->stop();
    }
    if (serverThread_.joinable()) {
        serverThread_.join();
    }
}

bool GRPCServer::isRunning() const {
    return service_ && service_->isRunning();
}

} // namespace grpc
} // namespace manifold
