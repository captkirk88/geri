//!include "game://shaders/pbr_math.wgsl"

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) normal: vec3<f32>,
    @location(4) joints: vec4<f32>,
    @location(5) weights: vec4<f32>,
}
struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) world_pos: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) normal: vec3<f32>,
}

struct Light {
    position: vec3<f32>,
    intensity: f32,
    color: vec3<f32>,
    radius: f32,
}

struct PbrUniforms {
    vp: mat4x4<f32>,
    model: mat4x4<f32>,
    cam_pos: vec3<f32>,
    num_lights: i32,
    lights: array<Light, 4>,
    roughness: f32,
    metallic: f32,
    ao: f32,
    num_joints: i32,
    joint_matrices: array<mat4x4<f32>, 64>,
}
@group(0) @binding(0) var<uniform> uniforms: PbrUniforms;
@group(0) @binding(1) var t_diffuse: texture_2d<f32>;
@group(0) @binding(2) var s_diffuse: sampler;

@vertex
fn vs_main(model_in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    var model_pos = vec4<f32>(model_in.position, 1.0);
    var model_normal = vec4<f32>(model_in.normal, 0.0);

    if (uniforms.num_joints > 0) {
        let j0 = i32(model_in.joints.x);
        let j1 = i32(model_in.joints.y);
        let j2 = i32(model_in.joints.z);
        let j3 = i32(model_in.joints.w);

        let skin_matrix =
            model_in.weights.x * uniforms.joint_matrices[j0] +
            model_in.weights.y * uniforms.joint_matrices[j1] +
            model_in.weights.z * uniforms.joint_matrices[j2] +
            model_in.weights.w * uniforms.joint_matrices[j3];

        model_pos = skin_matrix * model_pos;
        model_normal = skin_matrix * model_normal;
    }

    let world_pos4 = uniforms.model * model_pos;
    out.world_pos = world_pos4.xyz;
    out.clip_position = uniforms.vp * world_pos4;
    out.color = model_in.color;
    out.uv = model_in.uv;

    let world_normal4 = uniforms.model * model_normal;
    out.normal = normalize(world_normal4.xyz);

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    var N: vec3<f32> = normalize(in.normal);
    let V = normalize(uniforms.cam_pos - in.world_pos);
    if (dot(N, V) < 0.0) {
        N = -N;
    }

    // Sample the diffuse texture if UVs are non-zero, otherwise use vertex color
    var albedo = in.color.rgb;
    var alpha = in.color.a;
    if (in.uv.x != 0.0 || in.uv.y != 0.0) {
        let tex_color = textureSample(t_diffuse, s_diffuse, in.uv);
        albedo = tex_color.rgb * in.color.rgb;
        alpha = tex_color.a * in.color.a;
    }

    if (alpha < 0.1) {
        discard;
    }

    let metallic = uniforms.metallic;
    let roughness = max(uniforms.roughness, 0.05); // prevent divide by zero
    let ao = uniforms.ao;

    var F0 = vec3<f32>(0.04);
    F0 = mix(F0, albedo, metallic);

    var Lo = vec3<f32>(0.0);

    for (var i: i32 = 0; i < uniforms.num_lights; i = i + 1) {
        let light = uniforms.lights[i];
        let L = normalize(light.position - in.world_pos);
        let H = normalize(V + L);

        let dist = distance(light.position, in.world_pos);
        var attenuation = 1.0;
        if (light.radius > 0.0) {
            attenuation = clamp(1.0 - (dist / light.radius), 0.0, 1.0);
            attenuation = attenuation * attenuation;
        }
        let radiance = light.color * light.intensity * attenuation;

        // Cook-Torrance BRDF
        let NDF = DistributionGGX(N, H, roughness);
        let G = GeometrySmith(N, V, L, roughness);
        let F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        let kS = F;
        var kD = vec3<f32>(1.0) - kS;
        kD = kD * (1.0 - metallic);

        let numerator = NDF * G * F;
        let denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        let specular = numerator / denominator;

        let NdotL = max(dot(N, L), 0.0);
        Lo = Lo + (kD * albedo / PI + specular) * radiance * NdotL;
    }

    let ambient = vec3<f32>(0.03) * albedo * ao;
    let color = ambient + Lo;

    // HDR tonemapping & gamma correction
    let mapped = color / (color + vec3<f32>(1.0));
    let corrected = pow(mapped, vec3<f32>(1.0 / 2.2));

    return vec4<f32>(corrected, alpha);
}
