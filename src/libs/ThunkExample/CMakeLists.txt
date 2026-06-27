project(ThunkExample)

# The host-side implementation of the example library. It is built for the host ISA and installed
# next to the host thunks, where the example HTL links it via LORE_THUNK_AUTO_LINK.
file(GLOB_RECURSE _src *.h *.cpp)
thunk_add_library(${PROJECT_NAME}
    SOURCES ${_src}
)
target_compile_definitions(${PROJECT_NAME} PRIVATE THUNKEXAMPLE_LIBRARY)
qm_include_recursive(${PROJECT_NAME} PRIVATE
    ${THUNK_SOURCE_DIR}/include/lorethunk/ThunkExample
)
