#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#define IR_PRIVATE_IMPLEMENTATION
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>
#include <array>
#include <cstdio>
#include <random>

@interface DrawRecorder : NSObject {
@public
  IRRuntimeDrawParams arguments;
  uint16_t irIndexType;
  uint64_t offset, count, instances, firstInstance;
  int64_t firstVertex;
}
@end
@implementation DrawRecorder
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {
  if (index == kIRArgumentBufferDrawArgumentsBindPoint) {
    NSCAssert(length == sizeof(arguments), @"Unexpected runtime arguments");
    memcpy(&arguments, bytes, length);
  } else if (index == kIRArgumentBufferUniformsBindPoint) {
    memcpy(&irIndexType, bytes, sizeof(irIndexType));
  }
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitive indexCount:(NSUInteger)n
                   indexType:(MTLIndexType)type indexBuffer:(id<MTLBuffer>)buffer
           indexBufferOffset:(NSUInteger)bytes instanceCount:(NSUInteger)i
                  baseVertex:(NSInteger)v baseInstance:(NSUInteger)b {
  offset = bytes; count = n; instances = i; firstVertex = v; firstInstance = b;
}
@end

using UINT = uint32_t;
using INT = int32_t;
using WMTPrimitiveType = MTLPrimitiveType;
constexpr auto WMTIndexTypeUInt32 = MTLIndexTypeUInt32;
constexpr auto WMTRenderCommandDrawIndexed = 1;
enum class DrawCallStatus { Ordinary, Invalid };
struct wmtcmd_render_draw_indexed {
  int type;
  MTLPrimitiveType primitive_type;
  MTLIndexType index_type;
  uint32_t index_count, instance_count, base_instance;
  int32_t base_vertex;
  void *index_buffer;
  uint64_t index_buffer_offset;
};
struct Allocator {
  wmtcmd_render_draw_indexed command{};
  template<typename T> T &EncodeRenderCommand() { return command; }
};
struct Pipeline { bool IsConvertedPipelineState = true; };
struct AmbreDraw {
  uint64_t index_offset = 0;
  MTLIndexType index_type = MTLIndexTypeUInt16;
  void *index_buffer = nullptr;
  int topology_ = 0;
  Pipeline pipeline;
  Pipeline *pso_graphics_ = &pipeline;
  Allocator allocator;
  Allocator *allocator_ = &allocator;
  std::array<uint32_t, 5> arguments{};
  uint16_t irIndexType = 0;
  DrawCallStatus PreDraw() { return DrawCallStatus::Ordinary; }
  bool to_metal_primitive_type(int, WMTPrimitiveType &type, uint32_t &cp) {
    type = MTLPrimitiveTypeTriangle; cp = 0; return true;
  }
  void EncodeConvertedDrawParams(const void *bytes, size_t size, uint16_t type, WMTPrimitiveType) {
    NSCAssert(size == sizeof(arguments), @"Unexpected Ambre arguments");
    memcpy(arguments.data(), bytes, size); irIndexType = type;
  }
  /* DRAW_INDEXED_METHOD */
};

int main() {
  @autoreleasepool {
    std::mt19937 rng(0xA4B12);
    for (unsigned i = 0; i < 3000; ++i) {
      AmbreDraw ambre;
      ambre.index_type = i % 2 ? MTLIndexTypeUInt32 : MTLIndexTypeUInt16;
      ambre.index_offset = i == 0 ? 14134772 : uint64_t(rng()) * 4;
      const UINT start = i == 0 ? 0 : rng();
      const UINT count = i == 0 ? 1242 : rng(), instances = rng(), instance = rng();
      const INT vertex = int32_t(rng());
      const uint64_t offset = ambre.index_offset + uint64_t(start) * (i % 2 ? 4 : 2);
      DrawRecorder *apple = [DrawRecorder new];
      IRRuntimeDrawIndexedPrimitives((id<MTLRenderCommandEncoder>)apple, MTLPrimitiveTypeTriangle,
          count, ambre.index_type, nil, offset, instances, vertex, instance);
      ambre.DrawIndexedInstanced(count, instances, start, vertex, instance);
      const auto &cmd = ambre.allocator.command;
      if (memcmp(ambre.arguments.data(), &apple->arguments, sizeof(apple->arguments)) ||
          ambre.irIndexType != apple->irIndexType || cmd.index_buffer_offset != apple->offset ||
          cmd.index_count != apple->count || cmd.instance_count != apple->instances ||
          cmd.base_vertex != apple->firstVertex || cmd.base_instance != apple->firstInstance) {
        fprintf(stderr, "Indexed draw mismatch at case %u: Ambre start=%u, Apple start=%u\n",
            i, ambre.arguments[2], apple->arguments.drawIndexed.startIndexLocation);
        return 1;
      }
      ambre.pipeline.IsConvertedPipelineState = false;
      ambre.DrawIndexedInstanced(count, instances, start, vertex, instance);
      if (cmd.index_buffer_offset != offset) return 2;
    }
    puts("3000 indexed draws match Apple's runtime (16/32-bit indices, suballocations, base vertex/instance).");
  }
}
