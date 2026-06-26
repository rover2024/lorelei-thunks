project(xcb_HMW)

find_library(_xcb_lib xcb)

if(NOT _xcb_lib)
    message(WARNING "xcb library not found; skipping ${PROJECT_NAME}")
    return()
endif()

file(GLOB_RECURSE _src *.h *.cpp)
thunk_add_library(${PROJECT_NAME}
    LIBRARY_DIRECTORY ${THUNK_HOST_ARCH}-LoreHTL
    SOURCES ${_src}
    LINKS_PRIVATE lorelei::LoreSupport ${_xcb_lib}
)
qm_include_recursive(${PROJECT_NAME} PRIVATE
    ${THUNK_SOURCE_DIR}/include/lorethunk/Midware/Host/xcb
)
thunk_generate_global_header(${PROJECT_NAME} lorethunk/Midware/Host/xcb)
