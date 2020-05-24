# Copyright (c) 2015-2020, Swiss Federal Institute of Technology (ETH Zurich)
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 
cmake_minimum_required(VERSION 3.8)
project(unix-apps VERSION 2.0.0 LANGUAGES CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/lib/cmake/modules")
include(sanitizers)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED on)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Import the library
add_subdirectory(lib)

# The custom target all-meters will build all available sink applications
add_custom_target(all-meters)
# The custom target all-generators will build all available source applications
add_custom_target(all-generators)
# The custom target all-apps will build all-meters and all-generators
add_custom_target(all-apps)

# The custom target all-utilities will build all available utilities
add_custom_target(all-utilities)

# Sink applications ############################################################

# Consider each single-file C++ source in 'meters' to be a separate sink
# application
file(GLOB sinks "${CMAKE_CURRENT_LIST_DIR}/meters/*.cpp")

foreach(sink ${sinks})
  get_filename_component(_name ${sink} NAME_WE)
  add_executable(${_name} ${sink})
  target_link_libraries(${_name} PRIVATE exot exot-modules)
  add_dependencies(all-meters ${_name})
endforeach(sink)

# Source applications ##########################################################

# Consider each single-file C++ source in 'generators' to be a separate source
# application
file(GLOB sources "${CMAKE_CURRENT_LIST_DIR}/generators/*.cpp")

foreach(source ${sources})
  get_filename_component(_name ${source} NAME_WE)
  add_executable(${_name} ${source})
  target_link_libraries(${_name} PRIVATE exot exot-modules)
  add_dependencies(all-generators ${_name})
endforeach(source)

add_dependencies(all-apps all-generators)
add_dependencies(all-apps all-meters)

# Consider each single-file C++ source in 'utilities' to be a separate application
file(GLOB utilities "${CMAKE_CURRENT_LIST_DIR}/utilities/*.cpp")

foreach(source ${utilities})
  get_filename_component(_name ${source} NAME_WE)
  add_executable(${_name} ${source})
  target_link_libraries(${_name} PRIVATE exot exot-modules)
  add_dependencies(all-utilities ${_name})
endforeach(source)
