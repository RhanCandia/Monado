# Dockerfile for Monado (XCDE) on Arch Linux
FROM archlinux:latest

# Update system and install toolchain + dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        base-devel \
        clang \
        llvm \
        cmake \
        ninja \
        git \
        pkgconf \
        python \
        python-pip \
        sdl3 \
        vulkan-headers \
        vulkan-icd-loader \
        shaderc \
        ffmpeg \
        opus \
        zlib \
        file \
        wget

# Download VulkanMemoryAllocator header
RUN wget -q -O /usr/include/vk_mem_alloc.h https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/master/include/vk_mem_alloc.h

# Python dependencies for the generator / lifter
RUN pip install --break-system-packages --no-cache-dir capstone unicorn lz4

WORKDIR /monado
