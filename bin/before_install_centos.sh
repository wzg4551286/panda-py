#!/bin/bash
set -euo pipefail

# This script targets the manylinux_2_28 image (RHEL 8 / AlmaLinux 8 base),
# which has the modern toolchain and dnf packages required by libfranka >=
# 0.14. The old manylinux2014 (CentOS 7) cannot easily install Pinocchio and
# is no longer supported by this script for libfranka >= 0.14.

# --- base toolchain / common dependencies ---------------------------------
dnf -y install \
    gcc-toolset-12 \
    cmake git make pkgconf-pkg-config \
    openssl-devel zlib-devel \
    eigen3-devel boost-devel

# Activate the modern GCC toolchain (needed for libfranka's C++17 usage).
# scl_source is preferred but fall back to PATH munging for non-bash runners.
if [[ -f /opt/rh/gcc-toolset-12/enable ]]; then
  # shellcheck disable=SC1091
  source /opt/rh/gcc-toolset-12/enable
fi

# --- Poco ------------------------------------------------------------------
if ! pkg-config --exists Poco; then
  rm -rf poco
  git clone https://github.com/pocoproject/poco.git
  pushd poco
  git checkout poco-1.12.4-release
  mkdir -p cmake-build && cd cmake-build
  cmake \
    -DENABLE_ENCODINGS=OFF -DENABLE_ENCODINGS_COMPILER=OFF \
    -DENABLE_XML=ON -DENABLE_JSON=ON \
    -DENABLE_MONGODB=OFF -DENABLE_DATA_SQLITE=OFF -DENABLE_REDIS=OFF \
    -DENABLE_PDF=OFF -DENABLE_UTIL=ON -DENABLE_NET=ON \
    -DENABLE_SEVENZIP=OFF -DENABLE_ZIP=OFF \
    -DENABLE_CPPPARSER=OFF -DENABLE_POCODOC=OFF \
    -DENABLE_PAGECOMPILER=OFF -DENABLE_PAGECOMPILER_FILE2PAGE=OFF \
    -DENABLE_ACTIVERECORD=OFF -DENABLE_ACTIVERECORD_COMPILER=OFF \
    -DCMAKE_BUILD_TYPE=Release ..
  cmake --build . --config Release -j"$(nproc)"
  cmake --build . --target install
  popd
fi

# --- Deps newly required by libfranka >= 0.14 -----------------------------
# fmt, tinyxml2, console_bridge are easy via dnf (EPEL on RHEL 8).
dnf -y install epel-release || true
dnf -y install \
    fmt-devel tinyxml2-devel console-bridge-devel || true

# Pinocchio is not in EPEL; build from source against the system Eigen3.
if ! pkg-config --exists pinocchio; then
  rm -rf pinocchio
  git clone --recursive https://github.com/stack-of-tasks/pinocchio.git
  pushd pinocchio
  git checkout v2.7.0
  mkdir -p build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_PYTHON_INTERFACE=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_WITH_COLLISION_SUPPORT=OFF ..
  cmake --build . -j"$(nproc)"
  cmake --build . --target install
  popd
fi

# --- libfranka itself -----------------------------------------------------
repo="https://github.com/frankarobotics/libfranka.git"
if [[ "${LIBFRANKA_VER:-}" == "0.7.1" || "${LIBFRANKA_VER:-}" == "0.8.0" ]]; then
  repo="https://github.com/JeanElsner/libfranka.git"
elif [[ "${LIBFRANKA_VER:-}" == "0.9.2" || "${LIBFRANKA_VER:-}" == "0.13.3" ]]; then
  repo="https://github.com/frankaemika/libfranka.git"
fi

rm -rf libfranka
git clone --recursive "$repo"
cd libfranka
git checkout "${LIBFRANKA_VER}"
git submodule update --init --recursive
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF ..
cmake --build . -j"$(nproc)"
cmake --build . --target install
