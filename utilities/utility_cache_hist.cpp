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
#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <tuple>
#include <utility>

#include <fmt/format.h>
#include <fmt/ostream.h>
#include <spdlog/spdlog.h>

#include <spdlog/sinks/stdout_color_sinks.h>

#include <exot/framework/all.h>
#include <exot/primitives/cache.h>
#include <exot/utilities/alignment.h>
#include <exot/utilities/allocator.h>
#include <exot/utilities/configuration.h>
#include <exot/utilities/eviction.h>
#include <exot/utilities/fmt.h>
#include <exot/utilities/helpers.h>
#include <exot/utilities/literals.h>
#include <exot/utilities/logging.h>
#include <exot/utilities/main.h>
#include <exot/utilities/thread.h>
#include <exot/utilities/timing.h>
#include <exot/utilities/types.h>

#if defined(__x86_64__)
#include <exot/primitives/tsc.h>
#else
#include <exot/utilities/timing_source.h>
#endif

using namespace exot::utilities::literals;
using namespace std::literals::string_literals;

using return_t   = std::uint64_t;
using void_ptr_t = void*;

inline namespace raw {
inline __attribute__((always_inline)) return_t flush(void_ptr_t addr) {
#if defined(__x86_64__)
  return exot::utilities::timeit<
      exot::primitives::MemoryFencedSerialisingFlushTSC>(
      exot::primitives::flush, addr);
#else
  return exot::utilities::default_timing_facility(exot::primitives::flush,
                                                  addr);
#endif
}
inline __attribute__((always_inline)) return_t prefetch(void_ptr_t addr) {
#if defined(__x86_64__)
  return exot::utilities::timeit<exot::primitives::MemoryFencedPrefetchTSC>(
      exot::primitives::prefetch, addr);
#else
  return exot::utilities::default_timing_facility(exot::primitives::prefetch,
                                                  addr);
#endif
}
inline __attribute__((always_inline)) return_t reload(void_ptr_t addr) {
#if defined(__x86_64__)
  return exot::utilities::timeit<exot::primitives::MemoryFencedTSC>(
      exot::primitives::access_read<>, addr);
#else
  return exot::utilities::default_timing_facility(
      exot::primitives::access_read<>, addr);
#endif
}
}  // namespace raw

inline namespace channel_access {
inline __attribute__((always_inline)) return_t flush_flush(void_ptr_t addr) {
#if defined(__x86_64__)
  return exot::utilities::timeit<
      exot::primitives::MemoryFencedSerialisingFlushTSC>(
      exot::primitives::flush, addr);
#else
  return exot::utilities::default_timing_facility(exot::primitives::flush,
                                                  addr);
#endif
}

inline __attribute__((always_inline)) return_t flush_prefetch(void_ptr_t addr) {
#if defined(__x86_64__)
  auto _ = exot::utilities::timeit<exot::primitives::MemoryFencedPrefetchTSC>(
      exot::primitives::prefetch, addr);
  exot::primitives::flush(addr);
  return _;
#else
  auto _ = exot::utilities::default_timing_facility(exot::primitives::prefetch,
                                                    addr);
  exot::primitives::flush(addr);
  return _;
#endif
}

inline __attribute__((always_inline)) return_t flush_reload(void_ptr_t addr) {
#if defined(__x86_64__)
  auto _ = exot::utilities::timeit<exot::primitives::MemoryFencedTSC>(
      exot::primitives::access_read<>, addr);
  exot::primitives::flush(addr);
  return _;
#else
  auto _ = exot::utilities::default_timing_facility(
      exot::primitives::access_read<>, addr);
  exot::primitives::flush(addr);
  return _;
#endif
}

}  // namespace channel_access

namespace util {

template <typename T, bool Forceful = false,
          typename = std::enable_if_t<
              (exot::utilities::is_iterable_v<T> ||
               exot::utilities::is_same_d<T, void_ptr_t>::value)>>
void reload(T& value) {
  if constexpr (exot::utilities::is_iterable_v<T>) {
    static_assert(
        exot::utilities::is_same_d<typename T::value_type, void_ptr_t>::value,
        "iterable must contain void* values");

    std::for_each(value.begin(), value.end(),
                  reload<typename T::value_type, Forceful>);
  } else {
    exot::utilities::const_for<0, 4>(
        [&value](const auto I) { exot::primitives::access_read<>(value); });

    if constexpr (Forceful) {
      std::this_thread::yield();
      exot::utilities::const_for<0, 4>(
          [&value](const auto I) { exot::primitives::access_read<>(value); });
    }
  }
}

template <typename T, bool Forceful = false,
          typename = std::enable_if_t<
              (exot::utilities::is_iterable_v<T> ||
               exot::utilities::is_same_d<T, void_ptr_t>::value)>>
void flush(T& value) {
  if constexpr (exot::utilities::is_iterable_v<T>) {
    static_assert(
        exot::utilities::is_same_d<typename T::value_type, void_ptr_t>::value,
        "iterable must contain void* values");

    std::for_each(value.begin(), value.end(),
                  flush<typename T::value_type, Forceful>);
  } else {
    if constexpr (Forceful) {
      exot::primitives::flush(value);
      std::this_thread::yield();
    } else {
      exot::utilities::const_for<0, 3>([&value](const auto I) {
        exot::primitives::flush(value);
        std::this_thread::yield();
      });
    }
  }
}

}  // namespace util

struct Evaluator : public exot::framework::IProcess {
  struct settings : public exot::utilities::configurable<settings> {
    using policy_type = exot::utilities::SchedulingPolicy;

    policy_type self_policy{policy_type::Other};
    unsigned self_priority{0u};
    std::optional<unsigned> cpu_to_pin{std::nullopt};
    unsigned count{1'000u};
    unsigned sets{16u};
    bool measure_with_perf{true};
    bool start_immediately{true};

    const char* name() const { return "utility"; }

    /* @brief The JSON configuration function */
    void configure() {
      bind_and_describe_data("cpu_to_pin", cpu_to_pin, "core pinning |uint|");
      bind_and_describe_data(
          "self_policy", self_policy,
          "scheduling policy of the utility |str, policy_type|, "
          "e.g. \"round_robin\"");
      bind_and_describe_data(
          "self_priority", self_priority,
          "scheduling priority of the utility |uint|, in range "
          "[0, 99], e.g. 99");
      bind_and_describe_data("count", count,
                             "number of measurement iterations |uint|");
      bind_and_describe_data(
          "sets", sets, "number of sets to evaluate |uint|, in range [1, 64]");
      bind_and_describe_data(
          "measure_with_perf", measure_with_perf,
          "measure channel access with perf clock on ARM? |bool|");
      bind_and_describe_data("start_immediately", start_immediately,
                             "start collection immediately? |bool|");
    }
  };

  explicit Evaluator(settings& conf)
      : conf_{conf}, global_state_{exot::framework::GLOBAL_STATE->get()} {
    if (conf_.sets > 64)
      throw std::logic_error("conf->sets must be less than or equal 64");

    // fill the arr with dummy values
    std::iota(arr.begin(), arr.end(), 0);
    // fill the ptr_arr with pointers to arr values
    for (auto n = 0; n < arr.size(); ++n) {
      ptr_arr[n] = reinterpret_cast<void_ptr_t>(&arr[n]);
    }
  }

  void process() {
    if (conf_.cpu_to_pin.has_value())
      exot::utilities::ThreadTraits::set_affinity(conf_.cpu_to_pin.value());
    exot::utilities::ThreadTraits::set_scheduling(conf_.self_policy,
                                                  conf_.self_priority);

    debug_log_->info("[Evaluator] running on {}",
                     exot::utilities::thread_info());

#if !defined(__x86_64__)
    exot::utilities::default_timing_facility([] {});
#endif

    while (!global_state_->is_started() && !conf_.start_immediately) {
      std::this_thread::sleep_for(std::chrono::milliseconds{1});
    }

    application_log_->info(
        "{}", "placeholder,method,category,class,sets,index,duration");

    measure(raw::flush, channel_access::flush_flush, "flush_flush"s);
    measure(raw::prefetch, channel_access::flush_prefetch, "flush_prefetch"s);
    measure(raw::reload, channel_access::flush_reload, "flush_reload"s);

    debug_log_->info("[Evaluator] finished measurements");
  }

  /**
   * @brief Measures the access times for raw operations and channel accesses
   *
   * @tparam Raw         The raw function type
   * @tparam Operation   The channel access operation type
   * @tparam Forceful    Use forceful reload/flush?
   * @param  raw         The raw function (choose from namespace 'raw' above)
   * @param  op          The channel access function (choose from namespace
   *                     'channel_access' above)
   * @param  method      A string identifier for reporting purposes
   */
  template <typename Raw, typename Operation, bool Forceful = false>
  void measure(Raw&& raw, Operation&& op, std::string&& method) {
    static auto raw_hit_holder  = std::vector<return_t>(conf_.count);
    static auto raw_miss_holder = std::vector<return_t>(conf_.count);
    static auto op_hit_holder   = std::vector<return_t>(conf_.count);
    static auto op_miss_holder  = std::vector<return_t>(conf_.count);

    // raw hit
    for (auto i = 0; i < conf_.count; ++i) {
      util::reload<decltype(ptr), Forceful>(ptr);
      raw_hit_holder[i] = raw(ptr);
    }

    // dump raw hit
    for (auto i = 0; i < conf_.count; ++i) {
      application_log_->info("0,{},raw,hit,0,{},{}", method, i,
                             raw_hit_holder[i]);
    }

    for (auto current_sets = 1; current_sets <= conf_.sets; ++current_sets) {
      // op hit
      for (auto i = 0; i < conf_.count; ++i) {
        util::reload<decltype(ptr_arr), Forceful>(ptr_arr);
        op_hit_holder[i] = measure_duration([&, this]() {
          for (auto j = 0; j < current_sets; ++j) {
            auto dummy = op(ptr_arr[j]);
          }
        });
      }

      // dump op hit
      for (auto i = 0; i < conf_.count; ++i) {
        application_log_->info("0,{},access,hit,{},{},{}", method, current_sets,
                               i, op_hit_holder[i]);
      }
    }

    util::flush<decltype(ptr), true>(ptr);
    util::flush<decltype(ptr_arr), true>(ptr_arr);

    // raw miss
    for (auto i = 0; i < conf_.count; ++i) {
      util::flush<decltype(ptr), Forceful>(ptr);
      raw_miss_holder[i] = raw(ptr);
    }

    // dump raw miss
    for (auto i = 0; i < conf_.count; ++i) {
      application_log_->info("0,{},raw,miss,0,{},{}", method, i,
                             raw_miss_holder[i]);
    }

    for (auto current_sets = 1; current_sets <= conf_.sets; ++current_sets) {
      // op miss
      for (auto i = 0; i < conf_.count; ++i) {
        util::flush<decltype(ptr_arr), Forceful>(ptr_arr);
        op_miss_holder[i] = measure_duration([&, this]() {
          for (auto j = 0; j < current_sets; ++j) {
            auto dummy = op(ptr_arr[j]);
          }
        });
      }

      // dump op miss
      for (auto i = 0; i < conf_.count; ++i) {
        application_log_->info("0,{},access,miss,{},{},{}", method,
                               current_sets, i, op_miss_holder[i]);
      }
    }
  }

  template <typename Callable, typename... Args>
  auto measure_duration(Callable&& callable, Args&&... args) {
    using namespace exot::utilities;

#if defined(__x86_64__)
    return timeit<exot::primitives::MemoryFencedTSC>(
        std::forward<Callable>(callable), std::forward<Args>(args)...);
#else
    if (conf_.measure_with_perf) {
      return default_timing_facility(std::forward<Callable>(callable),
                                     std::forward<Args>(args)...);
    } else {
      return timeit<serialised_time_source_t<
          time_source_t<TimingSourceType::SteadyClock>,
          TimingFenceType::Strong>>(std::forward<Callable>(callable),
                                    std::forward<Args>(args)...)
          .count();
    }
#endif
  }

 private:
  using state_type     = exot::framework::State;
  using state_pointer  = std::shared_ptr<state_type>;
  using logger_pointer = std::shared_ptr<spdlog::logger>;

  exot::utilities::aligned_t<std::uint8_t, 64> var{1u};
  void_ptr_t ptr{reinterpret_cast<void_ptr_t>(&var)};
  std::array<exot::utilities::aligned_t<std::uint8_t, 64>, 64> arr;
  std::array<void_ptr_t, 64> ptr_arr;

  settings conf_;
  state_pointer global_state_;

  logger_pointer application_log_ =
      spdlog::get("app") ? spdlog::get("app") : spdlog::stdout_color_mt("app");
  logger_pointer debug_log_ =
      spdlog::get("log") ? spdlog::get("log") : spdlog::stderr_color_mt("log");
};

using component_t = Evaluator;

int main(int argc, char** argv) {
  return exot::utilities::cli_wrapper<component_t>(argc, argv);
}
