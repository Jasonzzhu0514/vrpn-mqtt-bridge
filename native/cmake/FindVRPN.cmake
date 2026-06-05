set(_VRPN_HINTS)

if(DEFINED ENV{VRPN_ROOT})
  list(APPEND _VRPN_HINTS "$ENV{VRPN_ROOT}")
endif()

if(DEFINED ENV{HOMEBREW_PREFIX})
  list(APPEND _VRPN_HINTS "$ENV{HOMEBREW_PREFIX}")
endif()

list(APPEND _VRPN_HINTS
  /opt/homebrew
  /opt/homebrew/opt/vrpn
  /usr/local
  /usr/local/opt/vrpn
  /opt/local
)

find_path(VRPN_INCLUDE_DIR
  NAMES vrpn_Tracker.h vrpn_Connection.h
  HINTS ${_VRPN_HINTS}
  PATH_SUFFIXES include
)

find_library(VRPN_LIBRARY
  NAMES vrpn
  HINTS ${_VRPN_HINTS}
  PATH_SUFFIXES lib lib64
)

find_library(QUAT_LIBRARY
  NAMES quat
  HINTS ${_VRPN_HINTS}
  PATH_SUFFIXES lib lib64
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(VRPN
  REQUIRED_VARS VRPN_INCLUDE_DIR VRPN_LIBRARY
  REASON_FAILURE_MESSAGE
    "Install VRPN development files or set VRPN_ROOT, CMAKE_PREFIX_PATH, VRPN_INCLUDE_DIR and VRPN_LIBRARY."
)

if(VRPN_FOUND AND NOT TARGET VRPN::vrpn)
  add_library(VRPN::vrpn UNKNOWN IMPORTED)
  set_target_properties(VRPN::vrpn PROPERTIES
    IMPORTED_LOCATION "${VRPN_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${VRPN_INCLUDE_DIR}"
  )
  if(QUAT_LIBRARY)
    set_property(TARGET VRPN::vrpn APPEND PROPERTY
      INTERFACE_LINK_LIBRARIES "${QUAT_LIBRARY}"
    )
  endif()
endif()

unset(_VRPN_HINTS)
