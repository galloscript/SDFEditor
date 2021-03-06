// Copyright (c) 2022 David Gallardo and SDFEditor Project

#define ATLAS_SIZE (ivec3(1024, 1024, 256))
#define ATLAS_SLOTS (ATLAS_SIZE / 8)

struct stroke_t
{
    vec4 posb;      // position.xyz, blend.a
    vec4 quat;      // rotation
    vec4 param0;    // size.xyz, radius.x, round.w
    vec4 param1;    // unused
    ivec4 id;       // shape.x, flags.y
};

layout(std430, binding = 0) readonly buffer strokes_buffer
{
    stroke_t strokes[];
};

layout(std430, binding = 1) buffer slot_list_buffer
{
    uint slot_list[];
};

layout(std430, binding = 2) buffer slot_count_buffer
{
    uint slot_count;
    uint padding[2];
};

layout(location = 20) uniform uint uStrokesCount;
layout(location = 21) uniform uint uMaxSlotsCount;
layout(location = 22) uniform vec4 uVoxelSide;    // LutVoxelSide.x, InvLutVoxelSide.y, AtlasVoxelSide.z InvAtlasVoxelSide.w
layout(location = 23) uniform vec4 uVolumeExtent;   // LutSize.x, InvLutSize.y, AtlasXYSize.z, AtlasDepth.y

layout(location = 30) uniform sampler3D uSdfLutTexture;
layout(location = 31) uniform sampler3D uSdfAtlasTexture;

// Debug
layout(location = 40) uniform ivec4 uVoxelPreview;

// - Voxel space conversion --------------------

uint GetIndexFromCellCoord(ivec3 coord, ivec3 size)
{
    return uint(coord.z * size.x * size.y + coord.y * size.x + coord.x);
}

ivec3 GetCellCoordFromIndex(uint idx, ivec3 size)
{
    uvec3 result = uvec3(0);
    uint a = (size.x * size.y);
    result.z = idx / a;
    uint b = idx - a * result.z;
    result.y = b / size.x;
    result.x = b % size.x;
    return ivec3(result);
}

// - Store coord as index conversion
uint CoordToIndex(ivec3 coord) 
{
    return coord.x | (coord.y << 8) | (coord.z << 16);
}

ivec3 IndexToCoord(uint idx) 
{
    return ivec3(int(idx), int(idx >> 8), int(idx >> 16)) & 0xff;
}

uint NormCoordToIndex(vec3 coord)
{
    return CoordToIndex(ivec3((coord * 255.0f) + 0.5f));
}

vec3 IndexToNormCoord(uint idx)
{
    return vec3(IndexToCoord(idx)) / 255.0f;
}

ivec3 WorldToLutCoord(vec3 pos)
{
    return ivec3(((pos.xyz /*xzy*/ * uVoxelSide.y) + (0.5 * uVolumeExtent.x)));
}

vec3 WorldToLutUVW(vec3 pos)
{
    return ((pos.xyz /*xzy*/ * uVoxelSide.y) + (0.5 * uVolumeExtent.x)) * uVolumeExtent.y;
}

vec3 LutCoordToWorld(ivec3 coord)
{
    return ((vec3(coord.xyz /*xzy*/) + 0.5) - (0.5 * uVolumeExtent.x)) * uVoxelSide.x;
}

// - MATHS -------------------------------
vec3 quatMultVec3(vec4 q, vec3 v)
{
    vec3 t = cross(q.xyz, cross(q.xyz, v) + q.w * v);
    return v + t + t;
}

// - SMOOTH OPERATIONS --------------------------
// https://www.shadertoy.com/view/lt3BW2
float opSmoothUnion(float d1, float d2, float k)
{
    float h = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - h * h * 0.25 / k;
    //float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    //return mix( d2, d1, h ) - k*h*(1.0-h);
}

float opSmoothSubtraction(float d1, float d2, float k)
{
    float h = max(k - abs(-d1 - d2), 0.0);
    return max(-d1, d2) + h * h * 0.25 / k;
    //float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    //return mix( d2, -d1, h ) + k*h*(1.0-h);
}

float opSmoothIntersection(float d1, float d2, float k)
{
    float h = max(k - abs(d1 - d2), 0.0);
    return max(d1, d2) + h * h * 0.25 / k;
    //float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    //return mix( d2, d1, h ) + k*h*(1.0-h);
}

// - SDF Primitives ---------------------
float sdEllipsoid(vec3 p, vec3 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

float sdRoundBox(vec3 p, vec3 b, float r)
{
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float sdTorus(vec3 p, vec2 t)
{
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdVerticalCapsule(vec3 p, float h, float r)
{
    p.y -= clamp(p.y, 0.0, h);
    return length(p) - r;
}

// - STROKE EVALUATION --------------
float evalStroke(vec3 p, in stroke_t stroke)
{
    float shape = 1000000.0;

    if ((stroke.id.y & 0x4) == 0x4)
    {
        p.x = abs(p.x);
    }

    if ((stroke.id.y & 0x8) == 0x8)
    {
        p.y = abs(p.y);
    }
    //p.y = abs(p.y);
    // TODO: mirror goes here
    vec3 position = p - stroke.posb.xyz;

    position = quatMultVec3(stroke.quat, position);

    if (stroke.id.x == 0)
    {
        shape = sdEllipsoid(position, stroke.param0.xyz);
    }
    else if (stroke.id.x == 1)
    {
        float round = clamp(stroke.param0.w, 0.0, 1.0);
        float smaller = min(min(stroke.param0.x, stroke.param0.y), stroke.param0.z);
        round = mix(0.0, smaller, round);
        shape = sdRoundBox(position, stroke.param0.xyz - round, round);
    }
    else if (stroke.id.x == 2)
    {
        shape = sdTorus(position, stroke.param0.xy);
    }
    else if (stroke.id.x == 3)
    {
        vec2 params = max(stroke.param0.xy, vec2(0.0, 0.0));
        shape = sdVerticalCapsule(position - vec3(0.0, -params.y + params.x, 0.0), params.y * 2.0 - params.x * 2.0, params.x);
    }

    return shape;
}

//Distance to scene at point
float distToScene(vec3 p)
{
    float d = 100000.0;

    for (uint i = 0; i < uStrokesCount; i++)
    {
        float shape = evalStroke(p, strokes[i]);

        float clampedBlend = max(0.0001, strokes[i].posb.w);

        // SMOOTH OPERATIONS

        if ((strokes[i].id.y & 3) == 0)
        {
            d = opSmoothUnion(shape, d, clampedBlend);
        }
        else if ((strokes[i].id.y & 1) == 1)
        {
            d = opSmoothSubtraction(shape + clampedBlend * 0.4, d, clampedBlend);
        }
        else if ((strokes[i].id.y & 2) == 2)
        {
            d = opSmoothIntersection(shape, d, clampedBlend);
        }
    }

    return d;
}

float distToSceneLut(vec3 p)
{
    // convert world p to lut coords
    // sample lut texture
    // convert distance to -1, 1
    // convert dist from normalized voxels to worlda

    vec3 lutUVW = WorldToLutUVW(p);
    float dist = texture(uSdfLutTexture, lutUVW).a;
    dist = (dist) * 2.0 - 1.0f;
    dist = dist * uVolumeExtent.x * uVoxelSide.x;

    return dist;
}

float sampleAtlasDist(vec3 uvw)
{
    float dist = texture(uSdfAtlasTexture, uvw).r;
    dist = dist * 2.0 - 1.0f;
    dist = dist * uVoxelSide.x;

    return dist;
}

float fetchAtlasDist(ivec3 coord)
{
    float dist = texelFetch(uSdfAtlasTexture, coord, 0).r;
    dist = dist * 2.0 - 1.0f;
    dist = dist * uVoxelSide.x;

    return dist;
}

float distToSceneAtlas(vec3 pos)
{
    // convert world p to lut coords
    // sample lut texture
    // convert distance to -1, 1
    // convert dist from normalized voxels to worlda

    ivec3 lutCoord = WorldToLutCoord(pos);
    vec3 lutData = texelFetch(uSdfLutTexture, lutCoord, 0).rgb;

    //if (abs(dist) < uVoxelSide.x * 2.0f)
    {
        if (ivec3(lutData.rgb + 0.5) != ivec3(1))
        {
            uint slot = NormCoordToIndex(lutData.rgb);
            vec3 cellCoord = GetCellCoordFromIndex(slot, ATLAS_SLOTS) * 8.0f;
            vec3 offset = fract(pos * uVoxelSide.y) * 8.0f;
            offset = clamp(offset, 0.5, 7.5);

            vec3 atlasUVW = (cellCoord + offset) / vec3(ATLAS_SIZE);
            return sampleAtlasDist(atlasUVW).r;
        }
    }

    return distToSceneLut(pos);
}

//Estimate normal based on distToScene function
const float EPS = 0.001;
vec3 estimateNormal(vec3 p)
{
    float xPl = distToScene(vec3(p.x + EPS, p.y, p.z));
    float xMi = distToScene(vec3(p.x - EPS, p.y, p.z));
    float yPl = distToScene(vec3(p.x, p.y + EPS, p.z));
    float yMi = distToScene(vec3(p.x, p.y - EPS, p.z));
    float zPl = distToScene(vec3(p.x, p.y, p.z + EPS));
    float zMi = distToScene(vec3(p.x, p.y, p.z - EPS));
    float xDiff = xPl - xMi;
    float yDiff = yPl - yMi;
    float zDiff = zPl - zMi;
    return normalize(vec3(xDiff, yDiff, zDiff));
}

vec3 estimateNormalLut(vec3 p)
{
    float offset = uVoxelSide.x * 0.5;
    float xPl = distToSceneLut(vec3(p.x + offset, p.y, p.z));
    float xMi = distToSceneLut(vec3(p.x - offset, p.y, p.z));
    float yPl = distToSceneLut(vec3(p.x, p.y + offset, p.z));
    float yMi = distToSceneLut(vec3(p.x, p.y - offset, p.z));
    float zPl = distToSceneLut(vec3(p.x, p.y, p.z + offset));
    float zMi = distToSceneLut(vec3(p.x, p.y, p.z - offset));
    float xDiff = xPl - xMi;
    float yDiff = yPl - yMi;
    float zDiff = zPl - zMi;
    return normalize(vec3(xDiff, yDiff, zDiff));
}

vec3 estimateNormalAtlas(vec3 p)
{
    float offset = 4.0f * uVoxelSide.x / 8.0f;
    float xPl = distToSceneAtlas(vec3(p.x + offset, p.y, p.z));
    float xMi = distToSceneAtlas(vec3(p.x - offset, p.y, p.z));
    float yPl = distToSceneAtlas(vec3(p.x, p.y + offset, p.z));
    float yMi = distToSceneAtlas(vec3(p.x, p.y - offset, p.z));
    float zPl = distToSceneAtlas(vec3(p.x, p.y, p.z + offset));
    float zMi = distToSceneAtlas(vec3(p.x, p.y, p.z - offset));
    float xDiff = xPl - xMi;
    float yDiff = yPl - yMi;
    float zDiff = zPl - zMi;
    return normalize(vec3(xDiff, yDiff, zDiff));
}

// return the normal of an AABB cube given a position relative to the cube center
vec3 cubenormal(in vec3 v)
{
    vec3 s = sign(v);
    vec3 a = abs(v);

    //vec3 n = (a.z > a.y)
    // ?
    // (a.z > a.x) ? vec3(0.0, 0.0, s.z) : vec3(s.x, 0.0, 0.0)
    // :
    // (a.y > a.x) ? vec3(0.0, s.y, 0.0) : vec3(s.x, 0.0, 0.0);

    vec3 n = mix(
        mix(vec3(0.0, 0.0, s.z), vec3(s.x, 0.0, 0.0), step(a.z, a.x)),
        mix(vec3(0.0, s.y, 0.0), vec3(s.x, 0.0, 0.0), step(a.y, a.x)),
        step(a.z, a.y));

    return n;
}

// Return true if they ray intersects the specified box
// https://gamedev.stackexchange.com/questions/18436/most-efficient-aabb-vs-ray-collision-algorithms
// https://www.shadertoy.com/view/Ns23RK
bool rayboxintersect(in vec3 raypos, in vec3 raydir, in vec3 boxmin, in vec3 boxmax, out vec3 normal, out vec2 distances)
{
    float t1 = (boxmin.x - raypos.x) / raydir.x;
    float t2 = (boxmax.x - raypos.x) / raydir.x;
    float t3 = (boxmin.y - raypos.y) / raydir.y;
    float t4 = (boxmax.y - raypos.y) / raydir.y;
    float t5 = (boxmin.z - raypos.z) / raydir.z;
    float t6 = (boxmax.z - raypos.z) / raydir.z;

    float tmin = max(max(min(t1, t2), min(t3, t4)), min(t5, t6));
    float tmax = min(min(max(t1, t2), max(t3, t4)), max(t5, t6));

    distances = vec2(tmin, tmax);

    if (tmax < 0.0) // box on ray but behind ray origin
    {
        return false;
    }

    if (tmin > tmax) // ray doesn't intersect box
    {
        return false;
    }

    normal = cubenormal(raypos + raydir * tmin - (boxmin + boxmax) / 2.0);
    return true;
}