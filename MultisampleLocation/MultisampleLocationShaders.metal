//
//  MultisampleLocationShaders.metal
//  MultisampleLocation
//
//  Created by Litherum on 7/28/16.
//  Copyright © 2016 Litherum. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[ attribute(0) ]];
};

struct VertexInOut
{
    float4 position [[ position ]];
};

vertex VertexInOut vertexShader(VertexIn vertexIn [[ stage_in ]])
{
    VertexInOut outVertex;
    
    outVertex.position = float4(vertexIn.position, 0, 1);
    
    return outVertex;
};

fragment float fragmentShader(VertexInOut inFrag [[ stage_in ]])
{
    return 1;
};

