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

let textureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(.R32Uint, width: 1, height: 1, mipmapped: false)
//textureDescriptor.textureType = .Type2DMultisample
//textureDescriptor.sampleCount = maximumSampleCount
//textureDescriptor.storageMode = .Private
textureDescriptor.usage = .RenderTarget
let texture = device.newTextureWithDescriptor(textureDescriptor)

let vertexBufferData : [Float] = [
    -1, -1,
    -1, 1,
    1, 1,
    1, 1,
    1, -1,
    -1, -1
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
colorAttachmentDescriptor.pixelFormat = texture.pixelFormat

let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.vertexFunction = vertexShader
pipelineDescriptor.fragmentFunction = fragmentShader
pipelineDescriptor.vertexDescriptor = vertexDescriptor
//pipelineDescriptor.sampleCount = maximumSampleCount
pipelineDescriptor.colorAttachments[0] = colorAttachmentDescriptor
var pipelineState: MTLRenderPipelineState!
do {
    pipelineState = try device.newRenderPipelineStateWithDescriptor(pipelineDescriptor)
} catch {
    fatalError()
}

let renderPassDescriptor = MTLRenderPassDescriptor()
renderPassDescriptor.colorAttachments[0].texture = texture
renderPassDescriptor.colorAttachments[0].loadAction = .Clear
renderPassDescriptor.colorAttachments[0].storeAction = .Store

let commandQueue = device.newCommandQueue()

let commandBuffer = commandQueue.commandBuffer()
let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
renderEncoder.setRenderPipelineState(pipelineState)
renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, atIndex: 0)
renderEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
renderEncoder.endEncoding()

let blitEncoder = commandBuffer.blitCommandEncoder()
blitEncoder.synchronizeResource(texture)
blitEncoder.endEncoding()

var complete = false
let condition = NSCondition()
commandBuffer.addCompletedHandler { commandBuffer in
    var data = [UInt32](count: 1, repeatedValue: 0)
    texture.getBytes(&data, bytesPerRow: sizeof(UInt32), fromRegion: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
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
