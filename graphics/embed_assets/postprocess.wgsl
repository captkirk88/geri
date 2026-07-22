struct SSAOUniforms {
    projection: mat4x4<f32>,
    inv_projection: mat4x4<f32>,
    view: mat4x4<f32>,
    samples: array<vec4<f32>, 64>,
    radius: f32,
    bias: f32,
    power: f32,
    kernel_size: i32,
    screen_size: vec2<f32>,
    noise_scale: vec2<f32>,
};

@group(0) @binding(0) var g_depth: texture_2d<f32>;
@group(0) @binding(1) var g_normal: texture_2d<f32>;
@group(0) @binding(2) var noise_tex: texture_2d<f32>;
@group(0) @binding(3) var g_sampler: sampler;
@group(0) @binding(4) var<uniform> u_ssao: SSAOUniforms;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var out: VertexOutput;
    var positions = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 1.0, -1.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>( 1.0,  1.0)
    );
    var uvs = array<vec2<f32>, 4>(
        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 0.0)
    );
    out.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    out.uv = uvs[vertex_index];
    return out;
}

@fragment
fn fs_ssao(in: VertexOutput) -> @location(0) vec4<f32> {
    let depth = textureSample(g_depth, g_sampler, in.uv).r;
    if (depth >= 1.0) {
        return vec4<f32>(1.0, 1.0, 1.0, 1.0);
    }

    let normal = textureSample(g_normal, g_sampler, in.uv).xyz * 2.0 - 1.0;
    let random_vec = textureSample(noise_tex, g_sampler, in.uv * u_ssao.noise_scale).xyz;

    // Create Tangent-Bitangent-Normal (TBN) matrix
    let tangent = normalize(random_vec - normal * dot(random_vec, normal));
    let bitangent = cross(normal, tangent);
    let tbn = mat3x3<f32>(tangent, bitangent, normal);

    // Reconstruct view position from depth
    let clip_space = vec4<f32>(in.uv * 2.0 - 1.0, depth, 1.0);
    var view_pos = u_ssao.inv_projection * clip_space;
    view_pos = view_pos / view_pos.w;

    var occlusion = 0.0;
    let num_samples = min(u_ssao.kernel_size, 64);

    for (var i = 0; i < num_samples; i = i + 1) {
        let sample_pos = tbn * u_ssao.samples[i].xyz;
        let sample_vec = view_pos.xyz + sample_pos * u_ssao.radius;

        var offset = u_ssao.projection * vec4<f32>(sample_vec, 1.0);
        offset = offset / offset.w;
        let sample_uv = offset.xy * 0.5 + 0.5;

        let sample_depth = textureSample(g_depth, g_sampler, sample_uv).r;
        let range_check = smoothstep(0.0, 1.0, u_ssao.radius / abs(view_pos.z - sample_depth));
        
        if (sample_depth <= offset.z - u_ssao.bias) {
            occlusion += range_check;
        }
    }

    let ssao = 1.0 - (occlusion / f32(num_samples));
    let final_ssao = pow(clamp(ssao, 0.0, 1.0), u_ssao.power);
    return vec4<f32>(vec3<f32>(final_ssao), 1.0);
}

@fragment
fn fs_ssao_blur(in: VertexOutput) -> @location(0) vec4<f32> {
    let texel_size = 1.0 / u_ssao.screen_size;
    var result = 0.0;
    
    for (var x = -2; x <= 2; x = x + 1) {
        for (var y = -2; y <= 2; y = y + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
            result += textureSample(g_depth, g_sampler, in.uv + offset).r;
        }
    }
    
    return vec4<f32>(vec3<f32>(result / 25.0), 1.0);
}

@fragment
fn fs_fxaa(in: VertexOutput) -> @location(0) vec4<f32> {
    let texel_size = 1.0 / u_ssao.screen_size;
    let rgbM = textureSample(g_depth, g_sampler, in.uv).rgb;
    
    let rgbNW = textureSample(g_depth, g_sampler, in.uv + vec2<f32>(-1.0, -1.0) * texel_size).rgb;
    let rgbNE = textureSample(g_depth, g_sampler, in.uv + vec2<f32>( 1.0, -1.0) * texel_size).rgb;
    let rgbSW = textureSample(g_depth, g_sampler, in.uv + vec2<f32>(-1.0,  1.0) * texel_size).rgb;
    let rgbSE = textureSample(g_depth, g_sampler, in.uv + vec2<f32>( 1.0,  1.0) * texel_size).rgb;

    let luma = vec3<f32>(0.299, 0.587, 0.114);
    let lumaM  = dot(rgbM,  luma);
    let lumaNW = dot(rgbNW, luma);
    let lumaNE = dot(rgbNE, luma);
    let lumaSW = dot(rgbSW, luma);
    let lumaSE = dot(rgbSE, luma);

    let lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    let lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    let dir = vec2<f32>(
        -((lumaNW + lumaNE) - (lumaSW + lumaSE)),
        ((lumaNW + lumaSW) - (lumaNE + lumaSE))
    );

    let dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * 0.125), 0.0078125);
    let rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    let dirScaled = min(vec2<f32>(8.0), max(vec2<f32>(-8.0), dir * rcpDirMin)) * texel_size;

    let rgbA = 0.5 * (
        textureSample(g_depth, g_sampler, in.uv + dirScaled * (1.0/3.0 - 0.5)).rgb +
        textureSample(g_depth, g_sampler, in.uv + dirScaled * (2.0/3.0 - 0.5)).rgb
    );
    let rgbB = rgbA * 0.5 + 0.25 * (
        textureSample(g_depth, g_sampler, in.uv + dirScaled * -0.5).rgb +
        textureSample(g_depth, g_sampler, in.uv + dirScaled * 0.5).rgb
    );

    let lumaB = dot(rgbB, luma);
    if (lumaB < lumaMin || lumaB > lumaMax) {
        return vec4<f32>(rgbA, 1.0);
    }
    return vec4<f32>(rgbB, 1.0);
}
