# Eigen Vendor Location

This directory is reserved for vendored Eigen headers used by the native
Octave backend build.

Expected layout:

- `third_party/eigen/Eigen/Core`
- `third_party/eigen/Eigen/Dense`

Build helper:

- `kernels/native/build_peec_native_backend.m`

Notes:

- Current native solver implementation does not require advanced Eigen APIs.
- The include path is still wired into the build command to keep the dependency
  policy stable for subsequent native kernel upgrades.
