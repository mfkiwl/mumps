# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

#[=======================================================================[.rst:
FindMUMPS
---------

Finds the MUMPS library.
Note that MUMPS generally requires SCALAPACK and LAPACK as well.
PORD is always used, in addition to the optional Scotch + METIS.

COMPONENTS
  s d c z   list one or more. Default is "s d". s: real32, d: real64, c: complex32, z: complex64
  Scotch  MUMPS built with Scotch + METIS
  OpenMP  MUMPS build with OpenMP support

Result Variables
^^^^^^^^^^^^^^^^

MUMPS_LIBRARIES
  libraries to be linked

MUMPS_INCLUDE_DIRS
  dirs to be included

#]=======================================================================]

set(MUMPS_LIBRARY)  # don't endlessly append
set(CMAKE_REQUIRED_FLAGS)

include(CheckFortranSourceCompiles)

# --- functions

function(mumps_openmp_check)

# MUMPS doesn't set any distinct symbols or procedures if OpenMP was linked,
# so we do this indirect test to see if MUMPS needs OpenMP to link.

find_package(OpenMP COMPONENTS C Fortran)

if(NOT OpenMP_FOUND)
  return()
endif()

list(APPEND CMAKE_REQUIRED_FLAGS ${OpenMP_Fortran_FLAGS} ${OpenMP_C_FLAGS})
list(APPEND CMAKE_REQUIRED_INCLUDES ${OpenMP_Fortran_INCLUDE_DIRS} ${OpenMP_C_INCLUDE_DIRS})
list(APPEND CMAKE_REQUIRED_LIBRARIES ${OpenMP_Fortran_LIBRARIES} ${OpenMP_C_LIBRARIES})


check_fortran_source_compiles(
"program test_omp
implicit none
external :: mumps_ana_omp_return, MUMPS_ICOPY_32TO64_64C
call mumps_ana_omp_return()
call MUMPS_ICOPY_32TO64_64C()
end program"
MUMPS_HAVE_OPENMP
SRC_EXT f90
)

set(MUMPS_OpenMP_FOUND true PARENT_SCOPE)

endfunction(mumps_openmp_check)


function(mumps_scotch_check)

# check if Scotch linked
find_package(Scotch COMPONENTS ESMUMPS)
# METIS is required when using Scotch
if(Scotch_FOUND)
  find_package(METIS)
endif()

if(NOT METIS_FOUND)
  return()
endif()

list(APPEND CMAKE_REQUIRED_INCLUDES ${Scotch_INCLUDE_DIRS} ${METIS_INCLUDE_DIRS})
list(APPEND CMAKE_REQUIRED_LIBRARIES ${Scotch_LIBRARIES} ${METIS_LIBRARIES})

check_fortran_source_compiles(
"program test_scotch
implicit none
external :: mumps_scotch
call mumps_scotch()
end program"
MUMPS_HAVE_Scotch
SRC_EXT f90
)

set(MUMPS_Scotch_FOUND true PARENT_SCOPE)

endfunction(mumps_scotch_check)


function(mumps_check)

if(NOT (MUMPS_LIBRARY AND MUMPS_INCLUDE_DIR))
  message(VERBOSE "MUMPS: skip checks as not found")
  return()
endif()

if(NOT SCALAPACK_FOUND)
  find_package(SCALAPACK)
endif()

if(NOT (MPI_C_FOUND AND MPI_Fortran_FOUND))
  # factory FindMPI re-searches, slowing down configure, especialy when many subprojects use MPI
  find_package(MPI COMPONENTS C Fortran)
endif()

if(NOT LAPACK_FOUND)
  find_package(LAPACK)
endif()

set(CMAKE_REQUIRED_INCLUDES ${MUMPS_INCLUDE_DIR} ${SCALAPACK_INCLUDE_DIRS} ${LAPACK_INCLUDE_DIRS} ${MPI_Fortran_INCLUDE_DIRS} ${MPI_C_INCLUDE_DIRS})
set(CMAKE_REQUIRED_LIBRARIES ${MUMPS_LIBRARY} ${SCALAPACK_LIBRARIES} ${LAPACK_LIBRARIES} ${MPI_Fortran_LIBRARIES} ${MPI_C_LIBRARIES})

if(OpenMP IN LISTS MUMPS_FIND_COMPONENTS)
  mumps_openmp_check()
endif()

if(Scotch IN LISTS MUMPS_FIND_COMPONENTS)
  mumps_scotch_check()
endif()

foreach(c IN LISTS MUMPS_FIND_COMPONENTS)
  if(NOT c IN_LIST mumps_ariths)
    continue()
  endif()

  check_fortran_source_compiles(
  "program test_mumps
  implicit none
  include '${c}mumps_struc.h'
  external :: ${c}mumps
  type(${c}mumps_struc) :: mumps_par
  end program"
  MUMPS_${c}_links
  SRC_EXT f90
  )

  if(NOT MUMPS_${c}_links)
    continue()
  endif()

  set(MUMPS_${c}_FOUND true PARENT_SCOPE)
endforeach()

set(MUMPS_links true PARENT_SCOPE)

endfunction(mumps_check)


function(mumps_libs)

# NOTE: NO_DEFAULT_PATH disables CMP0074 MUMPS_ROOT and PATH_SUFFIXES, so we manually specify:
# HINTS ${MUMPS_ROOT} ENV MUMPS_ROOT
# PATH_SUFFIXES ...
# to allow MKL using user-built MUMPS with `cmake -DMUMPS_ROOT=~/lib_intel/mumps`

if(DEFINED ENV{MKLROOT})
  find_path(MUMPS_INCLUDE_DIR
  NAMES mumps_compat.h
  NO_DEFAULT_PATH
  HINTS ${MUMPS_ROOT} ENV MUMPS_ROOT ${CMAKE_PREFIX_PATH} ENV CMAKE_PREFIX_PATH
  PATH_SUFFIXES include
  DOC "MUMPS common header"
  )
else()
  find_path(MUMPS_INCLUDE_DIR
  NAMES mumps_compat.h
  PATH_SUFFIXES MUMPS openmpi-x86_64 mpich-x86_64
  DOC "MUMPS common header"
  )
endif()
if(NOT MUMPS_INCLUDE_DIR)
  return()
endif()

# get Mumps version
find_file(mumps_conf
NAMES smumps_c.h dmumps_c.h
HINTS ${MUMPS_INCLUDE_DIR}
NO_DEFAULT_PATH
DOC "MUMPS configuration header"
)

if(mumps_conf)
  file(STRINGS ${mumps_conf} _def
  REGEX "^[ \t]*#[ \t]*define[ \t]+MUMPS_VERSION[ \t]+" )

  if("${_def}" MATCHES "MUMPS_VERSION[ \t]+\"([0-9]+\\.[0-9]+\\.[0-9]+)?\"")
    set(MUMPS_VERSION "${CMAKE_MATCH_1}" PARENT_SCOPE)
  endif()
endif()

# --- Mumps Common ---
if(DEFINED ENV{MKLROOT})
  find_library(MUMPS_COMMON
  NAMES mumps_common
  NO_DEFAULT_PATH
  HINTS ${MUMPS_ROOT} ENV MUMPS_ROOT ${CMAKE_PREFIX_PATH} ENV CMAKE_PREFIX_PATH
  PATH_SUFFIXES lib
  DOC "MUMPS MPI common libraries"
  )
else()
  find_library(MUMPS_COMMON
  NAMES mumps_common mumps_common_mpi mumpso_common mumps_common_shm
  NAMES_PER_DIR
  PATH_SUFFIXES openmpi/lib mpich/lib
  DOC "MUMPS common libraries"
  )
endif()

if(NOT MUMPS_COMMON)
  return()
endif()

# --- Pord ---

if(DEFINED ENV{MKLROOT})
  find_library(PORD
  NAMES pord
  NO_DEFAULT_PATH
  HINTS ${MUMPS_ROOT} ENV MUMPS_ROOT ${CMAKE_PREFIX_PATH} ENV CMAKE_PREFIX_PATH
  PATH_SUFFIXES lib
  DOC "PORD ordering library"
  )
else()
  find_library(PORD
  NAMES pord mumps_pord
  NAMES_PER_DIR
  PATH_SUFFIXES openmpi/lib mpich/lib
  DOC "PORD ordering library"
  )
endif()
if(NOT PORD)
  return()
endif()

foreach(c IN LISTS MUMPS_FIND_COMPONENTS)
  if(NOT c IN_LIST mumps_ariths)
    continue()
  endif()

  if(DEFINED ENV{MKLROOT})
    find_library(MUMPS_${c}_lib
    NAMES ${c}mumps
    NO_DEFAULT_PATH
    HINTS ${MUMPS_ROOT} ENV MUMPS_ROOT ${CMAKE_PREFIX_PATH} ENV CMAKE_PREFIX_PATH
    PATH_SUFFIXES lib
    DOC "MUMPS precision-specific"
    )
  else()
    find_library(MUMPS_${c}_lib
    NAMES ${c}mumps ${c}mumps_mpi
    NAMES_PER_DIR
    PATH_SUFFIXES openmpi/lib mpich/lib
    DOC "MUMPS precision-specific"
    )
  endif()

  if(NOT MUMPS_${c}_lib)
    continue()
  endif()

  list(APPEND MUMPS_LIBRARY ${MUMPS_${c}_lib})
endforeach()

set(MUMPS_LIBRARY ${MUMPS_LIBRARY} ${MUMPS_COMMON} ${PORD} PARENT_SCOPE)

endfunction(mumps_libs)

# --- main

# need to have at least one arith precision component
set(mumps_ariths s d c z)

set(mumps_need_default true)
foreach(c IN LISTS MUMPS_FIND_COMPONENTS)
  if(c IN_LIST mumps_ariths)
    set(mumps_need_default false)
    break()
  endif()
endforeach()
if(mumps_need_default)
  list(APPEND MUMPS_FIND_COMPONENTS s d)
endif()

mumps_libs()

mumps_check()

# --- finalize

set(CMAKE_REQUIRED_FLAGS)
set(CMAKE_REQUIRED_INCLUDES)
set(CMAKE_REQUIRED_LIBRARIES)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(MUMPS
REQUIRED_VARS MUMPS_LIBRARY MUMPS_INCLUDE_DIR MUMPS_links
VERSION_VAR MUMPS_VERSION
HANDLE_COMPONENTS
)

if(MUMPS_FOUND)
  # need if _FOUND guard as can't overwrite imported target even if bad
  set(MUMPS_LIBRARIES ${MUMPS_LIBRARY})
  set(MUMPS_INCLUDE_DIRS ${MUMPS_INCLUDE_DIR})

  message(VERBOSE "Mumps libraries: ${MUMPS_LIBRARIES}
Mumps include directories: ${MUMPS_INCLUDE_DIRS}")

  if(NOT TARGET MUMPS::MUMPS)
    add_library(MUMPS::MUMPS INTERFACE IMPORTED)
    set_property(TARGET MUMPS::MUMPS PROPERTY INTERFACE_LINK_LIBRARIES "${MUMPS_LIBRARY};SCALAPACK::SCALAPACK;LAPACK::LAPACK;${MPI_Fortran_LIBRARIES};MPI::MPI_C")
    set_property(TARGET MUMPS::MUMPS PROPERTY INTERFACE_INCLUDE_DIRECTORIES "${MUMPS_INCLUDE_DIR};${MPI_Fortran_INCLUDE_DIRS}")
  endif()

endif(MUMPS_FOUND)

mark_as_advanced(MUMPS_INCLUDE_DIR MUMPS_LIBRARY)
