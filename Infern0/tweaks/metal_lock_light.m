//
//  metal_lock_light.m
//  Cyanide
//
//  Experimental lock-screen Metal renderer inspired by Sticker's foil and
//  reflection shaders. This test build renders a fixed bundled image as a
//  source texture, then applies the shader output into a CAMetalLayer.
//

#import "metal_lock_light.h"
#import "remote_objc.h"
#import "../LogTextView.h"
#import "../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>

typedef struct { double x, y, w, h; } MLLRect;
typedef struct { double w, h; } MLLSize;
typedef struct { double red, green, blue, alpha; } MLLClearColor;
typedef struct {
    float lightX;
    float lightY;
    float colorIntensity;
    float reflectIntensity;
    float viewWidth;
    float viewHeight;
    float textureWidth;
    float textureHeight;
    int mode;
    int padding0;
    int padding1;
    int padding2;
} MLLShaderParams;

static uint64_t g_mll_layer = 0;
static uint64_t g_mll_lock_window = 0;
static uint64_t g_mll_device = 0;
static uint64_t g_mll_command_queue = 0;
static uint64_t g_mll_pipeline = 0;
static uint64_t g_mll_source_texture = 0;
static MLLShaderParams g_mll_params = { 0.32f, 0.24f, 0.30f, 0.30f, 390.0f, 844.0f, 1.0f, 1.0f, 2, 0, 0, 0 };

static bool mll_is_kind_of_class_fast(uint64_t obj, uint64_t cls);

static void mll_read_remote_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) {
        snprintf(out, outLen, "nil");
        return;
    }

    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_dlsym_call(R_TIMEOUT, "NSStringFromClass", cls, 0, 0, 0, 0, 0, 0, 0);
    if (!r_read_nsstring(name, out, outLen)) {
        snprintf(out, outLen, "0x%llx", (unsigned long long)obj);
    }
}

static void mll_log_layer_tree(uint64_t layer, int depth, int *budget)
{
    if (!r_is_objc_ptr(layer) || !budget || *budget <= 0 || depth > 8) return;
    (*budget)--;

    char clsName[96];
    char delegateName[96];
    mll_read_remote_class_name(layer, clsName, sizeof(clsName));
    uint64_t delegate = r_msg2_main(layer, "delegate", 0, 0, 0, 0);
    mll_read_remote_class_name(delegate, delegateName, sizeof(delegateName));

    MLLRect bounds = {0, 0, 0, 0};
    (void)r_msg2_main_struct_ret(layer, "bounds",
                                 &bounds, sizeof(bounds),
                                 NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    uint64_t sublayers = r_msg2_main(layer, "sublayers", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(sublayers) ? r_msg2_main(sublayers, "count", 0, 0, 0, 0) : 0;

    log_user("[METAL-LIGHT][WP] layer depth=%d ptr=0x%llx class=%s delegate=%s bounds=(%.0f,%.0f %.0fx%.0f) sublayers=%llu\n",
             depth,
             (unsigned long long)layer,
             clsName,
             delegateName,
             bounds.x, bounds.y, bounds.w, bounds.h,
             (unsigned long long)count);

    for (uint64_t i = 0; i < count && i < 24 && *budget > 0; i++) {
        uint64_t child = r_msg2_main(sublayers, "objectAtIndex:", i, 0, 0, 0);
        mll_log_layer_tree(child, depth + 1, budget);
    }
}

static bool mll_view_is_hidden(uint64_t view)
{
    if (!r_is_objc_ptr(view)) return true;
    return r_msg2_main(view, "isHidden", 0, 0, 0, 0) != 0;
}

static uint64_t mll_find_view_of_class(uint64_t view, uint64_t targetCls, int depth, int *budget)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(targetCls) || !budget || *budget <= 0 || depth > 12) return 0;
    (*budget)--;

    if (depth > 0 && mll_view_is_hidden(view)) return 0;
    if (mll_is_kind_of_class_fast(view, targetCls)) {
        return view;
    }

    uint64_t subviews = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subviews) ? r_msg2_main(subviews, "count", 0, 0, 0, 0) : 0;
    for (uint64_t i = 0; i < count && i < 32; i++) {
        uint64_t child = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        uint64_t found = mll_find_view_of_class(child, targetCls, depth + 1, budget);
        if (r_is_objc_ptr(found)) return found;
    }
    return 0;
}

static uint64_t mll_find_cgimage_in_image_view_subtree(uint64_t view, uint64_t imageViewCls, int depth, int *budget, uint64_t *imageViewOut)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(imageViewCls) || !budget || *budget <= 0 || depth > 8) return 0;
    (*budget)--;

    if (depth > 0 && mll_view_is_hidden(view)) return 0;
    if (mll_is_kind_of_class_fast(view, imageViewCls)) {
        uint64_t image = r_msg2_main(view, "image", 0, 0, 0, 0);
        uint64_t cgImage = r_is_objc_ptr(image) ? r_msg2_main(image, "CGImage", 0, 0, 0, 0) : 0;
        uint64_t cgWidth = cgImage ? r_dlsym_call(R_TIMEOUT, "CGImageGetWidth", cgImage, 0, 0, 0, 0, 0, 0, 0) : 0;
        uint64_t cgHeight = cgImage ? r_dlsym_call(R_TIMEOUT, "CGImageGetHeight", cgImage, 0, 0, 0, 0, 0, 0, 0) : 0;
        if (cgImage && cgWidth > 0 && cgHeight > 0) {
            if (imageViewOut) *imageViewOut = view;
            return cgImage;
        }
    }

    uint64_t subviews = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subviews) ? r_msg2_main(subviews, "count", 0, 0, 0, 0) : 0;
    for (uint64_t i = 0; i < count && i < 32; i++) {
        uint64_t child = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        uint64_t found = mll_find_cgimage_in_image_view_subtree(child, imageViewCls, depth + 1, budget, imageViewOut);
        if (found) return found;
    }
    return 0;
}

static bool mll_is_kind_of_class_fast(uint64_t obj, uint64_t cls)
{
    if (!r_is_objc_ptr(obj) || !r_is_objc_ptr(cls)) return false;

    uint64_t cur = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    for (int depth = 0; r_is_objc_ptr(cur) && depth < 16; depth++) {
        if (cur == cls) return true;
        cur = r_dlsym_call(R_TIMEOUT, "class_getSuperclass", cur, 0, 0, 0, 0, 0, 0, 0);
    }
    return false;
}

static uint64_t mll_find_lock_window(void)
{
    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    uint64_t coverSheetCls = r_class("SBCoverSheetWindow");

    for (uint64_t i = 0; i < count && i < 32; i++) {
        uint64_t w = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (mll_is_kind_of_class_fast(w, coverSheetCls)) return w;
    }
    return 0;
}

static uint64_t mll_find_wallpaper_window(void)
{
    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    uint64_t wallpaperCls = r_class("_SBWallpaperSecureWindow");

    for (uint64_t i = 0; i < count && i < 32; i++) {
        uint64_t w = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (mll_is_kind_of_class_fast(w, wallpaperCls)) return w;
    }
    return 0;
}

static uint64_t mll_nsstring_retained(const char *text)
{
    uint64_t cls = r_class("NSString");
    uint64_t str = r_alloc_str(text);
    if (!r_is_objc_ptr(cls) || !str) {
        if (str) r_free(str);
        return 0;
    }
    uint64_t obj = r_msg2(cls, "stringWithUTF8String:", str, 0, 0, 0);
    r_free(str);
    if (r_is_objc_ptr(obj)) obj = r_msg2(obj, "retain", 0, 0, 0, 0);
    return obj;
}

static float mll_clampf(double value, double minValue, double maxValue)
{
    if (value < minValue) return (float)minValue;
    if (value > maxValue) return (float)maxValue;
    return (float)value;
}

static void mll_set_params(double colorIntensity, double reflectIntensity, double lightX, double lightY, int mode)
{
    g_mll_params.lightX = mll_clampf(lightX, 0.06, 0.94);
    g_mll_params.lightY = mll_clampf(lightY, 0.06, 0.94);
    g_mll_params.colorIntensity = mll_clampf(colorIntensity, 0.0, 1.5);
    g_mll_params.reflectIntensity = mll_clampf(reflectIntensity, 0.0, 1.5);
    if (mode < 0) mode = 0;
    if (mode > 3) mode = 3;
    g_mll_params.mode = mode;
}

static bool mll_prepare_metal_pipeline(void)
{
    uint64_t metalPath = r_alloc_str("/System/Library/Frameworks/Metal.framework/Metal");
    if (metalPath) {
        r_dlsym_call(R_TIMEOUT, "dlopen", metalPath, 2, 0, 0, 0, 0, 0, 0);
        r_free(metalPath);
    }
    uint64_t quartzPath = r_alloc_str("/System/Library/Frameworks/QuartzCore.framework/QuartzCore");
    if (quartzPath) {
        r_dlsym_call(R_TIMEOUT, "dlopen", quartzPath, 2, 0, 0, 0, 0, 0, 0);
        r_free(quartzPath);
    }
    uint64_t metalKitPath = r_alloc_str("/System/Library/Frameworks/MetalKit.framework/MetalKit");
    if (metalKitPath) {
        r_dlsym_call(R_TIMEOUT, "dlopen", metalKitPath, 2, 0, 0, 0, 0, 0, 0);
        r_free(metalKitPath);
    }

    if (!r_is_objc_ptr(g_mll_device)) {
        g_mll_device = r_dlsym_call(R_TIMEOUT, "MTLCreateSystemDefaultDevice", 0, 0, 0, 0, 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(g_mll_device)) {
        log_user("[METAL-LIGHT] MTLCreateSystemDefaultDevice failed.\n");
        return false;
    }

    if (!r_is_objc_ptr(g_mll_command_queue)) {
        g_mll_command_queue = r_msg2(g_mll_device, "newCommandQueue", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(g_mll_command_queue)) {
        log_user("[METAL-LIGHT] newCommandQueue failed.\n");
        return false;
    }

    if (r_is_objc_ptr(g_mll_pipeline)) return true;

    const char *source =
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct Params { float2 light; float colorIntensity; float reflectIntensity; float2 viewSize; float2 textureSize; int mode; int3 padding; };\n"
        "struct VOut { float4 position [[position]]; float2 uv; };\n"
        "float random2(float2 uv) { return fract(sin(dot(uv.xy, float2(12.9898, 78.233))) * 43758.5453); }\n"
        "float noisePattern(float2 uv) { float2 i=floor(uv); float2 f=fract(uv); float a=random2(i); float b=random2(i+float2(1,0)); float c=random2(i+float2(0,1)); float d=random2(i+float2(1,1)); float2 u=smoothstep(0.0,1.0,f); return mix(a,b,u.x)+(c-a)*u.y*(1.0-u.x)+(d-b)*u.x*u.y; }\n"
        "half3 inkPalette(float t) { t=fract(t); float3 a=float3(0.42,0.48,0.58); float3 b=float3(0.46,0.42,0.38); float3 c=float3(1.0,1.0,1.0); float3 d=float3(0.02,0.30,0.62); float3 rgb=a+b*cos(6.2831853*(c*t+d)); rgb=clamp(rgb,float3(0),float3(1)); return half3(half(rgb.r),half(rgb.g),half(rgb.b)); }\n"
        "float brightness(half3 color) { return float(color.r)*0.299+float(color.g)*0.587+float(color.b)*0.114; }\n"
        "float2 aspectFillUV(float2 uv, float2 viewSize, float2 textureSize) { float va=viewSize.x/max(viewSize.y,1.0); float ta=textureSize.x/max(textureSize.y,1.0); if (ta>va) { float visible=va/ta; uv.x=0.5+(uv.x-0.5)*visible; } else { float visible=ta/va; uv.y=0.5+(uv.y-0.5)*visible; } return float2(uv.x,1.0-uv.y); }\n"
        "vertex VOut v_main(uint vid [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; VOut o; o.position=float4(p[vid],0,1); o.uv=(p[vid]+1.0)*0.5; return o; }\n"
        "fragment half4 f_main(VOut in [[stage_in]], texture2d<half, access::sample> source [[texture(0)]], constant Params& p [[buffer(0)]]) {\n"
        "    float2 uv=in.uv; constexpr sampler s(address::clamp_to_edge, filter::linear); half4 base=source.sample(s, aspectFillUV(uv,p.viewSize,p.textureSize));\n"
        "    float2 rel=uv-p.light; float2 offset=(p.light-float2(0.5,0.5))*float2(-150.0,190.0); float2 foilUv=(uv/2.2)+(offset+float2(250.0))*0.00012; float g=random2(uv*1024.0)*0.10; float noise=noisePattern(uv*100.0);\n"
        "    float sweepA=sin((foilUv.x*8.0)+(foilUv.y*5.5)+p.light.y*5.0+g); float sweepB=cos((foilUv.x*3.2)-(foilUv.y*8.8)+p.light.x*4.0);\n"
        "    half3 foil=half3(half(0.86+0.23*sweepA), half(0.90+0.22*sweepB), half(0.96+0.20*sin((foilUv.x+foilUv.y)*7.0+p.light.y*6.0-g)));\n"
        "    float bright=brightness(base.rgb); float foilMask=max(smoothstep(0.2,1.0,bright)*p.colorIntensity,0.30*p.colorIntensity);\n"
        "    if (p.mode==3) { float2 dir=normalize(float2((p.light.x-0.5)*2.0,(p.light.y-0.5)*2.0)+float2(0.001)); float2 normal=float2(-dir.y,dir.x); float axis=dot(rel,dir); float crossAxis=dot(rel,normal); float localRadius=length(rel*float2(0.88,1.10)); float localMask=smoothstep(0.74,0.0,localRadius); float shoulder=smoothstep(1.10,0.15,localRadius); float micro=noisePattern((uv-p.light*0.35)*170.0+p.light*8.0)-0.5; float fine=random2(floor((uv+p.light*0.23)*480.0))-0.5; float lowFreq=noisePattern((uv-p.light*0.50)*22.0+p.light*4.0)-0.5; float rotatePhase=atan2(dir.y,dir.x)*0.15915494; float film=axis*2.15+crossAxis*0.42+localRadius*0.34+lowFreq*0.026+micro*0.014+fine*0.008+rotatePhase; half3 inkA=inkPalette(film); half3 inkB=inkPalette(film+0.16+localRadius*0.10); float grazing=smoothstep(-0.44,0.58,axis+localRadius*0.20); half3 ink=mix(inkA,inkB,half(grazing)); float inkMask=clamp(foilMask*shoulder*(0.10+localMask*0.48+grazing*0.20+(lowFreq+0.5)*0.016),0.0,0.80); half3 color=mix(base.rgb,ink,half(inkMask)); float spotReflect=smoothstep(0.44,0.0,localRadius); float arc=pow(max(0.0,1.0-abs(axis-0.10)*2.8),2.6)*smoothstep(0.78,0.0,abs(crossAxis)); float varnish=clamp(spotReflect*0.28+arc*0.34,0.0,1.0); color=mix(color,half3(1.0),half(clamp(varnish*p.reflectIntensity,0.0,0.38))); return half4(color,base.a); }\n"
        "    if (p.mode==2) { float2 dir=normalize(float2((p.light.x-0.5)*2.0,(p.light.y-0.5)*2.0)+float2(0.001)); float axis=dot(uv-float2(0.5),dir); float crossAxis=dot(uv-float2(0.5),float2(-dir.y,dir.x)); float micro=noisePattern(uv*180.0+p.light*9.0)-0.5; float fine=random2(floor(uv*520.0-p.light*17.0))-0.5; float lowFreq=noisePattern(uv*24.0+p.light*3.0)-0.5; float angle=p.light.x*0.62+p.light.y*0.38; float film=axis*1.35+crossAxis*0.28+lowFreq*0.022+micro*0.018+fine*0.010+angle; half3 inkA=inkPalette(film); half3 inkB=inkPalette(film+0.18); float grazing=smoothstep(-0.72,0.82,axis+angle*0.26); half3 ink=mix(inkA,inkB,half(grazing)); float inkMask=clamp(foilMask*(0.20+grazing*0.34+(lowFreq+0.5)*0.018+(micro+0.5)*0.010),0.0,0.78); half3 color=mix(base.rgb,ink,half(inkMask)); float varnish=pow(max(0.0,1.0-abs(axis-(angle-0.5)*0.65)*1.9),2.2); color=mix(color,half3(1.0),half(clamp(varnish*p.reflectIntensity*0.20,0.0,0.32))); return half4(color,base.a); }\n"
        "    if (p.mode==1) { float2 dir=normalize(float2((p.light.x-0.5)*2.0,(p.light.y-0.5)*2.0)+float2(0.001)); float2 normal=float2(-dir.y,dir.x); float axis=dot(uv-float2(0.5),dir); float crossAxis=dot(uv-float2(0.5),normal); float phase=axis*2.4+p.light.x*2.2-p.light.y*1.7; half3 linearFoil=half3(half(0.80+0.28*sin(phase)),half(0.84+0.24*sin(phase+2.1)),half(0.96+0.20*sin(phase+4.2))); float linearMask=clamp(foilMask*(0.12+(0.5+0.5*sin(phase))*0.28),0.0,0.72); half3 color=mix(base.rgb,linearFoil,half(linearMask)); float sheenCenter=(p.light.x-0.5)*1.15+(p.light.y-0.5)*0.45; float broad=smoothstep(0.58,0.0,abs(axis-sheenCenter)); float streak=pow(max(0.0,1.0-abs(axis-sheenCenter)*7.5),4.2); float ribbon=pow(max(0.0,1.0-abs(crossAxis+sheenCenter*0.35)*3.0),2.2); float sparkle=random2(floor((uv+p.light*0.17)*170.0))>0.982 ? smoothstep(0.26,0.0,abs(axis-sheenCenter))*smoothstep(0.58,0.0,abs(crossAxis)) : 0.0; float sheen=clamp(broad*0.15+streak*0.28+ribbon*0.08+sparkle*0.55,0.0,1.0); color=mix(color,half3(1.0),half(clamp(sheen*p.reflectIntensity,0.0,0.50))); return half4(color,base.a); }\n"
        "    float radial=smoothstep(0.72,0.0,length(rel*float2(0.82,1.18))); float wave=0.5+0.5*(sweepA*0.45+sweepB*0.35+radial*0.20); half3 color=mix(base.rgb,foil,half(clamp(foilMask*(0.12+wave*0.16+radial*0.10+noise*0.030),0.0,0.70))); float reflection=smoothstep(0.42,0.0,length(rel*float2(0.92,1.12))); color=mix(color,half3(1.0),half(clamp(reflection*p.reflectIntensity,0.0,0.65))); return half4(color,base.a);\n"
        "}\n";

    uint64_t sourceString = mll_nsstring_retained(source);
    if (!r_is_objc_ptr(sourceString)) {
        log_user("[METAL-LIGHT] shader source allocation failed.\n");
        return false;
    }

    uint64_t library = r_msg2(g_mll_device, "newLibraryWithSource:options:error:", sourceString, 0, 0, 0);
    r_msg2(sourceString, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(library)) {
        log_user("[METAL-LIGHT] shader library compile failed.\n");
        return false;
    }

    uint64_t vName = mll_nsstring_retained("v_main");
    uint64_t fName = mll_nsstring_retained("f_main");
    uint64_t vFunc = r_msg2(library, "newFunctionWithName:", vName, 0, 0, 0);
    uint64_t fFunc = r_msg2(library, "newFunctionWithName:", fName, 0, 0, 0);
    if (r_is_objc_ptr(vName)) r_msg2(vName, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(fName)) r_msg2(fName, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(vFunc) || !r_is_objc_ptr(fFunc)) {
        log_user("[METAL-LIGHT] shader function lookup failed.\n");
        return false;
    }

    uint64_t desc = r_msg2(r_class("MTLRenderPipelineDescriptor"), "new", 0, 0, 0, 0);
    if (!r_is_objc_ptr(desc)) {
        log_user("[METAL-LIGHT] pipeline descriptor failed.\n");
        return false;
    }
    r_msg2(desc, "setVertexFunction:", vFunc, 0, 0, 0);
    r_msg2(desc, "setFragmentFunction:", fFunc, 0, 0, 0);
    uint64_t attachments = r_msg2(desc, "colorAttachments", 0, 0, 0, 0);
    uint64_t att0 = r_msg2(attachments, "objectAtIndexedSubscript:", 0, 0, 0, 0);
    if (r_is_objc_ptr(att0)) {
        r_msg2(att0, "setPixelFormat:", 80, 0, 0, 0); // MTLPixelFormatBGRA8Unorm
    }
    g_mll_pipeline = r_msg2(g_mll_device, "newRenderPipelineStateWithDescriptor:error:", desc, 0, 0, 0);
    if (!r_is_objc_ptr(g_mll_pipeline)) {
        log_user("[METAL-LIGHT] pipeline creation failed.\n");
        return false;
    }

    return true;
}

static bool mll_prepare_source_texture(const char *imagePath)
{
    if (r_is_objc_ptr(g_mll_source_texture)) return true;
    if (!imagePath || imagePath[0] == '\0') {
        log_user("[METAL-LIGHT] source image path missing.\n");
        return false;
    }
    if (!r_is_objc_ptr(g_mll_device)) {
        log_user("[METAL-LIGHT] source texture needs MTLDevice first.\n");
        return false;
    }

    uint64_t path = mll_nsstring_retained(imagePath);
    uint64_t UIImageCls = r_class("UIImage");
    uint64_t image = (r_is_objc_ptr(UIImageCls) && r_is_objc_ptr(path))
        ? r_msg2_main(UIImageCls, "imageWithContentsOfFile:", path, 0, 0, 0)
        : 0;
    if (r_is_objc_ptr(path)) r_msg2(path, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(image)) {
        log_user("[METAL-LIGHT] UIImage decode failed: %s\n", imagePath);
        return false;
    }

    uint64_t cgImage = r_msg2_main(image, "CGImage", 0, 0, 0, 0);
    if (!cgImage) {
        log_user("[METAL-LIGHT] source CGImage missing.\n");
        return false;
    }

    uint64_t loaderCls = r_class("MTKTextureLoader");
    uint64_t loaderAlloc = r_is_objc_ptr(loaderCls) ? r_msg2(loaderCls, "alloc", 0, 0, 0, 0) : 0;
    uint64_t loader = r_is_objc_ptr(loaderAlloc) ? r_msg2(loaderAlloc, "initWithDevice:", g_mll_device, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(loader)) {
        log_user("[METAL-LIGHT] MTKTextureLoader init failed.\n");
        return false;
    }

    g_mll_source_texture = r_msg2(loader, "newTextureWithCGImage:options:error:", cgImage, 0, 0, 0);
    r_msg2(loader, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(g_mll_source_texture)) {
        log_user("[METAL-LIGHT] source texture creation failed.\n");
        return false;
    }

    uint64_t width = r_msg2(g_mll_source_texture, "width", 0, 0, 0, 0);
    uint64_t height = r_msg2(g_mll_source_texture, "height", 0, 0, 0, 0);
    g_mll_params.textureWidth = width > 0 ? (float)width : 1.0f;
    g_mll_params.textureHeight = height > 0 ? (float)height : 1.0f;
    log_user("[METAL-LIGHT] source texture ready %.0fx%.0f.\n",
             g_mll_params.textureWidth, g_mll_params.textureHeight);
    return true;
}

static bool mll_prepare_wallpaper_snapshot_texture(uint64_t wallpaperWindow)
{
    if (r_is_objc_ptr(g_mll_source_texture)) return true;
    if (!r_is_objc_ptr(wallpaperWindow)) return false;
    if (!r_is_objc_ptr(g_mll_device)) return false;

    uint64_t snapshotCls = r_class("PBUISnapshotReplicaView");
    if (!r_is_objc_ptr(snapshotCls)) {
        log_user("[METAL-LIGHT] PBUISnapshotReplicaView class not found.\n");
        return false;
    }

    uint64_t snapshotView = 0;
    for (int attempt = 0; attempt < 10 && !r_is_objc_ptr(snapshotView); attempt++) {
        int budget = 220;
        snapshotView = mll_find_view_of_class(wallpaperWindow, snapshotCls, 0, &budget);
        if (!r_is_objc_ptr(snapshotView)) {
            usleep(120000);
        }
    }
    if (!r_is_objc_ptr(snapshotView)) {
        log_user("[METAL-LIGHT] wallpaper snapshot view not found.\n");
        return false;
    }
    log_user("[METAL-LIGHT] wallpaper snapshot view found: 0x%llx.\n",
             (unsigned long long)snapshotView);

    uint64_t imageViewCls = r_class("UIImageView");
    uint64_t imageView = 0;
    int imageBudget = 80;
    uint64_t cgImage = mll_find_cgimage_in_image_view_subtree(snapshotView, imageViewCls, 0, &imageBudget, &imageView);
    uint64_t cgWidth = cgImage ? r_dlsym_call(R_TIMEOUT, "CGImageGetWidth", cgImage, 0, 0, 0, 0, 0, 0, 0) : 0;
    uint64_t cgHeight = cgImage ? r_dlsym_call(R_TIMEOUT, "CGImageGetHeight", cgImage, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!cgImage || cgWidth == 0 || cgHeight == 0) {
        log_user("[METAL-LIGHT] wallpaper UIImageView CGImage not found.\n");
        return false;
    }
    log_user("[METAL-LIGHT] wallpaper image view found: 0x%llx CGImage=%llux%llu.\n",
             (unsigned long long)imageView,
             (unsigned long long)cgWidth,
             (unsigned long long)cgHeight);

    uint64_t loaderCls = r_class("MTKTextureLoader");
    uint64_t loaderAlloc = r_is_objc_ptr(loaderCls) ? r_msg2(loaderCls, "alloc", 0, 0, 0, 0) : 0;
    uint64_t loader = r_is_objc_ptr(loaderAlloc) ? r_msg2(loaderAlloc, "initWithDevice:", g_mll_device, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(loader)) {
        log_user("[METAL-LIGHT] wallpaper texture loader init failed.\n");
        return false;
    }

    g_mll_source_texture = r_msg2(loader, "newTextureWithCGImage:options:error:", cgImage, 0, 0, 0);
    r_msg2(loader, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(g_mll_source_texture)) {
        log_user("[METAL-LIGHT] wallpaper snapshot texture creation failed.\n");
        return false;
    }

    uint64_t width = r_msg2(g_mll_source_texture, "width", 0, 0, 0, 0);
    uint64_t height = r_msg2(g_mll_source_texture, "height", 0, 0, 0, 0);
    g_mll_params.textureWidth = width > 0 ? (float)width : 1.0f;
    g_mll_params.textureHeight = height > 0 ? (float)height : 1.0f;
    log_user("[METAL-LIGHT] wallpaper snapshot texture ready %.0fx%.0f.\n",
             g_mll_params.textureWidth, g_mll_params.textureHeight);
    return true;
}

static bool mll_attach_layer_to_lock_window(uint64_t layer, uint64_t window)
{
    if (!r_is_objc_ptr(layer) || !r_is_objc_ptr(window)) return false;

    MLLRect bounds = {0};
    r_msg2_main_struct_ret(window, "bounds", &bounds, sizeof(bounds),
                           NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    if (bounds.w <= 0 || bounds.h <= 0) {
        bounds.w = 390;
        bounds.h = 844;
    }
    g_mll_params.viewWidth = (float)bounds.w;
    g_mll_params.viewHeight = (float)bounds.h;
    r_msg2_main_raw(layer, "setFrame:",
                    &bounds, sizeof(bounds), NULL, 0, NULL, 0, NULL, 0);

    MLLSize drawableSize = { bounds.w * 2.0, bounds.h * 2.0 };
    r_msg2_main_raw(layer, "setDrawableSize:",
                    &drawableSize, sizeof(drawableSize), NULL, 0, NULL, 0, NULL, 0);

    uint64_t winLayer = r_msg2_main(window, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(winLayer)) return false;

    uint64_t curSuper = r_msg2_main(layer, "superlayer", 0, 0, 0, 0);
    if (curSuper != winLayer) {
        if (r_is_objc_ptr(curSuper)) r_msg2_main(layer, "removeFromSuperlayer", 0, 0, 0, 0);
        r_msg2_main(winLayer, "insertSublayer:atIndex:", layer, 1, 0, 0);
    }
    g_mll_lock_window = window;
    return true;
}

static bool mll_render_once(void)
{
    if (!r_is_objc_ptr(g_mll_layer) ||
        !r_is_objc_ptr(g_mll_command_queue) ||
        !r_is_objc_ptr(g_mll_pipeline) ||
        !r_is_objc_ptr(g_mll_source_texture)) {
        return false;
    }

    uint64_t drawable = r_msg2_main(g_mll_layer, "nextDrawable", 0, 0, 0, 0);
    if (!r_is_objc_ptr(drawable)) {
        log_user("[METAL-LIGHT] nextDrawable failed.\n");
        return false;
    }
    uint64_t texture = r_msg2(drawable, "texture", 0, 0, 0, 0);
    if (!r_is_objc_ptr(texture)) {
        log_user("[METAL-LIGHT] drawable texture missing.\n");
        return false;
    }

    uint64_t passDesc = r_msg2(r_class("MTLRenderPassDescriptor"), "renderPassDescriptor", 0, 0, 0, 0);
    uint64_t colorAttachments = r_msg2(passDesc, "colorAttachments", 0, 0, 0, 0);
    uint64_t color0 = r_msg2(colorAttachments, "objectAtIndexedSubscript:", 0, 0, 0, 0);
    if (!r_is_objc_ptr(color0)) return false;

    MLLClearColor clear = {0, 0, 0, 0};
    r_msg2(color0, "setTexture:", texture, 0, 0, 0);
    r_msg2(color0, "setLoadAction:", 2, 0, 0, 0);  // MTLLoadActionClear
    r_msg2(color0, "setStoreAction:", 1, 0, 0, 0); // MTLStoreActionStore
    r_msg2_main_raw(color0, "setClearColor:",
                    &clear, sizeof(clear), NULL, 0, NULL, 0, NULL, 0);

    uint64_t cmd = r_msg2(g_mll_command_queue, "commandBuffer", 0, 0, 0, 0);
    uint64_t encoder = r_msg2(cmd, "renderCommandEncoderWithDescriptor:", passDesc, 0, 0, 0);
    if (!r_is_objc_ptr(cmd) || !r_is_objc_ptr(encoder)) {
        log_user("[METAL-LIGHT] command encoder failed.\n");
        return false;
    }

    r_msg2(encoder, "setRenderPipelineState:", g_mll_pipeline, 0, 0, 0);
    r_msg2(encoder, "setFragmentTexture:atIndex:", g_mll_source_texture, 0, 0, 0);
    uint64_t paramsRemote = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(g_mll_params), 0, 0, 0, 0, 0, 0, 0);
    if (!paramsRemote || !remote_write(paramsRemote, &g_mll_params, sizeof(g_mll_params))) {
        if (paramsRemote) r_free(paramsRemote);
        log_user("[METAL-LIGHT] shader params upload failed.\n");
        return false;
    }
    r_msg2(encoder, "setFragmentBytes:length:atIndex:", paramsRemote, sizeof(g_mll_params), 0, 0);
    r_free(paramsRemote);
    r_msg2(encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, 3, 0); // triangle
    r_msg2(encoder, "endEncoding", 0, 0, 0, 0);
    r_msg2(cmd, "presentDrawable:", drawable, 0, 0, 0);
    r_msg2(cmd, "commit", 0, 0, 0, 0);
    return true;
}

bool metal_lock_light_apply_in_session(double colorIntensity, double reflectIntensity,
                                       int mode, const char *imagePath)
{
    uint32_t oldSettle = r_settle_us(0);
    bool ok = false;

    mll_set_params(colorIntensity, reflectIntensity, 0.32, 0.24, mode);
    if (!mll_prepare_metal_pipeline()) goto out;

    uint64_t wallpaperWindow = mll_find_wallpaper_window();
    if (r_is_objc_ptr(wallpaperWindow)) {
        log_user("[METAL-LIGHT] wallpaper window found; trying live snapshot source.\n");
    }
    if (!mll_prepare_wallpaper_snapshot_texture(wallpaperWindow)) {
        log_user("[METAL-LIGHT] wallpaper snapshot unavailable; falling back to bundled test image.\n");
        if (!mll_prepare_source_texture(imagePath)) goto out;
    }

    if (!r_is_objc_ptr(g_mll_layer)) {
        g_mll_layer = r_msg2_main(r_class("CAMetalLayer"), "layer", 0, 0, 0, 0);
        if (!r_is_objc_ptr(g_mll_layer)) {
            log_user("[METAL-LIGHT] CAMetalLayer creation failed.\n");
            goto out;
        }
        r_msg2_main(g_mll_layer, "setDevice:", g_mll_device, 0, 0, 0);
        r_msg2_main(g_mll_layer, "setPixelFormat:", 80, 0, 0, 0);
        r_msg2_main(g_mll_layer, "setFramebufferOnly:", 1, 0, 0, 0);
        r_msg2_main(g_mll_layer, "setOpaque:", 1, 0, 0, 0);
    }

    uint64_t lockWindow = r_is_objc_ptr(g_mll_lock_window)
        ? g_mll_lock_window
        : (r_is_objc_ptr(wallpaperWindow) ? wallpaperWindow : mll_find_lock_window());
    if (!r_is_objc_ptr(lockWindow)) {
        log_user("[METAL-LIGHT] lock window not found.\n");
        goto out;
    }
    if (!mll_attach_layer_to_lock_window(g_mll_layer, lockWindow)) {
        log_user("[METAL-LIGHT] attach failed.\n");
        goto out;
    }
    if (!mll_render_once()) goto out;

    log_user("[METAL-LIGHT] Metal lock light rendered once.\n");
    ok = true;

out:
    r_settle_us(oldSettle);
    return ok;
}

bool metal_lock_light_update_in_session(double colorIntensity, double reflectIntensity,
                                        double lightX, double lightY, int mode)
{
    uint32_t oldSettle = r_settle_us(0);
    bool ok = false;

    mll_set_params(colorIntensity, reflectIntensity, lightX, lightY, mode);
    if (!r_is_objc_ptr(g_mll_layer) || !r_is_objc_ptr(g_mll_lock_window)) {
        goto out;
    }
    if (!mll_prepare_metal_pipeline()) goto out;
    ok = mll_render_once();

out:
    r_settle_us(oldSettle);
    return ok;
}

bool metal_lock_light_retry_wallpaper_source_in_session(void)
{
    uint32_t oldSettle = r_settle_us(0);
    bool ok = false;

    if (!r_is_objc_ptr(g_mll_layer)) {
        log_user("[METAL-LIGHT] retry skipped: Metal layer is not active.\n");
        goto out;
    }
    if (r_is_objc_ptr(g_mll_source_texture)) {
        r_msg2(g_mll_source_texture, "release", 0, 0, 0, 0);
        g_mll_source_texture = 0;
    }

    uint64_t wallpaperWindow = mll_find_wallpaper_window();
    if (!r_is_objc_ptr(wallpaperWindow)) {
        log_user("[METAL-LIGHT] retry failed: wallpaper window not found.\n");
        goto out;
    }
    if (!mll_prepare_wallpaper_snapshot_texture(wallpaperWindow)) {
        log_user("[METAL-LIGHT] retry failed: wallpaper snapshot source unavailable.\n");
        goto out;
    }
    ok = mll_render_once();
    log_user("[METAL-LIGHT] retry wallpaper source result=%d.\n", ok ? 1 : 0);

out:
    r_settle_us(oldSettle);
    return ok;
}

bool metal_lock_light_probe_wallpaper_layers_in_session(void)
{
    uint32_t oldSettle = r_settle_us(0);
    bool ok = false;

    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    uint64_t windows = r_is_objc_ptr(app) ? r_msg2_main(app, "windows", 0, 0, 0, 0) : 0;
    uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(windows)) {
        log_user("[METAL-LIGHT][WP] probe failed: UIApplication windows unavailable.\n");
        goto out;
    }

    log_user("[METAL-LIGHT][WP] probe begin windows=%llu. Looking for lock-screen wallpaper/PosterBoard layers.\n",
             (unsigned long long)count);
    for (uint64_t i = 0; i < count && i < 24; i++) {
        uint64_t window = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(window)) continue;

        char windowName[96];
        mll_read_remote_class_name(window, windowName, sizeof(windowName));
        MLLRect bounds = {0, 0, 0, 0};
        (void)r_msg2_main_struct_ret(window, "bounds",
                                     &bounds, sizeof(bounds),
                                     NULL, 0, NULL, 0, NULL, 0, NULL, 0);
        uint64_t layer = r_msg2_main(window, "layer", 0, 0, 0, 0);
        log_user("[METAL-LIGHT][WP] window[%llu] ptr=0x%llx class=%s bounds=(%.0f,%.0f %.0fx%.0f) layer=0x%llx\n",
                 (unsigned long long)i,
                 (unsigned long long)window,
                 windowName,
                 bounds.x, bounds.y, bounds.w, bounds.h,
                 (unsigned long long)layer);

        int budget = 80;
        mll_log_layer_tree(layer, 0, &budget);
    }

    log_user("[METAL-LIGHT][WP] probe end.\n");
    ok = true;

out:
    r_settle_us(oldSettle);
    return ok;
}

bool metal_lock_light_stop_in_session(void)
{
    if (r_is_objc_ptr(g_mll_layer)) {
        r_msg2_main(g_mll_layer, "removeFromSuperlayer", 0, 0, 0, 0);
    }
    metal_lock_light_forget_remote_state();
    log_user("[METAL-LIGHT] removed.\n");
    return true;
}

void metal_lock_light_forget_remote_state(void)
{
    if (r_is_objc_ptr(g_mll_source_texture)) {
        r_msg2(g_mll_source_texture, "release", 0, 0, 0, 0);
    }
    g_mll_layer = 0;
    g_mll_lock_window = 0;
    g_mll_device = 0;
    g_mll_command_queue = 0;
    g_mll_pipeline = 0;
    g_mll_source_texture = 0;
    g_mll_params = (MLLShaderParams){ 0.32f, 0.24f, 0.30f, 0.30f, 390.0f, 844.0f, 1.0f, 1.0f, 2, 0, 0, 0 };
}
