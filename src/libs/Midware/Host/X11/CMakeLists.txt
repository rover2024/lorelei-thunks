project(X11_HMW)

find_library(_x11_lib X11)

if(NOT _x11_lib)
    message(WARNING "X11 library not found; skipping ${PROJECT_NAME}")
    return()
endif()

file(GLOB_RECURSE _src *.h *.cpp)
thunk_add_library(${PROJECT_NAME}
    LIBRARY_DIRECTORY ${THUNK_HOST_ARCH}-LoreHTL
    SOURCES ${_src}
    LINKS_PRIVATE lorelei::LoreSupport ${_x11_lib}
)
qm_include_recursive(${PROJECT_NAME} PRIVATE
    ${THUNK_SOURCE_DIR}/include/lorethunk/Midware/Host/X11
)
thunk_generate_global_header(${PROJECT_NAME} lorethunk/Midware/Host/X11)
