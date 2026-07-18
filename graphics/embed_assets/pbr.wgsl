//!include "game://shaders/pbr_math.wgsl"

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
}
struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) world_pos: vec3<f32>,
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
}
@group(0) @binding(0) var<uniform> uniforms: PbrUniforms;

@vertex
fn vs_main(model_in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let world_pos4 = uniforms.model * vec4<f32>(model_in.position, 1.0);
    out.world_pos = world_pos4.xyz;
    out.clip_position = uniforms.vp * world_pos4;
    out.color = model_in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    var N: vec3<f32> = normalize(cross(dpdx(in.world_pos), dpdy(in.world_pos)));
    let V = normalize(uniforms.cam_pos - in.world_pos);
    if (dot(N, V) < 0.0) {
        N = -N;
    }
    
    let albedo = in.color.rgb;
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
    
    return vec4<f32>(corrected, in.color.a);
}
