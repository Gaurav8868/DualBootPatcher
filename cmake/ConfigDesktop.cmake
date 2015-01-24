include(CMakeDependentOption)
include(GNUInstallDirs)

# Portable application

option(MBP_PORTABLE "Build as portable application" OFF)

if(WIN32)
    set(MBP_PORTABLE ON CACHE BOOL "Build as portable application" FORCE)
endif()

# Compiler flags

if(CMAKE_COMPILER_IS_GNUCXX OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--no-undefined")

    # Enable warnings
    #set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Werror -pedantic")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -pedantic")
    # Except for "/*" within comment errors (present in doxygen blocks)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-error=comment")
    # Visibility
    #set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden")

    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections")
endif()

# Use boost::regex instead on versions of gcc that don't have std::regex
# implemented

set(USE_BOOST_REGEX TRUE)

if(CMAKE_COMPILER_IS_GNUCXX)
    execute_process(COMMAND ${CMAKE_C_COMPILER} -dumpversion
                    OUTPUT_VARIABLE GCC_VERSION)
    if (GCC_VERSION VERSION_GREATER 4.9 OR GCC_VERSION VERSION_EQUAL 4.9)
        message(STATUS "Found gcc >= 4.9; std::regex will be used")
        set(USE_BOOST_REGEX FALSE)
    endif()
endif()

set(BOOST_COMPONENTS filesystem system)

if(USE_BOOST_REGEX)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_BOOST_REGEX")
    list(APPEND BOOST_COMPONENTS regex)
endif()

# Dependencies

find_package(Boost REQUIRED COMPONENTS ${BOOST_COMPONENTS})
include_directories(${Boost_INCLUDE_DIRS})
link_directories(${Boost_LIBRARY_DIRS})

find_package(Qt5Core 5.3 REQUIRED)

find_package(LibXml2 REQUIRED)
include_directories(${LIBXML2_INCLUDE_DIR})


# Same logic as CMakeLists.txt from the CMake source
set(EXTERNAL_LIBRARIES LIBARCHIVE LIBLZMA LZ4 ZLIB)
foreach(extlib ${EXTERNAL_LIBRARIES})
    if(NOT DEFINED MBP_USE_SYSTEM_LIBRARY_${extlib}
            AND DEFINED MBP_USE_SYSTEM_LIBRARIES)
        set(MBP_USE_SYSTEM_LIBRARY_${extlib} "${MBP_USE_SYSTEM_LIBRARIES}")
    endif()
    if(DEFINED MBP_USE_SYSTEM_LIBRARY_${extlib})
        if(MBP_USE_SYSTEM_LIBRARY_${extlib})
            set(MBP_USE_SYSTEM_LIBRARY_${extlib} ON)
        else()
            set(MBP_USE_SYSTEM_LIBRARY_${extlib} OFF)
        endif()
        string(TOLOWER "${extlib}" extlib_lower)
        set(MBP_USE_SYSTEM_${extlib} "${MBP_USE_SYSTEM_LIBRARY_${extlib}}"
            CACHE BOOL "Use system-installed ${extlib_lower}" FORCE)
    else()
        set(MBP_USE_SYSTEM_LIBRARY_${extlib} OFF)
    endif()
endforeach()


# Optionally use system utility libraries.
option(
    MBP_USE_SYSTEM_LIBARCHIVE
    "Use system-installed libarchive"
    "${MBP_USE_SYSTEM_LIBRARY_LIBARCHIVE}"
)
cmake_dependent_option(
    MBP_USE_SYSTEM_ZLIB
    "Use system-installed zlib"
    "${MBP_USE_SYSTEM_LIBRARY_ZLIB}"
    "NOT MBP_USE_SYSTEM_LIBARCHIVE"
    ON
)
cmake_dependent_option(
    MBP_USE_SYSTEM_BZIP2
    "Use system-installed bzip2"
    "${MBP_USE_SYSTEM_LIBRARY_BZIP2}"
    "NOT MBP_USE_SYSTEM_LIBARCHIVE"
    ON
)
cmake_dependent_option(
    MBP_USE_SYSTEM_LIBLZMA
    "Use system-installed liblzma"
    "${MBP_USE_SYSTEM_LIBRARY_LIBLZMA}"
    "NOT MBP_USE_SYSTEM_LIBARCHIVE"
    ON
)

foreach(extlib ${EXTERNAL_LIBRARIES})
    if(MBP_USE_SYSTEM_${extlib})
        message(STATUS "Using system-installed ${extlib}")
    endif()
endforeach()


# zlib
if(MBP_USE_SYSTEM_ZLIB)
    find_package(ZLIB)
    if(NOT ZLIB_FOUND)
        message(FATAL_ERROR "MBP_USE_SYSTEM_ZLIB is ON but zlib is not found!")
    endif()
    set(MBP_ZLIB_INCLUDES ${ZLIB_INCLUDE_DIR})
    set(MBP_ZLIB_LIBRARIES ${ZLIB_LIBRARIES})
else()
    set(SKIP_INSTALL_ALL ON CACHE INTERNAL "Disable zlib install")
    set(MBP_ZLIB_INCLUDES ${CMAKE_SOURCE_DIR}/external/zlib)
    set(MBP_ZLIB_LIBRARIES zlibstatic)
    add_subdirectory(external/zlib)
    # Linking shared library to zlib's static library, need -fPIC
    set_target_properties(
        zlibstatic
        PROPERTIES
        POSITION_INDEPENDENT_CODE 1
    )
    # Don't build the shared library or other binaries
    set_target_properties(
        zlib example example64 minigzip minigzip64
        PROPERTIES
        EXCLUDE_FROM_ALL 1
        EXCLUDE_FROM_DEFAULT_BUILD 1
    )
endif()


# liblzma
if(MBP_USE_SYSTEM_LIBLZMA)
    find_package(LibLZMA)
    if(NOT LIBLZMA_FOUND)
        message(FATAL_ERROR "CMAKE_USE_SYSTEM_LIBLZMA is ON but LibLZMA is not found!")
    endif()
    set(MBP_LIBLZMA_INCLUDES ${LIBLZMA_INCLUDE_DIRS})
    set(MBP_LIBLZMA_LIBRARIES ${LIBLZMA_LIBRARIES})
else()
    add_subdirectory(external/xz)
    set(MBP_LIBLZMA_INCLUDES "${CMAKE_SOURCE_DIR}/external/xz/src/liblzma/api")
    set(MBP_LIBLZMA_LIBRARIES lzma_static)
    # Linking shared library to libarchive's static library, need -fPIC
    set_target_properties(
        lzma_static
        PROPERTIES
        POSITION_INDEPENDENT_CODE 1
    )
    # Don't build the shared library
    set_target_properties(
        lzma
        PROPERTIES
        EXCLUDE_FROM_ALL 1
        EXCLUDE_FROM_DEFAULT_BUILD 1
    )
endif()


# lz4
if(MBP_USE_SYSTEM_LZ4)
    find_path(MBP_LZ4_INCLUDES lz4.h)
    find_library(MBP_LZ4_LIBRARIES NAMES lz4 liblz4)
    include(FindPackageHandleStandardArgs)
    find_package_handle_standard_args(LZ4 DEFAULT_MSG MBP_LZ4_LIBRARIES MBP_LZ4_INCLUDES)
    if(NOT LZ4_FOUND)
        message(FATAL_ERROR "CMAKE_USE_SYSTEM_LIBLZ4 is ON but LZ4 is not found!")
    endif()
else()
    set(BUILD_TOOLS OFF CACHE INTERNAL "Build the command line tools")
    set(BUILD_LIBS ON CACHE INTERNAL "Build the libraries in addition to the tools")
    add_subdirectory(external/lz4/cmake_unofficial)
    set(MBP_LZ4_INCLUDES "${CMAKE_SOURCE_DIR}/external/lz4/lib")
    set(MBP_LZ4_LIBRARIES liblz4)
endif()


# libarchive
if(MBP_USE_SYSTEM_LIBARCHIVE)
    find_package(LibArchive)
    if(NOT LibArchive_FOUND)
        message(FATAL_ERROR "MBP_USE_SYSTEM_LIBARCHIVE is ON but LibArchive is not found!")
    endif()
    set(MBP_LIBARCHIVE_INCLUDES ${LibArchive_INCLUDE_DIRS})
    set(MBP_LIBARCHIVE_LIBRARIES ${LibArchive_LIBRARIES})
else()
    set(ENABLE_NETTLE OFF CACHE INTERNAL "Enable use of Nettle")
    set(ENABLE_OPENSSL OFF CACHE INTERNAL "Enable use of OpenSSL")
    set(ENABLE_LZMA ON CACHE INTERNAL "Enable the use of the system found LZMA library if found")
    set(ENABLE_ZLIB ON CACHE INTERNAL "Enable the use of the system found ZLIB library if found")
    set(ENABLE_BZip2 OFF CACHE INTERNAL "Enable the use of the system found BZip2 library if found")
    set(ENABLE_EXPAT OFF CACHE INTERNAL "Enable the use of the system found EXPAT library if found")
    set(ENABLE_PCREPOSIX OFF CACHE INTERNAL "Enable the use of the system found PCREPOSIX library if found")
    set(ENABLE_LibGCC OFF CACHE INTERNAL "Enable the use of the system found LibGCC library if found")
    set(ENABLE_XATTR OFF CACHE INTERNAL "Enable extended attribute support")
    set(ENABLE_ACL OFF CACHE INTERNAL "Enable ACL support")
    set(ENABLE_ICONV OFF CACHE INTERNAL "Enable iconv support")
    set(ENABLE_TAR OFF CACHE INTERNAL "Enable tar building")
    set(ENABLE_CPIO OFF CACHE INTERNAL "Enable cpio building")
    set(ENABLE_CAT OFF CACHE INTERNAL "Enable cat building")
    set(ENABLE_TEST OFF CACHE INTERNAL "Enable unit and regression tests")
    set(ENABLE_INSTALL OFF CACHE INTERNAL "Enable installing of libraries")
    set(ZLIB_INCLUDE_DIR ${MBP_ZLIB_INCLUDES})
    set(ZLIB_LIBRARY ${MBP_ZLIB_LIBRARIES})
    set(LZMA_INCLUDE_DIR ${MBP_LIBLZMA_INCLUDES})
    set(LZMA_LIBRARY ${MBP_LIBLZMA_LIBRARIES})
    set(LZ4_INCLUDE_DIR ${MBP_LZ4_INCLUDES})
    set(LZ4_LIBRARY ${MBP_LZ4_LIBRARIES})
    set(MBP_LIBARCHIVE_INCLUDES ${CMAKE_SOURCE_DIR}/external/libarchive)
    set(MBP_LIBARCHIVE_LIBRARIES archive_static)
    add_subdirectory(external/libarchive)
    # Linking shared library to libarchive's static library, need -fPIC
    set_target_properties(
        archive_static
        PROPERTIES
        POSITION_INDEPENDENT_CODE 1
    )
    # Don't build the shared library
    set_target_properties(
        archive
        PROPERTIES
        EXCLUDE_FROM_ALL 1
        EXCLUDE_FROM_DEFAULT_BUILD 1
    )
endif()


# Install paths

if(${MBP_PORTABLE})
    set(BIN_INSTALL_DIR bin)
    set(DATA_INSTALL_DIR data)
    set(HEADERS_INSTALL_DIR include)

    if(WIN32)
        set(LIB_INSTALL_DIR bin)
    else()
        set(LIB_INSTALL_DIR lib)
    endif()
else()
    set(BIN_INSTALL_DIR ${CMAKE_INSTALL_BINDIR})
    set(LIB_INSTALL_DIR ${CMAKE_INSTALL_LIBDIR})
    set(DATA_INSTALL_DIR ${CMAKE_INSTALL_DATADIR}/mbp)
    set(HEADERS_INSTALL_DIR ${CMAKE_INSTALL_INCLUDEDIR})
endif()

# CPack

set(CPACK_PACKAGE_NAME "DualBootPatcher")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "A patcher for Android ROMs to make them multibootable")
set(CPACK_SOURCE_GENERATOR "TGZ;TBZ2;ZIP")
