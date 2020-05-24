### Unix applications

This repository contains sink and source applications built on top of the [ExOT Application Library](https://gitlab.ethz.ch/tec/public/exot/app_lib), and relevant utilities. Current development versions are available in the `develop` branch.

The [generators](generators) folder contains the source applications, and [meters](meters) contains sink applications. The library is imported as a git submodule at *lib*. The [scripts](scripts) folder contains auxiliary files, most notably the script for [distributing meters as systemd services](scripts/pack-for-distribution.sh).

### How to add/compile applications

To import the library, first clone the repository with submodules:

~~~sh
git clone --recursive https://gitlab.ethz.ch/tec/public/exot/app_unx.git
~~~

If the repository was cloned without the `--recursive` flag, make sure to import the dependent submodules:

~~~sh
# run beforehand...
git clone https://gitlab.ethz.ch/tec/public/exot/app_unx.git
git submodule update --init --recursive
~~~

The main build file, [CMakeLists.txt](CMakeLists.txt), considers every single C++ source file as a separate application, and provides a build target for it. For example, a file [utilisation.cpp](meters/utilisation.cpp) will create a `utilisation` make target. Applications can be added manually to the build file, or take advantage of the automatic build target creation.

The applications' repository has the same dependencies as the application library, at minimum:

- [CMake] ~> 3.6, preferably one that understands the C++17 standard (~> 3.8). A recent version should be available in package repositories on most Linux distributions;
- A C++ compiler conforming to the C++17 standard;
- A recent C++ standard library, conforming to the C++17 standard. This could be the GNU libstdc++ from [GCC 7] and higher (libstdc++.so.6.0.23 and higher).

[CMake]: https://cmake.org
[GCC 7]: https://gcc.gnu.org/projects/cxx-status.html#cxx17

The project uses CMake toolchains to bootstrap compiler options, please refer to CMake [documentation](https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html) or browse through the toolchain folder.[^1] To compile an application, first create a build directory:

~~~sh
# Debug configuration, with symbols, static analysis, and no optimisation
cmake -DCMAKE_TOOLCHAIN_FILE=<path/to/toolchain> \
      -DCMAKE_BUILD_TYPE=Debug -B build/Debug -H.
# Release build, no symbols, no debug statements, high optimisation
cmake -DCMAKE_TOOLCHAIN_FILE=<path/to/toolchain> \
      -DCMAKE_BUILD_TYPE=Release -B build/Release -H.
~~~

Then, to compile specific targets, choose the build folder and run:

```sh
cmake --build build/{Debug,Release} --target <target name> -- -j 0
```

Please consult the [application library](https://gitlab.ethz.ch/tec/public/exot/app_lib) for further options, like adding memory or thread sanitisers to CMake targets.

---

[^1]: With an imported library, the toolchains are located at `lib/cmake/toolchains`.
