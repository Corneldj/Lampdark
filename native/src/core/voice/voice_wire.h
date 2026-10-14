#pragma once
// SND-07: the voice packets on the wire (the GDScript mirror is shared/protocol/voice_packets.gd).
// Upstream, client to server: u16 seq, u8 head (band in bits 0-2; END, PROBE), then the Opus frame.
// Downstream, server to each listener: u16 stream, u16 seq, u8 head (band; END, PROBE, MUFFLED,
// TELEPHONE, DRY), i8 gain dB, u8 treatment (bit 0 crackle; bits 1-7 the distance muffle, 0-127,
// SND-08), i32 x and y of the apparent position in 1/16 tiles, then
// the Opus frame as it came. The stream id is ephemeral (new every utterance, per listener), so
// nothing on the wire names a speaker. Little-endian. Engine-free.

#include <cstdint>

namespace lb::core::voice::wire {

constexpr uint8_t BAND_MASK = 0x07;
constexpr uint8_t END = 0x08; // the utterance's last packet (the band fell silent)
constexpr uint8_t PROBE = 0x10; // NET-12's marked frame: the payload is the sender's i64 clock
constexpr uint8_t MUFFLED = 0x20; // through rock, or a muffled route (downstream only)
constexpr uint8_t TELEPHONE = 0x40; // a phone line: telephone band with hiss (downstream only)
constexpr uint8_t DRY = 0x80; // a shared channel: dry, unspatialised (downstream only)
constexpr uint8_t UP_FLAGS = END | PROBE;
constexpr int MAX_BAND = 4; // scream; 5-7 are refused
constexpr int UP_HEADER = 3;
constexpr int DOWN_HEADER = 15;
constexpr int POS_SCALE = 16; // apparent position units per tile
constexpr uint8_t CRACKLE = 0x01; // treatment byte: the Stythe's crackle (SND-08)
constexpr int MUFFLE_SHIFT = 1; // treatment byte: muffle level 0-127 above the crackle bit
constexpr int MUFFLE_MAX = 127;

} // namespace lb::core::voice::wire
