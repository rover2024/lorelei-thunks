cmake_minimum_required(VERSION 3.19)

project(lorethunk
    VERSION 0.0.1.0
    LANGUAGES C CXX
    DESCRIPTION "Lorelei thunk libraries."
    HOMEPAGE_URL "https://github.com/rover2024/lorelei"
)

# ----------------------------------
# Build Options
# ----------------------------------
option(THUNK_BUILD_HOST_TARGETS "Build host thunk targets" ON)
option(THUNK_BUILD_GUEST_TARGETS "Build guest thunk targets" OFF)
option(THUNK_BUILD_TESTS "Build test targets" OFF)
option(THUNK_BUILD_EXPERIMENTAL_LIBRARIES "Build the experimental, work-in-progress thunks" OFF)
option(THUNK_INSTALL "Install thunk libraries" ON)

# Which thunk libraries to build, by subdirectory name. THUNK_ENABLE_LIBRARIES is an explicit
# allowlist: when non-empty, exactly those libraries are built (stable or not, overriding everything
# below). Otherwise the stable thunks are built, plus the experimental ones if THUNK_BUILD_EXPERIMENTAL_LIBRARIES
# is ON, minus anything in the THUNK_DISABLE_LIBRARIES denylist. All are semicolon-separated subdir
# names (e.g. -DTHUNK_ENABLE_LIBRARIES="zlib;lzma", -DTHUNK_DISABLE_LIBRARIES="SDL2").
set(THUNK_ENABLE_LIBRARIES "" CACHE STRING "Thunk libraries to build exclusively (allowlist; empty = the default selection)")
set(THUNK_DISABLE_LIBRARIES "" CACHE STRING "Thunk libraries to skip building (denylist; ignored if the allowlist is set)")

# ----------------------------------
# CMake Settings
# ----------------------------------
if(MSVC)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /manifest:no")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} /manifest:no")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} /manifest:no")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /utf-8")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /utf-8")
elseif(MINGW)
    set(CMAKE_STATIC_LIBRARY_PREFIX "")
    set(CMAKE_SHARED_LIBRARY_PREFIX "")
    set(CMAKE_IMPORT_LIBRARY_PREFIX "")
endif()

if(THUNK_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)
endif()

# ----------------------------------
# Dependencies
# ----------------------------------
find_package(qmsetup REQUIRED)
qm_import(Filesystem)

if(NOT DEFINED QMSETUP_BUILD_DIR)
    set(QMSETUP_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/out")
endif()

qm_init_directories()

# lorelei provides LoreTLC (the thunk compiler), the LoreGuestRT/LoreHostRT runtimes, and
# the ThunkInterface headers that the generated sources include.
find_package(lorelei REQUIRED)

# ----------------------------------
# Project Variables
# ----------------------------------
set(THUNK_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})

if(NOT DEFINED THUNK_INSTALL_SHARE_DIR)
    set(THUNK_INSTALL_SHARE_DIR ${CMAKE_INSTALL_DATADIR})
endif()

# Directory holding each thunk's TLC stat result (ThunkStat.json). When the caller points
# this at a pre-generated directory, stat is skipped (the files are taken as-is) and not
# installed; otherwise stat runs into the build tree and the results are installed so they
# can be reused later.
if(NOT DEFINED THUNK_DATA_DIR)
    set(THUNK_DATA_DIR_USER_DEFINED FALSE)
    set(THUNK_DATA_DIR ${QMSETUP_BUILD_DIR}/share/lorelei/thunks)
else()
    set(THUNK_DATA_DIR_USER_DEFINED TRUE)
endif()

# Directory the generated thunk sources (Thunk_{guest,host}.cpp) are emitted into. Like the
# stat result, when the caller points this at a pre-generated directory the generate step is
# skipped (the sources are compiled as-is) and not installed; otherwise generate runs into the
# build tree and the sources are installed so a later build can reuse them without rerunning TLC.
if(NOT DEFINED THUNK_GEN_SOURCE_DIR)
    set(THUNK_GEN_SOURCE_DIR_USER_DEFINED FALSE)
    set(THUNK_GEN_SOURCE_DIR ${QMSETUP_BUILD_DIR}/src/thunks)
else()
    set(THUNK_GEN_SOURCE_DIR_USER_DEFINED TRUE)
endif()

include("cmake/LoreThunkBuildApi.cmake")

# ----------------------------------
# Add thunks
# ----------------------------------
add_subdirectory(src)

# Install the generated stat results, but only when this build actually ran stat (it is skipped when
# the caller supplied their own data directory or pre-generated sources, matching the stat command's
# own guard; otherwise THUNK_DATA_DIR does not exist and the install would fail).
if(THUNK_INSTALL AND NOT THUNK_DATA_DIR_USER_DEFINED AND NOT THUNK_GEN_SOURCE_DIR_USER_DEFINED)
    install(DIRECTORY ${THUNK_DATA_DIR}/
        DESTINATION ${THUNK_INSTALL_SHARE_DIR}/lorelei/thunks
    )
endif()

# Install the generated thunk sources (alongside the stat results) unless the caller supplied
# their own. Generation is independent of the enabled side, so both Thunk_host.cpp and
# Thunk_guest.cpp are produced and installed here (a host-only cross build still emits the guest
# source for a following guest build to compile from THUNK_GEN_SOURCE_DIR).
if(THUNK_INSTALL AND NOT THUNK_GEN_SOURCE_DIR_USER_DEFINED)
    install(DIRECTORY ${THUNK_GEN_SOURCE_DIR}/
        DESTINATION ${THUNK_INSTALL_SHARE_DIR}/lorelei/thunks
        FILES_MATCHING PATTERN "Thunk_*.cpp"
    )
endif()

if(THUNK_INSTALL)
    # Install the public headers.
    install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )

    # Install shared data (ThunkDB.json, ...)
    include("share/install.cmake")

    # Install the support libraries (midware, ...)
    get_property(_thunk_has_exports GLOBAL PROPERTY THUNK_HAS_EXPORTS)

    if(_thunk_has_exports)
        qm_basic_install(
            NAME ${PROJECT_NAME}
            VERSION ${PROJECT_VERSION}
            NAMESPACE lorethunk::
            EXPORT lorethunkTargets
        )
    endif()
endif()
