#ifndef LORE_XCB_H
#define LORE_XCB_H

// Forward declaration so callers need not pull in <xcb/xcb.h> just for the handle type.
typedef struct xcb_connection_t xcb_connection_t;

#include <lorethunk/Midware/Host/xcb/Global.h>

namespace lore::midware::host {

    /// xcb - Host middleware that translates opaque xcb connection handles across the guest/host
    /// boundary.
    ///
    /// As with the X11 helper, a guest \c xcb_connection_t cannot be used on the host; these map
    /// between the two, opening a host connection to the guest's display on demand.
    struct xcb {
        /// Returns the host connection paired with guest \a conn, opening one to the guest's display
        /// (derived from the connection's socket peer name) on first use.
        static XCB_HMW_EXPORT xcb_connection_t *connection_G2H(xcb_connection_t *conn);

        /// Returns the guest connection previously paired with host \a conn, or null if none.
        static XCB_HMW_EXPORT xcb_connection_t *connection_H2G(xcb_connection_t *conn);
    };

}

#endif // LORE_XCB_H
