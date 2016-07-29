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
assert(maximumSampleCount <= 32)

let multisampleTextureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(.R32Float, width: 1, height: 1, mipmapped: false)
multisampleTextureDescriptor.textureType = .Type2DMultisample
multisampleTextureDescriptor.sampleCount = maximumSampleCount
multisampleTextureDescriptor.storageMode = .Private
multisampleTextureDescriptor.usage = .RenderTarget
let multisampleTexture = device.newTextureWithDescriptor(multisampleTextureDescriptor)

let resolveTextureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(multisampleTexture.pixelFormat, width: multisampleTexture.width, height: multisampleTexture.height, mipmapped: multisampleTexture.mipmapLevelCount != 1)
multisampleTextureDescriptor.usage = .RenderTarget
let resolveTexture = device.newTextureWithDescriptor(resolveTextureDescriptor)

let vertexBuffer = device.newBufferWithLength(sizeof(Float) * 2 * 4, options: MTLResourceOptions())

let indexBufferData : [UInt16] = [ 0, 1, 2, 2, 3, 0 ]
let indexBuffer = device.newBufferWithBytes(indexBufferData, length: indexBufferData.count * sizeofValue(indexBufferData[0]), options: MTLResourceOptions())

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

var complete = false
let condition = NSCondition()

var iterationX = 0
var iterationY = 0
let stepsX = 100
let stepsY = 100

var redMask = UInt32(0)
var greenMask = UInt32(0)
var blueMask = UInt32(0)

func draw() {
    var vertexBufferData : [Float] = [
        2 * Float(iterationX) / Float(stepsX) - 1, 2 * Float(iterationY) / Float(stepsY) - 1,
        2 * Float(iterationX) / Float(stepsX) - 1, 2 * Float(iterationY + 1) / Float(stepsY) - 1,
        2 * Float(iterationX + 1) / Float(stepsX) - 1, 2 * Float(iterationY + 1) / Float(stepsY) - 1,
        2 * Float(iterationX + 1) / Float(stepsX) - 1, 2 * Float(iterationY) / Float(stepsY) - 1
    ]
    let vertexBufferContents = UnsafeMutablePointer<Float>(vertexBuffer.contents())
    vertexBufferContents.assignFrom(&vertexBufferData, count: vertexBufferData.count)
    if vertexBuffer.storageMode == .Managed {
        vertexBuffer.didModifyRange(NSMakeRange(0, vertexBuffer.length))
    }

    let commandBuffer = commandQueue.commandBuffer()
    let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, atIndex: 0)
    renderEncoder.drawIndexedPrimitives(.Triangle, indexCount: indexBufferData.count, indexType: .UInt16, indexBuffer: indexBuffer, indexBufferOffset: 0)
    renderEncoder.endEncoding()

    if resolveTexture.storageMode == .Managed {
        let blitEncoder = commandBuffer.blitCommandEncoder()
        blitEncoder.synchronizeResource(resolveTexture)
        blitEncoder.endEncoding()
    }

    commandBuffer.addCompletedHandler { commandBuffer in
        var data = [Float](count: 1, repeatedValue: 0)
        resolveTexture.getBytes(&data, bytesPerRow: sizeofValue(data[0]), fromRegion: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        if data[0] != 0 {
            let coordinateX = (Float(iterationX) + Float(0.5)) / Float(stepsX)
            //let coordinateY = (Float(iterationY) + Float(0.5)) / Float(stepsY)
            let mask = UInt32(data[0] * Float(maximumSampleCount))
            if coordinateX < Float(1) / Float(3) {
                redMask = redMask | mask
            } else if coordinateX < Float(2) / Float(3) {
                greenMask = greenMask | mask
            } else {
                blueMask = blueMask | mask
            }
        }
        iterationX = iterationX + 1
        if iterationX == stepsX {
            iterationX = 0
            iterationY = iterationY + 1
        }
        if iterationY == stepsY {
            condition.lock()
            complete = true
            condition.signal()
            condition.unlock()
        } else {
            draw()
        }
    }

    commandBuffer.commit()
}

draw()

condition.lock()
while !complete {
    condition.wait()
}
condition.unlock()

print("Red Mask: \(redMask)")
print("Green Mask: \(greenMask)")
print("Blue Mask: \(blueMask)")
