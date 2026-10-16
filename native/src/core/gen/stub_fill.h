#pragma once
// GEN-05: a chosen template fitted to its cell's sockets (Gameplay §12.3). An open socket at a
// stub's edge and offset narrows that stub's throat to the socket's width (Proposed, shared with
// GEN-04), so no road changes width at a cell edge; every other stub's throat fills with rock and
// leaves a blind heading. The cell's zones and portals are then cut again (GEN-04's cutter).

#include "core/gen/template_choice.h"

namespace lb::core::gen {

// The template's cell (a one-cell template) at `coord`, its stubs fitted to `sockets`.
lb::core::world::Cell fill_stubs(const Template &t, const CellSockets &sockets, lb::core::world::Coord coord);

} // namespace lb::core::gen
