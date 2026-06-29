#pragma once

// The interposed subset spans the allocator family (<stdlib.h>) and the stdio FILE* family
// (<stdio.h>).
#include <stdlib.h>
#include <stdio.h>

#include <lorelei/ThunkInterface/Proc.h>
#include <lorelei/ThunkInterface/PassTags.h>

namespace lore::thunk {}
