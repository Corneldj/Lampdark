// lampblack_core entry point (FND-02). Every native class registers here.

#include "godot/audio/lb_audio_mixer.h"
#include "godot/audit/lb_audit_reference.h"
#include "godot/voice/lb_opus.h"
#include "godot/voice/lb_band_meter.h"
#include "godot/voice/lb_voice_forwarder.h"
#include "godot/voice/lb_voice_loss.h"
#include "godot/voice/lb_voice_playout.h"
#include "godot/voice/lb_voice_capture.h"
#include "godot/lb_core_info.h"
#include "godot/gen/lb_layouts.h"
#include "godot/gen/lb_templates.h"
#include "godot/light/lb_light.h"
#include "godot/vision/lb_vision.h"
#include "godot/world/lb_det_math.h"
#include "godot/world/lb_diff_store.h"
#include "godot/creatures/lb_creature_nav.h"
#include "godot/net/lb_replication.h"
#include "godot/net/lb_seal.h"
#include "godot/rng/lb_hash.h"
#include "godot/rng/lb_rng.h"
#include "godot/sim/lb_entity_mirror.h"
#include "godot/sound/lb_road_graph.h"
#include "godot/tuning/lb_tuning.h"
#include "godot/world/lb_mine.h"
#include "godot/world/lb_world.h"
#include "godot/sheets/lb_sheet.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

namespace {

void initialize_lampblack_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(lb::godot::LbCoreInfo);
	GDREGISTER_CLASS(lb::godot::LbTuning);
	GDREGISTER_CLASS(lb::godot::LbHash);
	GDREGISTER_CLASS(lb::godot::LbRng);
	GDREGISTER_CLASS(lb::godot::LbWorld);
	GDREGISTER_CLASS(lb::godot::LbEntityIds);
	GDREGISTER_CLASS(lb::godot::LbDiffStore);
	GDREGISTER_CLASS(lb::godot::LbSeal);
	GDREGISTER_CLASS(lb::godot::LbEntityMirror);
	GDREGISTER_CLASS(lb::godot::LbCellData);
	GDREGISTER_CLASS(lb::godot::LbMine);
	GDREGISTER_CLASS(lb::godot::LbTemplates);
	GDREGISTER_CLASS(lb::godot::LbLayouts);
	GDREGISTER_CLASS(lb::godot::LbLightGrid);
	GDREGISTER_CLASS(lb::godot::LbLightMath);
	GDREGISTER_CLASS(lb::godot::LbRoadGraph);
	GDREGISTER_CLASS(lb::godot::LbVision);
	GDREGISTER_CLASS(lb::godot::LbDetMath);
	GDREGISTER_CLASS(lb::godot::LbReplication);
	GDREGISTER_CLASS(lb::godot::LbFrameCodec);
	GDREGISTER_CLASS(lb::godot::LbCreatureNav);
	GDREGISTER_CLASS(lb::godot::LbAudioMixer);
	GDREGISTER_CLASS(lb::godot::LbSheet); // LFT-14's map card and rubber
#ifdef LB_DEBUG_TOOLS
	GDREGISTER_CLASS(lb::godot::LbAuditReference); // NET-08's stream audit: dev and QA only
#endif
	GDREGISTER_CLASS(lb::godot::LbOpusEncoder);
	GDREGISTER_CLASS(lb::godot::LbOpusDecoder);
	GDREGISTER_CLASS(lb::godot::LbVoiceCapture);
	GDREGISTER_CLASS(lb::godot::LbBandMeter);
	GDREGISTER_CLASS(lb::godot::LbVoiceForwarder);
	GDREGISTER_CLASS(lb::godot::LbVoiceLoss);
	GDREGISTER_CLASS(lb::godot::LbVoicePlayout);
}

void uninitialize_lampblack_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

} // namespace

extern "C" {

GDExtensionBool GDE_EXPORT lampblack_core_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_lampblack_core);
	init_obj.register_terminator(uninitialize_lampblack_core);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
