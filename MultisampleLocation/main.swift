//
//  main.swift
//  MultisampleLocation
//
//  Created by Litherum on 7/28/16.
//  Copyright © 2016 Litherum. All rights reserved.
//

import Foundation
import Metal

let device = MTLCreateSystemDefaultDevice()!
var maximumSampleCount = -1
for sampleCount in 0 ..< 100 {
    if device.supportsTextureSampleCount(sampleCount) {
        maximumSampleCount = sampleCount
    }
}
assert(maximumSampleCount > 1)

let multisampleTextureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(.R32Float, width: 1, height: 1, mipmapped: false)
multisampleTextureDescriptor.textureType = .Type2DMultisample
multisampleTextureDescriptor.sampleCount = maximumSampleCount
multisampleTextureDescriptor.storageMode = .Private
multisampleTextureDescriptor.usage = .RenderTarget
let multisampleTexture = device.newTextureWithDescriptor(multisampleTextureDescriptor)

let resolveTextureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(multisampleTexture.pixelFormat, width: multisampleTexture.width, height: multisampleTexture.height, mipmapped: multisampleTexture.mipmapLevelCount != 1)
multisampleTextureDescriptor.usage = .RenderTarget
let resolveTexture = device.newTextureWithDescriptor(resolveTextureDescriptor)

let vertexBufferData : [Float] = [
    0, 0,
    0, 1,
    1, 1,
    1, 1,
    1, 0,
    0, 0
]
let vertexBuffer = device.newBufferWithBytes(vertexBufferData, length: vertexBufferData.count * sizeofValue(vertexBufferData[0]), options: .StorageModeManaged)

let library = device.newDefaultLibrary()!
let vertexShader = library.newFunctionWithName("vertexShader")!
let fragmentShader = library.newFunctionWithName("fragmentShader")!

let vertexDescriptor = MTLVertexDescriptor()
vertexDescriptor.layouts[0].stride = sizeof(Float) * 2
vertexDescriptor.attributes[0].format = .Float2
vertexDescriptor.attributes[0].offset = 0
vertexDescriptor.attributes[0].bufferIndex = 0

let colorAttachmentDescriptor = MTLRenderPipelineColorAttachmentDescriptor()
colorAttachmentDescriptor.pixelFormat = multisampleTexture.pixelFormat

let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.vertexFunction = vertexShader
pipelineDescriptor.fragmentFunction = fragmentShader
pipelineDescriptor.vertexDescriptor = vertexDescriptor
pipelineDescriptor.sampleCount = maximumSampleCount
pipelineDescriptor.colorAttachments[0] = colorAttachmentDescriptor
var pipelineState: MTLRenderPipelineState!
do {
    pipelineState = try device.newRenderPipelineStateWithDescriptor(pipelineDescriptor)
} catch {
    fatalError()
}

let renderPassDescriptor = MTLRenderPassDescriptor()
renderPassDescriptor.colorAttachments[0].texture = multisampleTexture
renderPassDescriptor.colorAttachments[0].resolveTexture = resolveTexture
renderPassDescriptor.colorAttachments[0].loadAction = .Clear
renderPassDescriptor.colorAttachments[0].storeAction = .MultisampleResolve

let commandQueue = device.newCommandQueue()

let commandBuffer = commandQueue.commandBuffer()
let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
renderEncoder.setRenderPipelineState(pipelineState)
renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, atIndex: 0)
renderEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
renderEncoder.endEncoding()

let blitEncoder = commandBuffer.blitCommandEncoder()
blitEncoder.synchronizeResource(resolveTexture)
blitEncoder.endEncoding()

var complete = false
let condition = NSCondition()
commandBuffer.addCompletedHandler { commandBuffer in
    var data = [Float](count: 1, repeatedValue: 0)
    resolveTexture.getBytes(&data, bytesPerRow: sizeofValue(data[0]), fromRegion: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
    print("\(data)")
    condition.lock()
    complete = true
    condition.signal()
    condition.unlock()
}

commandBuffer.commit()

condition.lock()
while !complete {
    condition.wait()
}
condition.unlock()
