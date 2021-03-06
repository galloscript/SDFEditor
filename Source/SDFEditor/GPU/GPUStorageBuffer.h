// Copyright (c) 2022 David Gallardo and SDFEditor Project

#pragma once

#include <cstdint>
#include <memory>

using CGPUBufferObjectRef = std::shared_ptr<class CGPUBufferObject>;

namespace EGPUBufferFlags
{
    enum Type
    {
        MAP_READ_BIT = 0x0001,
        MAP_WRITE_BIT = 0x0002,
        DYNAMIC_STORAGE = 0x0100,
        ALL = MAP_READ_BIT | MAP_WRITE_BIT | DYNAMIC_STORAGE,
    };
};

namespace EGPUBufferBindTarget
{
    enum Type
    {
        UNIFORM_BUFFER,
        SHADER_BUFFER_STORAGE,
        ATOMIC_COUNTER_BUFFER,
        DISPATCH_INDIRECT_BUFFER,
        COPY_READ_BUFFER,
        COPY_WRITE_BUFFER,
    };
};

class CGPUBufferObject
{
public:
    CGPUBufferObject(EGPUBufferBindTarget::Type aTarget);
    ~CGPUBufferObject();

    void SetData(size_t aSize, void* aData, uint32_t aFlags = EGPUBufferFlags::ALL);
    void UpdateSubData(intptr_t aOffset, size_t aSize, void* aData);

    void* Map();
    void Unmap();

    uint32_t GetHandler() const { return mBufferHandler; }
    size_t GetStorageSize() const { return mStorageSize; }

    void BindShaderStorage(uint32_t aBindingIndex);
    void BindUniformBuffer(uint32_t aBindingIndex);

    void BindTarget(EGPUBufferBindTarget::Type aBindTarget);
    void UnbindTarget(EGPUBufferBindTarget::Type aBindTarget);

private:
    uint32_t mBufferHandler;
    size_t mStorageSize;

    EGPUBufferBindTarget::Type mTarget;
};