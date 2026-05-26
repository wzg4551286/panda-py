#!/bin/bash
set -euo pipefail

# Pick the upstream libfranka repository. As of late 2024 the project moved
# from frankaemika/libfranka to frankarobotics/libfranka. We only fall back
# to the legacy fork for very old versions that JeanElsner had patched.
repo="https://github.com/frankarobotics/libfranka.git"
if [[ "${LIBFRANKA_VER:-}" == "0.7.1" || "${LIBFRANKA_VER:-}" == "0.8.0" ]]; then
  repo="https://github.com/JeanElsner/libfranka.git"
elif [[ "${LIBFRANKA_VER:-}" == "0.9.2" || "${LIBFRANKA_VER:-}" == "0.13.3" ]]; then
  # These tags only exist on the legacy frankaemika mirror
  repo="https://github.com/frankaemika/libfranka.git"
fi

# Base build tooling + dependencies common to every libfranka version.
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake git \
    libpoco-dev libeigen3-dev

# libfranka >= 0.14 additionally requires Pinocchio (kinematics/dynamics),
# TinyXML2 (URDF parsing) and fmt; >= 0.18 also requires console_bridge.
# These are all kept private inside the libfranka shared library, but they
# must be present at build time. Available on Ubuntu 22.04+.
if [[ "${LIBFRANKA_VER:-0.20.5}" != "0.7.1" \
   && "${LIBFRANKA_VER:-0.20.5}" != "0.8.0" \
   && "${LIBFRANKA_VER:-0.20.5}" != "0.9.2" \
   && "${LIBFRANKA_VER:-0.20.5}" != "0.13.3" ]]; then
  sudo apt-get install -y \
      libtinyxml2-dev libfmt-dev libconsole-bridge-dev \
      robotpkg-pinocchio || \
  sudo apt-get install -y \
      libtinyxml2-dev libfmt-dev libconsole-bridge-dev \
      libpinocchio-dev
fi

sudo apt remove -y "*libfranka*" || true
rm -rf libfranka
git clone --recursive "$repo"
cd libfranka
git checkout "${LIBFRANKA_VER}"
git submodule update --init --recursive
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF ..
cmake --build . -j"$(nproc)"
cpack -G DEB
sudo dpkg -i libfranka*.deb || sudo apt-get install -fy
