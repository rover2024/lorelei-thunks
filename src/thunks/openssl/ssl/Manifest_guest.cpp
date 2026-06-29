#define LORE_THUNK_CALLBACK_REPLACE

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestGuest.cpp.inc>

// Remap the guest std streams to the host's for any libssl function that takes a FILE*, so passing
// one across the boundary is safe.
#include <lorethunk/ThunkUtils/Guest/libc-shim/StdStream.h>

namespace lore::thunk {}
