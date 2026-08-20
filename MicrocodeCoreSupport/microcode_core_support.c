#include "microcode_coreFFI.h"

// SwiftPM/Xcode needs one compilation unit for this C target so it emits the
// target object used by the MicroCodeCore static library product. The actual
// implementation is linked from the Rust static library by build.sh.
void microcode_core_support_link_anchor(void) {}
