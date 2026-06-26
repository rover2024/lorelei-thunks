#ifndef LORE_X11_H
#define LORE_X11_H

extern "C" {
#include <X11/Xlib.h>
#include <X11/Xutil.h>
}

// Xlib defines Success as a macro, which collides with identifiers elsewhere.
#ifdef Success
#  undef Success
#endif

#include <lorethunk/Midware/Host/X11/Global.h>

namespace lore::midware::host {

    /// X11 - Host middleware that translates opaque Xlib handles across the guest/host boundary.
    ///
    /// A guest \c Display (or \c XVisualInfo) refers to the guest's own X connection and is
    /// meaningless on the host, and vice versa. The X11 thunk routes such handles through these
    /// helpers, which keep a guest<->host mapping and open the matching host connection on demand.
    struct X11 {
        /// Returns the host \c Display paired with guest \a display, opening a host connection to
        /// the same display name on first use.
        static X11_HMW_EXPORT Display *Display_G2H(Display *display);

        /// Returns the guest \c Display paired with host \a display; if none exists yet, creates one
        /// via \a guest_open (the guest's \c XOpenDisplay) and records the pairing.
        static X11_HMW_EXPORT Display *Display_H2G(Display *display,
                                                   Display *(*guest_open)(const char *) );

        /// Returns the host \c XVisualInfo matching guest \a visualInfo on \a display (looked up by
        /// screen and visual id).
        static X11_HMW_EXPORT XVisualInfo *VisualInfo_G2H(Display *display,
                                                          XVisualInfo *visualInfo);

        /// Returns a guest-side \c XVisualInfo mirroring host \a visualInfo, freeing the host one.
        static X11_HMW_EXPORT XVisualInfo *VisualInfo_H2G(Display *display,
                                                          XVisualInfo *visualInfo);
    };

}

#endif // LORE_X11_H
