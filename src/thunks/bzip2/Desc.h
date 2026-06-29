#pragma once

// <bzlib.h> uses FILE in its stdio-based API (BZ2_bzReadOpen / BZ2_bzWriteOpen / ...), so pull in
// <stdio.h> first.
#include <stdio.h>
#include <bzlib.h>

#include <lorelei/ThunkInterface/Proc.h>
#include <lorelei/ThunkInterface/PassTags.h>

namespace lore::thunk {}
