#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#define IR_PRIVATE_IMPLEMENTATION
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>
#include <cstdio>
#include <random>

@interface ViewResource : NSObject {
@public uint64_t address, resource;
}
@end
@implementation ViewResource
- (uint64_t)gpuAddress { return address; }
- (MTLResourceID)gpuResourceID { return (MTLResourceID){resource}; }
@end

struct IRDescriptorEntry { uint64_t gpu_va, texture_view_id, metadata; };
/* METADATA_FUNCTION */
struct View { uint64_t gpu_resource_id; };
struct Buffer {
  uint64_t address, resource;
  Buffer *current() { return this; }
  uint64_t gpuAddress() { return address; }
  View view_(int) { return {resource}; }
  uint64_t offsetViewResourceID(int, uint32_t first, uint32_t *remaining) {
    *remaining = first & 255;
    return resource;
  }
};
struct Slice { uint64_t byteOffset, byteLength; uint32_t firstElement; };
struct CPUDescriptor {
  struct { Buffer *buffer; Slice slice; int view; } UAVTexelBuffer;
};
uint64_t AmbreZeroBufferAddress(void *) { return 0x10000; }
IRDescriptorEntry encode(CPUDescriptor cpu) {
  IRDescriptorEntry entry{};
  void *device_ = nullptr;
  switch (0) { case 0: {
    /* TYPED_DESCRIPTOR_BODY */
    break;
  }}
  return entry;
}
int main() {
  @autoreleasepool {
    std::mt19937 rng(0xA4B17);
    for (unsigned i = 0; i < 3000; ++i) {
      Buffer buffer{0x10062eb0000ULL, uint64_t(rng())};
      const uint32_t first = i == 0 ? 7059712 : rng();
      const uint32_t bytes = i == 0 ? 2 : (1 << (i % 5));
      Slice slice{uint64_t(first) * bytes, i == 0 ? 20346ULL : uint64_t(rng()), first};
      auto ambre = encode({{&buffer, slice, 0}});
      ViewResource *appleBuffer = [ViewResource new], *appleTexture = [ViewResource new];
      appleBuffer->address = buffer.address; appleTexture->resource = buffer.resource;
      IRBufferView view{};
      view.buffer = (id<MTLBuffer>)appleBuffer;
      view.bufferOffset = slice.byteOffset;
      view.bufferSize = slice.byteLength;
      view.textureBufferView = (id<MTLTexture>)appleTexture;
      view.textureViewOffsetInElements = first & 255;
      view.typedBuffer = true;
      IRDescriptorTableEntry apple{};
      IRDescriptorTableSetBufferView(&apple, &view);
      if (memcmp(&ambre, &apple, sizeof(apple))) {
        fprintf(stderr, "Typed view mismatch at case %u: Ambre address=0x%llx, Apple address=0x%llx\n",
                i, (unsigned long long)ambre.gpu_va, (unsigned long long)apple.gpuVA);
        return 1;
      }
    }
    puts("3000 typed buffer descriptors match Apple's runtime (byte offsets, texture offsets, bounds metadata).");
  }
}
