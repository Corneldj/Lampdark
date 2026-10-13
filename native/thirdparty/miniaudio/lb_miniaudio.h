#pragma once
/*
LAMPBLACK (SND-05): miniaudio as the voice capture's device layer, and nothing else. Only the
backends the game's platforms need (WASAPI on Windows; PulseAudio, which PipeWire serves, then ALSA
on Linux; the null device for tests), no encoder, decoder, generators, node graph or engine, so no
code path here can write audio to a file. Every user includes this, never miniaudio.h directly.
*/
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_WASAPI
#define MA_ENABLE_PULSEAUDIO
#define MA_ENABLE_ALSA
#define MA_ENABLE_NULL
#define MA_NO_ENCODING
#define MA_NO_DECODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#include "miniaudio.h"
