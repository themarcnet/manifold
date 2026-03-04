#pragma once
// ============================================================================
// OSCPacketBuilder - builds binary OSC packets for any transport.
//
// Extracted from OSCServer::sendToTargets() so both UDP broadcasting and
// WebSocket binary streaming can share the same packet format.
// ============================================================================

#include <juce_core/juce_core.h>
#include <vector>
#include <cstring>

namespace OSCPacketBuilder {

inline uint32_t hostToBE32(uint32_t val) {
    return ((val >> 24) & 0xFF) |
           ((val >>  8) & 0xFF00) |
           ((val <<  8) & 0xFF0000) |
           ((val << 24) & 0xFF000000);
}

// Build a complete OSC binary packet from address + arguments.
// Returns the raw bytes ready for UDP send or WebSocket binary frame.
inline std::vector<char> build(const juce::String& address,
                               const std::vector<juce::var>& args) {
    std::vector<char> packet;
    packet.reserve(128);

    // Address string (null-terminated, padded to 4 bytes)
    for (int i = 0; i < address.length(); i++) {
        packet.push_back((char)address[i]);
    }
    packet.push_back('\0');
    while (packet.size() % 4 != 0) packet.push_back('\0');

    // Type tag string
    packet.push_back(',');
    juce::String typeTag;
    for (const auto& arg : args) {
        if (arg.isInt())         typeTag += "i";
        else if (arg.isDouble()) typeTag += "f";
        else if (arg.isString()) typeTag += "s";
        else                     typeTag += "N";
    }
    for (int i = 0; i < typeTag.length(); i++) {
        packet.push_back(typeTag[i]);
    }
    packet.push_back('\0');
    while (packet.size() % 4 != 0) packet.push_back('\0');

    // Arguments (big-endian)
    for (const auto& arg : args) {
        if (arg.isInt()) {
            int32_t val = (int32_t)(int)arg;
            uint32_t beVal;
            std::memcpy(&beVal, &val, 4);
            beVal = hostToBE32(beVal);
            const char* bytes = reinterpret_cast<const char*>(&beVal);
            for (int i = 0; i < 4; i++) packet.push_back(bytes[i]);
        }
        else if (arg.isDouble()) {
            float val = (float)(double)arg;
            uint32_t beVal;
            std::memcpy(&beVal, &val, 4);
            beVal = hostToBE32(beVal);
            const char* bytes = reinterpret_cast<const char*>(&beVal);
            for (int i = 0; i < 4; i++) packet.push_back(bytes[i]);
        }
        else if (arg.isString()) {
            juce::String str = arg.toString();
            for (int i = 0; i < str.length(); i++) {
                packet.push_back((char)str[i]);
            }
            packet.push_back('\0');
            while (packet.size() % 4 != 0) packet.push_back('\0');
        }
    }

    return packet;
}

} // namespace OSCPacketBuilder
