# Dockerfile for Monado (XCDE) on Ubuntu 24.04 LTS (glibc 2.39)
# Highly portable: runs on SteamOS (Steam Deck), Ubuntu 24.04+, Fedora, Arch Linux, and all modern distros
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools, compilers, and library dependencies
RUN apt update -qq && \
    apt install -y -qq \
        build-essential \
        clang \
        llvm \
        cmake \
        ninja-build \
        git \
        pkg-config \
        python3 \
        python3-pip \
        wget \
        file \
        libvulkan-dev \
        vulkan-tools \
        libshaderc-dev \
        libavcodec-dev \
        libavformat-dev \
        libavutil-dev \
        libswscale-dev \
        libswresample-dev \
        libopus-dev \
        zlib1g-dev \
        libasound2-dev \
        libpulse-dev \
        libx11-dev \
        libxext-dev \
        libxcursor-dev \
        libxi-dev \
        libxrandr-dev \
        libxss-dev \
        libxtst-dev \
        libwayland-dev \
        libxkbcommon-dev \
        libdrm-dev \
        libgbm-dev \
        libgl1-mesa-dev \
        libegl1-mesa-dev && \
    rm -rf /var/lib/apt/lists/*

# Build and install SDL3 directly to /usr
RUN git clone --depth 1 https://github.com/libsdl-org/SDL.git -b main /tmp/SDL && \
    cmake -S /tmp/SDL -B /tmp/SDL/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DSDL_STATIC=OFF \
        -DSDL_TEST_LIBRARY=OFF && \
    cmake --build /tmp/SDL/build && \
    cmake --install /tmp/SDL/build && \
    rm -rf /tmp/SDL

# Download VulkanMemoryAllocator header
RUN wget -q -O /usr/include/vk_mem_alloc.h https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/master/include/vk_mem_alloc.h

# Python dependencies for generator / lifter
RUN pip3 install --break-system-packages --no-cache-dir capstone unicorn lz4

WORKDIR /monado
