# ----------------------------------
# Language Configurations
# ----------------------------------
set(CMAKE_POSITION_INDEPENDENT_CODE TRUE)
set(CMAKE_VISIBILITY_INLINES_HIDDEN TRUE)
set(CMAKE_C_VISIBILITY_PRESET "hidden")
set(CMAKE_CXX_VISIBILITY_PRESET "hidden")

if(MSVC)
    set(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS} /EHsc-")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc- /GR-")
else()
    set(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS} -fno-exceptions")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-exceptions -fno-rtti")

    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,defs")
    endif()
endif()

# ----------------------------------
# Add source directories
# ----------------------------------
add_subdirectory(libs)

add_subdirectory(thunks)

if(LORE_BUILD_TESTS)
    add_subdirectory(tests)
endif()
