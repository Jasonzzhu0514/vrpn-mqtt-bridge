find_path(VRPN_INCLUDE_DIR
  NAMES vrpn_Tracker.h vrpn_Connection.h
  PATHS
    /opt/ros/noetic/include
    /opt/ros/humble/include
    /opt/ros/iron/include
    /opt/ros/jazzy/include
    /usr/local/include
    /usr/include
)

find_library(VRPN_LIBRARY
  NAMES vrpn
  PATHS
    /opt/ros/noetic/lib
    /opt/ros/humble/lib
    /opt/ros/iron/lib
    /opt/ros/jazzy/lib
    /usr/local/lib
    /usr/lib
    /usr/lib/x86_64-linux-gnu
)

find_library(QUAT_LIBRARY
  NAMES quat
  PATHS
    /opt/ros/noetic/lib
    /opt/ros/humble/lib
    /opt/ros/iron/lib
    /opt/ros/jazzy/lib
    /usr/local/lib
    /usr/lib
    /usr/lib/x86_64-linux-gnu
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(VRPN
  REQUIRED_VARS VRPN_INCLUDE_DIR VRPN_LIBRARY QUAT_LIBRARY
)

if(VRPN_FOUND AND NOT TARGET VRPN::vrpn)
  add_library(VRPN::vrpn UNKNOWN IMPORTED)
  set_target_properties(VRPN::vrpn PROPERTIES
    IMPORTED_LOCATION "${VRPN_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${VRPN_INCLUDE_DIR}"
    INTERFACE_LINK_LIBRARIES "${QUAT_LIBRARY}"
  )
endif()
