find_path(VRPN_INCLUDE_DIR
  NAMES vrpn_Tracker.h vrpn_Connection.h
)

find_library(VRPN_LIBRARY
  NAMES vrpn
)

find_library(QUAT_LIBRARY
  NAMES quat
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
