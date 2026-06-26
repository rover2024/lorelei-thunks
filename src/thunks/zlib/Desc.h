#pragma once

#include <zlib.h>

#include <lorelei/ThunkInterface/Proc.h>
#include <lorelei/ThunkInterface/PassTags.h>

namespace lore::thunk {}

#ifdef gzgetc
#  undef gzgetc
#endif
