#pragma once
// ============================================================================
// Minimal SHA-1 implementation for WebSocket handshake (RFC 6455).
//
// Based on the algorithm from RFC 3174. This is a self-contained, dependency-free
// implementation. SHA-1 is cryptographically broken for collision resistance but
// is required by the WebSocket protocol for the Sec-WebSocket-Accept handshake.
//
// Usage:
//   uint8_t hash[20];
//   sha1::compute("input data", 10, hash);
// ============================================================================

#include <cstdint>
#include <cstddef>
#include <cstring>

namespace sha1 {

namespace detail {

inline uint32_t leftRotate(uint32_t value, int bits) {
    return (value << bits) | (value >> (32 - bits));
}

} // namespace detail

// Compute SHA-1 hash of input data. Output must point to 20 bytes.
inline void compute(const void* data, size_t length, uint8_t output[20]) {
    // Initial hash values (H0-H4)
    uint32_t h0 = 0x67452301;
    uint32_t h1 = 0xEFCDAB89;
    uint32_t h2 = 0x98BADCFE;
    uint32_t h3 = 0x10325476;
    uint32_t h4 = 0xC3D2E1F0;

    const uint8_t* msg = static_cast<const uint8_t*>(data);

    // Pre-processing: add padding
    // Message length in bits
    uint64_t bitLength = (uint64_t)length * 8;

    // Padded message: original + 1 byte (0x80) + zeros + 8 bytes (length)
    // Total must be multiple of 64 bytes (512 bits)
    size_t paddedLen = length + 1;  // +1 for 0x80
    while (paddedLen % 64 != 56) paddedLen++;
    paddedLen += 8;  // 64-bit length

    // Allocate padded message on stack for small messages, heap for large
    uint8_t stackBuf[256];
    uint8_t* padded = (paddedLen <= sizeof(stackBuf)) ? stackBuf : new uint8_t[paddedLen];

    std::memcpy(padded, msg, length);
    padded[length] = 0x80;
    std::memset(padded + length + 1, 0, paddedLen - length - 1);

    // Append bit length as big-endian 64-bit
    for (int i = 0; i < 8; i++) {
        padded[paddedLen - 8 + i] = (uint8_t)(bitLength >> (56 - i * 8));
    }

    // Process each 64-byte (512-bit) block
    for (size_t offset = 0; offset < paddedLen; offset += 64) {
        uint32_t w[80];

        // Break block into sixteen 32-bit big-endian words
        for (int i = 0; i < 16; i++) {
            w[i] = ((uint32_t)padded[offset + i * 4 + 0] << 24) |
                   ((uint32_t)padded[offset + i * 4 + 1] << 16) |
                   ((uint32_t)padded[offset + i * 4 + 2] <<  8) |
                   ((uint32_t)padded[offset + i * 4 + 3]);
        }

        // Extend to 80 words
        for (int i = 16; i < 80; i++) {
            w[i] = detail::leftRotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        }

        uint32_t a = h0, b = h1, c = h2, d = h3, e = h4;

        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) {
                f = (b & c) | ((~b) & d);
                k = 0x5A827999;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ED9EBA1;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8F1BBCDC;
            } else {
                f = b ^ c ^ d;
                k = 0xCA62C1D6;
            }

            uint32_t temp = detail::leftRotate(a, 5) + f + e + k + w[i];
            e = d;
            d = c;
            c = detail::leftRotate(b, 30);
            b = a;
            a = temp;
        }

        h0 += a;
        h1 += b;
        h2 += c;
        h3 += d;
        h4 += e;
    }

    if (padded != stackBuf) delete[] padded;

    // Produce the final hash value (big-endian)
    output[ 0] = (uint8_t)(h0 >> 24); output[ 1] = (uint8_t)(h0 >> 16);
    output[ 2] = (uint8_t)(h0 >>  8); output[ 3] = (uint8_t)(h0);
    output[ 4] = (uint8_t)(h1 >> 24); output[ 5] = (uint8_t)(h1 >> 16);
    output[ 6] = (uint8_t)(h1 >>  8); output[ 7] = (uint8_t)(h1);
    output[ 8] = (uint8_t)(h2 >> 24); output[ 9] = (uint8_t)(h2 >> 16);
    output[10] = (uint8_t)(h2 >>  8); output[11] = (uint8_t)(h2);
    output[12] = (uint8_t)(h3 >> 24); output[13] = (uint8_t)(h3 >> 16);
    output[14] = (uint8_t)(h3 >>  8); output[15] = (uint8_t)(h3);
    output[16] = (uint8_t)(h4 >> 24); output[17] = (uint8_t)(h4 >> 16);
    output[18] = (uint8_t)(h4 >>  8); output[19] = (uint8_t)(h4);
}

} // namespace sha1
