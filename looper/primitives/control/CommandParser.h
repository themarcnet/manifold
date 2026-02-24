#pragma once

#include "ControlServer.h"  // for ControlCommand
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>

// ============================================================================
// CommandParser - shared text-protocol parser used by both ControlServer (IPC)
// and LuaEngine (UI). One source of truth for command string → ControlCommand.
// ============================================================================

struct ParseResult {
    enum class Kind {
        Enqueue,        // a ControlCommand that should be enqueued to audio thread
        Query,          // a read-only query (STATE, PING, DIAGNOSE, etc.)
        Watch,          // enter watch mode (IPC only)
        Inject,         // INJECT <filepath> - handled by server thread
        InjectionStatus,// INJECTION_STATUS query
        Error           // parse error
    };

    Kind kind = Kind::Error;
    ControlCommand command;     // valid when kind == Enqueue
    std::string queryType;      // "STATE", "PING", "DIAGNOSE" when kind == Query
    std::string filepath;       // valid when kind == Inject
    std::string errorMessage;   // valid when kind == Error
};

namespace CommandParser {

inline std::string toUpper(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::toupper);
    return s;
}

inline int recordModeFromString(const std::string& s) {
    auto upper = toUpper(s);
    if (upper == "FIRSTLOOP" || upper == "FIRST" || upper == "0") return 0;
    if (upper == "FREEMODE" || upper == "FREE" || upper == "1") return 1;
    if (upper == "TRADITIONAL" || upper == "TRAD" || upper == "2") return 2;
    if (upper == "RETROSPECTIVE" || upper == "RETRO" || upper == "3") return 3;
    return -1;
}

// Parse a single command line into a ParseResult.
// Pure function - no side effects, no mutex, no IO.
inline ParseResult parse(const std::string& cmd) {
    std::istringstream iss(cmd);
    std::vector<std::string> tokens;
    std::string tok;
    while (iss >> tok) tokens.push_back(tok);

    if (tokens.empty())
        return { ParseResult::Kind::Error, {}, {}, {}, "empty command" };

    auto verb = toUpper(tokens[0]);

    auto makeEnqueue = [](ControlCommand::Type type, int ip = 0, float fp = 0.0f) -> ParseResult {
        ParseResult r;
        r.kind = ParseResult::Kind::Enqueue;
        r.command.type = type;
        r.command.intParam = ip;
        r.command.floatParam = fp;
        return r;
    };

    auto makeQuery = [](const std::string& qt) -> ParseResult {
        ParseResult r;
        r.kind = ParseResult::Kind::Query;
        r.queryType = qt;
        return r;
    };

    auto makeError = [](const std::string& msg) -> ParseResult {
        return { ParseResult::Kind::Error, {}, {}, {}, msg };
    };

    // ---- Queries (no side effects) ----
    if (verb == "STATE")    return makeQuery("STATE");
    if (verb == "PING")     return makeQuery("PING");
    if (verb == "DIAGNOSE") return makeQuery("DIAGNOSE");
    if (verb == "WATCH")    return { ParseResult::Kind::Watch, {}, {}, {}, {} };

    // ---- COMMIT <bars> ----
    if (verb == "COMMIT") {
        if (tokens.size() < 2) return makeError("usage: COMMIT <bars>");
        try { return makeEnqueue(ControlCommand::Type::Commit, 0, std::stof(tokens[1])); }
        catch (...) { return makeError("invalid bars value"); }
    }

    // ---- FORWARD <bars> ----
    if (verb == "FORWARD") {
        if (tokens.size() < 2) return makeError("usage: FORWARD <bars>");
        try { return makeEnqueue(ControlCommand::Type::ForwardCommit, 0, std::stof(tokens[1])); }
        catch (...) { return makeError("invalid bars value"); }
    }

    // ---- TEMPO <bpm> ----
    if (verb == "TEMPO") {
        if (tokens.size() < 2) return makeError("usage: TEMPO <bpm>");
        try { return makeEnqueue(ControlCommand::Type::SetTempo, 0, std::stof(tokens[1])); }
        catch (...) { return makeError("invalid bpm value"); }
    }

    // ---- REC ----
    if (verb == "REC") return makeEnqueue(ControlCommand::Type::StartRecording);

    // ---- OVERDUB [0|1] ----
    if (verb == "OVERDUB") {
        if (tokens.size() >= 2) {
            float val = (tokens[1] == "1" || toUpper(tokens[1]) == "TRUE" || toUpper(tokens[1]) == "ON") ? 1.0f : 0.0f;
            return makeEnqueue(ControlCommand::Type::SetOverdubEnabled, 0, val);
        }
        return makeEnqueue(ControlCommand::Type::ToggleOverdub);
    }

    // ---- Transport: STOP / PLAY / PAUSE / STOPREC ----
    if (verb == "STOP")    return makeEnqueue(ControlCommand::Type::GlobalStop);
    if (verb == "PLAY")    return makeEnqueue(ControlCommand::Type::GlobalPlay);
    if (verb == "PAUSE")   return makeEnqueue(ControlCommand::Type::GlobalPause);
    if (verb == "STOPREC") return makeEnqueue(ControlCommand::Type::StopRecording);

    // ---- CLEAR [layer] ----
    if (verb == "CLEAR") {
        int idx = -1;
        if (tokens.size() >= 2) {
            try { idx = std::stoi(tokens[1]); }
            catch (...) { return makeError("invalid layer index"); }
        }
        return makeEnqueue(ControlCommand::Type::LayerClear, idx);
    }

    // ---- CLEARALL ----
    if (verb == "CLEARALL") return makeEnqueue(ControlCommand::Type::ClearAllLayers);

    // ---- MODE <mode> ----
    if (verb == "MODE") {
        if (tokens.size() < 2) return makeError("usage: MODE <firstLoop|freeMode|traditional|retrospective>");
        int mode = recordModeFromString(tokens[1]);
        if (mode < 0) return makeError("unknown mode: " + tokens[1]);
        return makeEnqueue(ControlCommand::Type::SetRecordMode, mode);
    }

    // ---- VOLUME <0-2> / MASTERVOLUME <0-2> ----
    if (verb == "VOLUME" || verb == "MASTERVOLUME") {
        if (tokens.size() < 2) return makeError("usage: VOLUME <0-2>");
        try { return makeEnqueue(ControlCommand::Type::SetMasterVolume, 0, std::stof(tokens[1])); }
        catch (...) { return makeError("invalid volume"); }
    }

    // ---- TARGETBPM <bpm> ----
    if (verb == "TARGETBPM") {
        if (tokens.size() < 2) return makeError("usage: TARGETBPM <bpm>");
        try { return makeEnqueue(ControlCommand::Type::SetTargetBPM, 0, std::stof(tokens[1])); }
        catch (...) { return makeError("invalid bpm"); }
    }

    // ---- LAYER <index> [subcommand] ----
    if (verb == "LAYER") {
        if (tokens.size() < 2) return makeError("usage: LAYER <index> [MUTE|SPEED|REVERSE|VOLUME|PLAY|PAUSE|STOP|CLEAR]");

        int layerIdx = -1;
        try { layerIdx = std::stoi(tokens[1]); }
        catch (...) { return makeError("invalid layer index"); }
        if (layerIdx < 0 || layerIdx >= 4)
            return makeError("layer index must be 0-3");

        // LAYER <index> with no subcommand = select
        if (tokens.size() == 2)
            return makeEnqueue(ControlCommand::Type::SetActiveLayer, layerIdx);

        auto sub = toUpper(tokens[2]);

        if (sub == "MUTE" && tokens.size() >= 4) {
            float val = (tokens[3] == "1" || toUpper(tokens[3]) == "TRUE") ? 1.0f : 0.0f;
            return makeEnqueue(ControlCommand::Type::LayerMute, layerIdx, val);
        }
        if (sub == "SPEED" && tokens.size() >= 4) {
            try { return makeEnqueue(ControlCommand::Type::LayerSpeed, layerIdx, std::stof(tokens[3])); }
            catch (...) { return makeError("invalid speed value"); }
        }
        if (sub == "REVERSE" && tokens.size() >= 4) {
            float val = (tokens[3] == "1" || toUpper(tokens[3]) == "TRUE") ? 1.0f : 0.0f;
            return makeEnqueue(ControlCommand::Type::LayerReverse, layerIdx, val);
        }
        if (sub == "VOLUME" && tokens.size() >= 4) {
            try { return makeEnqueue(ControlCommand::Type::LayerVolume, layerIdx, std::stof(tokens[3])); }
            catch (...) { return makeError("invalid volume value"); }
        }
        if (sub == "STOP")  return makeEnqueue(ControlCommand::Type::LayerStop, layerIdx);
        if (sub == "PLAY")  return makeEnqueue(ControlCommand::Type::LayerPlay, layerIdx);
        if (sub == "PAUSE") return makeEnqueue(ControlCommand::Type::LayerPause, layerIdx);
        if (sub == "CLEAR") return makeEnqueue(ControlCommand::Type::LayerClear, layerIdx);

        return makeError("unknown layer command: " + tokens[2]);
    }

    // ---- INJECT <filepath> ----
    if (verb == "INJECT") {
        if (tokens.size() < 2) return makeError("usage: INJECT <filepath>");
        std::string filepath;
        for (size_t i = 1; i < tokens.size(); ++i) {
            if (i > 1) filepath += " ";
            filepath += tokens[i];
        }
        ParseResult r;
        r.kind = ParseResult::Kind::Inject;
        r.filepath = filepath;
        return r;
    }

    // ---- INJECTION_STATUS ----
    if (verb == "INJECTION_STATUS") {
        return { ParseResult::Kind::InjectionStatus, {}, {}, {}, {} };
    }

    return makeError("unknown command: " + tokens[0]);
}

} // namespace CommandParser
