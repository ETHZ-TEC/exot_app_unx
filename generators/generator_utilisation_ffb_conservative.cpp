// Copyright (c) 2015-2020, Swiss Federal Institute of Technology (ETH Zurich)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// 
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// 
// * Neither the name of the copyright holder nor the names of its
//   contributors may be used to endorse or promote products derived from
//   this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// 
/**
 * @file generators/generator_utilisation_ffb_conservative.cpp
 * @author     Philipp Miedl, Bruno Klopott
 * @brief      Single-threaded generator imposing a computation-driven load on
 *             the system depending on the current operating frequency.
 */

#ifndef GENERATOR_HOST_PERFORM_VALIDATION
#define GENERATOR_HOST_PERFORM_VALIDATION true
#endif

#include <chrono>

#include <exot/components/generator_ffb.h>
#include <exot/components/schedule_reader.h>
#include <exot/generators/utilisation_ffb_conservative.h>
#include <exot/utilities/main.h>

using loadgen_t = exot::components::generator_ffb<
    std::chrono::nanoseconds,
    exot::modules::generator_utilisation_ffb_conservative>;
using reader_t =
    exot::components::schedule_reader<typename loadgen_t::token_type>;

int main(int argc, char** argv) {
  return exot::utilities::cli_wrapper<reader_t, loadgen_t>(argc, argv);
}
