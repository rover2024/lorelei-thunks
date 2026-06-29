#pragma once

// libcrypto and libssl share the same public header set, so reuse the ssl thunk's Desc rather than
// duplicating the full <openssl/*.h> include list. Symbols.conf is what scopes this thunk to the
// libcrypto functions.
#include "../ssl/Desc.h"

// libcrypto exports the directory-iteration helpers, and the openssl CLI imports them, but they are
// declared only in OpenSSL's private internal/o_dir.h, not in any public <openssl/*.h>. Declare them
// by hand (matching that header exactly) so TLC has a prototype to thunk.
extern "C" {
typedef struct OPENSSL_dir_context_st OPENSSL_DIR_CTX;
const char *OPENSSL_DIR_read(OPENSSL_DIR_CTX **ctx, const char *directory);
int OPENSSL_DIR_end(OPENSSL_DIR_CTX **ctx);
}
