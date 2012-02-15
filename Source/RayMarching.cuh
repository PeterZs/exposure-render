/*
	Copyright (c) 2011, T. Kroes <t.kroes@tudelft.nl>
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	- Neither the name of the TU Delft nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
#pragma once

#include "Geometry.cuh"
#include "CudaUtilities.h"

#define KRNL_SINGLE_SCATTERING_BLOCK_W		16
#define KRNL_SINGLE_SCATTERING_BLOCK_H		8
#define KRNL_SINGLE_SCATTERING_BLOCK_SIZE	KRNL_SINGLE_SCATTERING_BLOCK_W * KRNL_SINGLE_SCATTERING_BLOCK_H

DEV inline void SampleVolume(CRay R, CRNG& RNG, RaySample& RS)
{
	const int TID = threadIdx.y * blockDim.x + threadIdx.x;

	__shared__ float MinT[KRNL_SINGLE_SCATTERING_BLOCK_SIZE];
	__shared__ float MaxT[KRNL_SINGLE_SCATTERING_BLOCK_SIZE];

	const Intersection Int = IntersectBox(R, ToVec3f(gVolume.m_MinAABB), ToVec3f(gVolume.m_MaxAABB));

	if (!Int.Valid)
		return;

	MinT[TID] = max(Int.NearT, R.m_MinT);
	MaxT[TID] = min(Int.FarT, R.m_MaxT);

	const float S	= -log(RNG.Get1()) / gVolume.m_DensityScale;
	float Sum		= 0.0f;
	float SigmaT	= 0.0f;

	Vec3f Ps;

	MinT[TID] += RNG.Get1() * gVolume.m_StepSize;

	while (Sum < S)
	{
		Ps = R.m_O + MinT[TID] * R.m_D;

		if (MinT[TID] >= MaxT[TID])
			return;
		
		SigmaT	= gVolume.m_DensityScale * GetOpacity(Ps);

		Sum			+= SigmaT * gVolume.m_StepSize;
		MinT[TID]	+= gVolume.m_StepSize;
	}

	RS.SetValid(MinT[TID], Ps, NormalizedGradient(Ps), -R.m_D, ColorXYZf());
}

DEV inline bool FreePathRM(CRay R, CRNG& RNG)
{
	const int TID = threadIdx.y * blockDim.x + threadIdx.x;

	__shared__ float MinT[KRNL_SINGLE_SCATTERING_BLOCK_SIZE];
	__shared__ float MaxT[KRNL_SINGLE_SCATTERING_BLOCK_SIZE];
	__shared__ Vec3f Ps[KRNL_SINGLE_SCATTERING_BLOCK_SIZE];

	const Intersection Int = IntersectBox(R, ToVec3f(gVolume.m_MinAABB), ToVec3f(gVolume.m_MaxAABB));
	
	if (!Int.Valid)
		return false;

	MinT[TID] = max(Int.NearT, R.m_MinT);
	MaxT[TID] = min(Int.FarT, R.m_MaxT);

	const float S	= -log(RNG.Get1()) / gVolume.m_DensityScale;
	float Sum		= 0.0f;
	float SigmaT	= 0.0f;

	MinT[TID] += RNG.Get1() * gVolume.m_StepSizeShadow;

	while (Sum < S)
	{
		Ps[TID] = R.m_O + MinT[TID] * R.m_D;

		if (MinT[TID] > MaxT[TID])
			return false;
		
		SigmaT	= gVolume.m_DensityScale * GetOpacity(Ps[TID]);

		Sum			+= SigmaT * gVolume.m_StepSizeShadow;
		MinT[TID]	+= gVolume.m_StepSizeShadow;
	}

	return true;
}