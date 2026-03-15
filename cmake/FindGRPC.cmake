# FindGRPC.cmake - Locate gRPC and Protobuf
#
# This module defines:
#   gRPC_FOUND
#   gRPC::grpc++
#   gRPC::grpc
#   protobuf::libprotobuf
#   protobuf::protoc

find_package(PkgConfig QUIET)

if(PkgConfig_FOUND)
    pkg_check_modules(GRPC grpc++ QUIET)
    pkg_check_modules(PROTOBUF protobuf QUIET)
endif()

if(NOT GRPC_FOUND)
    # Try to find via cmake config
    find_package(gRPC CONFIG QUIET)
endif()

if(NOT PROTOBUF_FOUND)
    find_package(Protobuf CONFIG QUIET)
endif()

if(NOT gRPC_FOUND AND NOT GRPC_FOUND)
    # Manual search as fallback
    find_path(GRPC_INCLUDE_DIR grpc/grpc.h
        HINTS ${GRPC_ROOT} ENV GRPC_ROOT
        PATH_SUFFIXES include
    )
    
    find_library(GRPC_LIBRARY grpc
        HINTS ${GRPC_ROOT} ENV GRPC_ROOT
        PATH_SUFFIXES lib lib64
    )
    
    find_library(GRPC_CPP_LIBRARY grpc++
        HINTS ${GRPC_ROOT} ENV GRPC_ROOT
        PATH_SUFFIXES lib lib64
    )
    
    if(GRPC_INCLUDE_DIR AND GRPC_LIBRARY AND GRPC_CPP_LIBRARY)
        set(GRPC_FOUND TRUE)
        add_library(gRPC::grpc UNKNOWN IMPORTED)
        set_target_properties(gRPC::grpc PROPERTIES
            IMPORTED_LOCATION ${GRPC_LIBRARY}
            INTERFACE_INCLUDE_DIRECTORIES ${GRPC_INCLUDE_DIR}
        )
        
        add_library(gRPC::grpc++ UNKNOWN IMPORTED)
        set_target_properties(gRPC::grpc++ PROPERTIES
            IMPORTED_LOCATION ${GRPC_CPP_LIBRARY}
            INTERFACE_INCLUDE_DIRECTORIES ${GRPC_INCLUDE_DIR}
        )
    endif()
endif()

if(NOT Protobuf_FOUND AND NOT PROTOBUF_FOUND)
    find_package(Protobuf QUIET)
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(GRPC DEFAULT_MSG
    gRPC::grpc++ gRPC::grpc protobuf::libprotobuf
)
