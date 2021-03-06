﻿/*
The MIT License (MIT)

Copyright (c) 2015 Huw Bowles & Daniel Zimmermann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// this shader renders the sample slice (ray scales) at the last camera position.
// this replaces the advection procedure, the core of which worked for 2D scales but
// extending the sample slice was difficult.

// the geometry is a grid with a vert at every texel of the scale texture, and with an
// extra ring of verts around the outside which form the extension. the inner verts
// are placed at where the sample slice was, based on the previous camera transform
// which is passed into the shader. on the other hand, the outer ring is rendered
// at the edges of the transformed camera - this will extend the sample slice as required.
// the scale value used for the extension interpolates from the scale at the border
// of the sample slice, to the ideal scale, based on the length of the extension (similar
// to how it is done for 1D scales extension in AdvectedScales.cs).

Shader "Custom/RenderScales2D" {
	Properties {
	}

	CGINCLUDE
	
	#include "UnityCG.cginc"
	
	uniform float2 _HalfFov;
	
	uniform float3 _PrevCamPos;
	uniform float3 _PrevCamForward;
	uniform float3 _PrevCamUp;
	uniform float3 _PrevCamRight;
	
	// these really aren't necessary, since this info is in the view matrix,
	// but i pass it in manually to stop the Scene view camera going nuts
	uniform float3 _CamPos;
	uniform float3 _CamForward;
	uniform float3 _CamUp;
	uniform float3 _CamRight;
	
	uniform sampler2D _PrevScalesTex;
	uniform float _ScalesTexSideDim = 32.0;
	
	uniform float _ScaleReturnAlpha = 0.1;
   	uniform float _CannonicalScale = 5.0;
	
	uniform float _ForwardPinShift = 0.0;
	
	uniform float _ClearScalesToValue = -1.0;
	
	struct v2fd
	{
		float4 pos  : SV_POSITION;
		float angleFromCenter : TEXCOORD0;
		float3 posWorld : TEXCOORD1;
	};
	
	v2fd vert( appdata_img v )
	{
		v2fd o;

	    float3 d;
	    d.z = 1.0;
	    d.xy = (v.texcoord*2.0 - 1.0) * tan(_HalfFov) * d.z;
	    d = normalize(d);
		o.angleFromCenter = acos( d.z );
	    
	    float scale = tex2Dlod( _PrevScalesTex, float4( v.texcoord, 0.0, 0.0 ) ).x;

		if( _ClearScalesToValue > -1.0 )
			scale = _ClearScalesToValue;
		
	    // compute vertex position	    
	    // boundary verts form the extension
	    float3 pos_slice_world = _PrevCamPos.xyz + scale * (d.x*_PrevCamRight + d.y*_PrevCamUp + d.z*_PrevCamForward);
	    
	    // forward pinning slides samples back towards camera origin. compensate for this to keep slice (approx) stationary
	    pos_slice_world -= _ForwardPinShift * normalize(_CamPos - pos_slice_world) * scale / tex2Dlod( _PrevScalesTex, float4( 0.5, 0.5, 0.0, 0.0 ) ).x;
	    
	    bool extensionVert = min( v.texcoord.x, v.texcoord.y ) < 0.001 || max( v.texcoord.x, v.texcoord.y ) > 0.999;
	    if( !extensionVert )
	    {
			o.pos = mul( UNITY_MATRIX_VP, float4(pos_slice_world, 1.) );
			o.posWorld = pos_slice_world;
	    }
	    else
	    {
		    float3 d_cam = d.x * _CamRight + d.y * _CamUp + d.z * _CamForward;
	    	o.posWorld = _CamPos + scale * d_cam;
	    	scale = lerp( scale, _CannonicalScale, min(1., _ScaleReturnAlpha * length(o.posWorld - pos_slice_world)) );
	    	o.posWorld = _CamPos + scale * d_cam;
	    	o.pos = mul( UNITY_MATRIX_VP, float4(o.posWorld, 1.) );
	    }
		
		return o;
	}
	
	float4 frag(v2fd i) : SV_Target 
	{
		// max: the fixed z line at the highest point of the circle. this allows strafing after rotating without aliasing
		float maxScale = _CannonicalScale / cos( i.angleFromCenter );
		// min: 90% of the fixed z line
		float minScale = 0.9*_CannonicalScale * cos(length(_HalfFov)) / cos( i.angleFromCenter );
		
		return (float4) clamp( length( i.posWorld - _CamPos ), minScale, maxScale );
	}
	
	ENDCG 
	
Subshader {
 Pass {
	  ZTest Always Cull Back ZWrite On

      CGPROGRAM
	  #pragma target 3.0   
      #pragma vertex vert
      #pragma fragment frag
      ENDCG
  }
}

Fallback off
	
} // shader
