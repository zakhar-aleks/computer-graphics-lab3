#import <Cocoa/Cocoa.h>
#include <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3native.h>
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"
#include <cmath>
#include <algorithm>
#include <vector>

struct RGBf { float r, g, b; };
struct HSV { float h, s, v; };
struct CMYK { float c, m, y, k; };
struct Lab { float l, a, b; };
enum class Shape { NONE, SQUARE, TRIANGLE, CIRCLE };

CMYK RgbToCmyk(RGBf rgb) 
{
    float k = 1.0f - std::max({rgb.r, rgb.g, rgb.b});
    if (k == 1.0f) return {0.0f, 0.0f, 0.0f, 1.0f};
    return {
        (1.0f - rgb.r - k) / (1.0f - k),
        (1.0f - rgb.g - k) / (1.0f - k),
        (1.0f - rgb.b - k) / (1.0f - k),
        k
    };
}

HSV RgbToHsv(RGBf rgb) 
{
    float cmax = std::max({rgb.r, rgb.g, rgb.b});
    float cmin = std::min({rgb.r, rgb.g, rgb.b});
    float delta = cmax - cmin;
    HSV hsv = {0.0f, 0.0f, cmax};

    if (delta > 0.0f) {
        hsv.s = delta / cmax;

        if (cmax == rgb.r) hsv.h = 60.0f * fmod(((rgb.g - rgb.b) / delta), 6.0f);
        else if (cmax == rgb.g) hsv.h = 60.0f * (((rgb.b - rgb.r) / delta) + 2.0f);
        else hsv.h = 60.0f * (((rgb.r - rgb.g) / delta) + 4.0f);
        if (hsv.h < 0.0f) hsv.h += 360.0f;
    }

    return hsv;
}

RGBf CmykToRgb(CMYK cmyk) 
{
    return {
        (1.0f - cmyk.c) * (1.0f - cmyk.k),
        (1.0f - cmyk.m) * (1.0f - cmyk.k),
        (1.0f - cmyk.y) * (1.0f - cmyk.k)
    };
}

RGBf HsvToRgb(HSV hsv) 
{
    float c = hsv.v * hsv.s;
    float x = c * (1.0f - std::abs(fmod(hsv.h / 60.0f, 2.0f) - 1.0f));
    float m = hsv.v - c;

    RGBf rgb = {0.0f, 0.0f, 0.0f};

    if (hsv.h >= 0.0f && hsv.h < 60.0f) rgb = {c, x, 0.0f};
    else if (hsv.h >= 60.0f && hsv.h < 120.0f) rgb = {x, c, 0.0f};
    else if (hsv.h >= 120.0f && hsv.h < 180.0f) rgb = {0.0f, c, x};
    else if (hsv.h >= 180.0f && hsv.h < 240.0f) rgb = {0.0f, x, c};
    else if (hsv.h >= 240.0f && hsv.h < 300.0f) rgb = {x, 0.0f, c};
    else if (hsv.h >= 300.0f && hsv.h < 360.0f) rgb = {c, 0.0f, x};

    return {rgb.r + m, rgb.g + m, rgb.b + m};
}

float RgbToXyzLinear(float c) {
    return (c > 0.04045f) ? powf((c + 0.055f) / 1.055f, 2.4f) : (c / 12.92f);
}

float XyzToLabF(float t) {
    return (t > 0.008856f) ? cbrtf(t) : (7.787f * t) + (16.0f / 116.0f);
}

Lab RgbToLab(RGBf rgb) {
    float r = RgbToXyzLinear(rgb.r);
    float g = RgbToXyzLinear(rgb.g);
    float b = RgbToXyzLinear(rgb.b);

    float x = (r * 0.4124564f + g * 0.3575761f + b * 0.1804375f) / 0.95047f;
    float y = (r * 0.2126729f + g * 0.7151522f + b * 0.0721750f) / 1.00000f;
    float z = (r * 0.0193339f + g * 0.1191920f + b * 0.9503041f) / 1.08883f;

    float fx = XyzToLabF(x);
    float fy = XyzToLabF(y);
    float fz = XyzToLabF(z);

    return {
        std::clamp((116.0f * fy) - 16.0f, 0.0f, 100.0f),
        std::clamp(500.0f * (fx - fy), -128.0f, 127.0f),
        std::clamp(200.0f * (fy - fz), -128.0f, 127.0f)
    };
}

float XyzToLabF_Inv(float t) {
    float t3 = t * t * t;
    return (t3 > 0.008856f) ? t3 : (t - 16.0f / 116.0f) / 7.787f;
}

float RgbFromXyzLinear(float c) {
    return (c > 0.0031308f) ? (1.055f * powf(c, 1.0f / 2.4f) - 0.055f) : (12.92f * c);
}

RGBf LabToRgb(Lab lab) {
    float fy = (lab.l + 16.0f) / 116.0f;
    float fx = lab.a / 500.0f + fy;
    float fz = fy - lab.b / 200.0f;

    float x = XyzToLabF_Inv(fx) * 0.95047f;
    float y = XyzToLabF_Inv(fy) * 1.00000f;
    float z = XyzToLabF_Inv(fz) * 1.08883f;

    float rl = x *  3.2404542f - y * 1.5371385f - z * 0.4985314f;
    float gl = -x * 0.9692660f + y * 1.8760108f + z * 0.0415560f;
    float bl = x *  0.0556434f - y * 0.2040259f + z * 1.0572252f;

    return {
        std::clamp(RgbFromXyzLinear(rl), 0.0f, 1.0f),
        std::clamp(RgbFromXyzLinear(gl), 0.0f, 1.0f),
        std::clamp(RgbFromXyzLinear(bl), 0.0f, 1.0f)
    };
}

struct VertexData 
{
    float position[2];
    float color[4];
};

const char* shaderSrc = R"(
#include <metal_stdlib>
using namespace metal;
struct VertexIn {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};
struct VertexOut {
    float4 position [[position]];
    float4 color;
};
vertex VertexOut vertexMain(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.color = in.color;
    return out;
}
fragment float4 fragmentMain(VertexOut in [[stage_in]]) {
    return in.color;
}
)";

int main() 
{
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    GLFWwindow* window = glfwCreateWindow(1280, 720, "Color Picker", nullptr, nullptr);

    MTL::Device* device = MTL::CreateSystemDefaultDevice();
    CA::MetalLayer* metalLayer = CA::MetalLayer::layer();
    metalLayer->setDevice(device);
    metalLayer->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    
    NSWindow* cocoaWindow = glfwGetCocoaWindow(window);
    
    [cocoaWindow.contentView setWantsLayer:YES];
    [cocoaWindow.contentView setLayer:(__bridge CALayer*)metalLayer];
    
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    MTL::CommandQueue* commandQueue = device->newCommandQueue();

    NS::String* nsShaderSrc = NS::String::string(shaderSrc, NS::UTF8StringEncoding);
    NS::Error* error = nullptr;
    MTL::Library* library = device->newLibrary(nsShaderSrc, nullptr, &error);
    MTL::Function* vertexFn = library->newFunction(NS::String::string("vertexMain", NS::UTF8StringEncoding));
    MTL::Function* fragFn = library->newFunction(NS::String::string("fragmentMain", NS::UTF8StringEncoding));

    MTL::RenderPipelineDescriptor* pDesc = MTL::RenderPipelineDescriptor::alloc()->init();
    pDesc->setVertexFunction(vertexFn);
    pDesc->setFragmentFunction(fragFn);
    pDesc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatBGRA8Unorm);

    MTL::VertexDescriptor* vDesc = MTL::VertexDescriptor::alloc()->init();
    vDesc->attributes()->object(0)->setFormat(MTL::VertexFormatFloat2);
    vDesc->attributes()->object(0)->setOffset(0);
    vDesc->attributes()->object(0)->setBufferIndex(0);
    vDesc->attributes()->object(1)->setFormat(MTL::VertexFormatFloat4);
    vDesc->attributes()->object(1)->setOffset(sizeof(float) * 2);
    vDesc->attributes()->object(1)->setBufferIndex(0);
    vDesc->layouts()->object(0)->setStride(sizeof(VertexData));
    vDesc->layouts()->object(0)->setStepRate(1);
    vDesc->layouts()->object(0)->setStepFunction(MTL::VertexStepFunctionPerVertex);
    pDesc->setVertexDescriptor(vDesc);

    MTL::RenderPipelineState* pipelineState = device->newRenderPipelineState(pDesc, &error);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui_ImplGlfw_InitForOther(window, true);
    ImGui_ImplMetal_Init((__bridge id<MTLDevice>)device);

    Shape currentShape = Shape::NONE;
    RGBf rgb1 = {1.0f, 0.0f, 0.0f};
    CMYK cmyk = RgbToCmyk(rgb1);
    HSV hsv = RgbToHsv(rgb1);
    Lab lab = RgbToLab(rgb1);

    RGBf rgb2 = {0.0f, 0.0f, 1.0f};
    CMYK cmyk2 = RgbToCmyk(rgb2);
    HSV hsv2 = RgbToHsv(rgb2);
    Lab lab2 = RgbToLab(rgb2);
    
    bool useGradient = false;
    int gradDir = 0;

    std::vector<VertexData> vertices;
    MTL::Buffer* vertexBuffer = nullptr;

    auto EmitCopyableData = [&](const char* label, const char* format, auto... args) {
        char valBuf[128];
        snprintf(valBuf, sizeof(valBuf), format, args...);
        char displayBuf[256];
        snprintf(displayBuf, sizeof(displayBuf), "%s: %s", label, valBuf);
        
        if (ImGui::Selectable(displayBuf)) {
            ImGui::SetClipboardText(valBuf);
        }

        if (ImGui::IsItemHovered()) ImGui::SetTooltip("Copy %s", label);
    };

    while (!glfwWindowShouldClose(window)) 
    {
        glfwPollEvents();

        int fbWidth, fbHeight;
        glfwGetFramebufferSize(window, &fbWidth, &fbHeight);
        metalLayer->setDrawableSize(CGSizeMake(fbWidth, fbHeight));

        NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
        
        CA::MetalDrawable* drawable = metalLayer->nextDrawable();
        MTL::RenderPassDescriptor* passDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = passDescriptor->colorAttachments()->object(0);
        colorAttachment->setTexture(drawable->texture());
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor::Make(0.1, 0.1, 0.1, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);

        ImGui_ImplMetal_NewFrame((__bridge MTLRenderPassDescriptor*)passDescriptor);
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        ImGui::Begin("Lab Controls", NULL, ImGuiWindowFlags_AlwaysAutoResize);

        if (ImGui::Button("Square")) currentShape = Shape::SQUARE;
        ImGui::SameLine();
        if (ImGui::Button("Triangle")) currentShape = Shape::TRIANGLE;
        ImGui::SameLine();
        if (ImGui::Button("Circle")) currentShape = Shape::CIRCLE;
        ImGui::SameLine();
        if (ImGui::Button("Clear")) currentShape = Shape::NONE;

        ImGui::Separator();
        ImGui::Text("Main Color");

        if (ImGui::ColorEdit3("##Main Color Picker", &rgb1.r)) {
            cmyk = RgbToCmyk(rgb1);
            hsv = RgbToHsv(rgb1);
            lab = RgbToLab(rgb1);
        }

        if (ImGui::SliderFloat3("RGB##1", &rgb1.r, 0.0f, 1.0f)) {
            cmyk = RgbToCmyk(rgb1);
            hsv = RgbToHsv(rgb1);
            lab = RgbToLab(rgb1);
        }

        if (ImGui::SliderFloat4("CMYK##1", &cmyk.c, 0.0f, 1.0f)) {
            rgb1 = CmykToRgb(cmyk);
            hsv = RgbToHsv(rgb1);
            lab = RgbToLab(rgb1);
        }

        if (ImGui::SliderFloat3("HSV##1", &hsv.h, 0.0f, 360.0f)) {
            hsv.s = std::clamp(hsv.s, 0.0f, 1.0f);
            hsv.v = std::clamp(hsv.v, 0.0f, 1.0f);
            rgb1 = HsvToRgb(hsv);
            cmyk = RgbToCmyk(rgb1);
            lab = RgbToLab(rgb1);
        }

        if (ImGui::SliderFloat3("CIE LAB##1", &lab.l, -128.0f, 127.0f)) {
            lab.l = std::clamp(lab.l, 0.0f, 100.0f);
            rgb1 = LabToRgb(lab);
            cmyk = RgbToCmyk(rgb1);
            hsv = RgbToHsv(rgb1);
        }

        ImGui::TextDisabled("Click to copy main color:");
        EmitCopyableData("RGB", "rgb(%d, %d, %d)", (int)std::round(rgb1.r * 255.0f), (int)std::round(rgb1.g * 255.0f), (int)std::round(rgb1.b * 255.0f));
        EmitCopyableData("CMYK", "cmyk(%.0f%%, %.0f%%, %.0f%%, %.0f%%)", cmyk.c * 100.0f, cmyk.m * 100.0f, cmyk.y * 100.0f, cmyk.k * 100.0f);
        EmitCopyableData("HSV", "hsv(%.0f, %.0f%%, %.0f%%)", hsv.h, hsv.s * 100.0f, hsv.v * 100.0f);
        EmitCopyableData("CIE LAB", "lab(%.0f%% %.0f %.0f)", lab.l, lab.a, lab.b);
        ImGui::Separator();

        ImGui::Checkbox("Enable Gradient", &useGradient);

        if (useGradient) {
            ImGui::RadioButton("Horizontal", &gradDir, 0);
            ImGui::SameLine();
            ImGui::RadioButton("Vertical", &gradDir, 1);
            
            ImGui::Text("Gradient Color");
            
            if (ImGui::ColorEdit3("##Gradient Color Picker", &rgb2.r)) {
                cmyk2 = RgbToCmyk(rgb2);
                hsv2 = RgbToHsv(rgb2);
                lab2 = RgbToLab(rgb2);
            }
            
            if (ImGui::SliderFloat3("RGB##2", &rgb2.r, 0.0f, 1.0f)) {
                cmyk2 = RgbToCmyk(rgb2);
                hsv2 = RgbToHsv(rgb2);
                lab2 = RgbToLab(rgb2);
            }

            if (ImGui::SliderFloat4("CMYK##2", &cmyk2.c, 0.0f, 1.0f)) {
                rgb2 = CmykToRgb(cmyk2);
                hsv2 = RgbToHsv(rgb2);
                lab2 = RgbToLab(rgb2);
            }

            if (ImGui::SliderFloat3("HSV##2", &hsv2.h, 0.0f, 360.0f)) {
                hsv2.s = std::clamp(hsv2.s, 0.0f, 1.0f);
                hsv2.v = std::clamp(hsv2.v, 0.0f, 1.0f);
                rgb2 = HsvToRgb(hsv2);
                cmyk2 = RgbToCmyk(rgb2);
                lab2 = RgbToLab(rgb2);
            }

            if (ImGui::SliderFloat3("CIE LAB##2", &lab2.l, -128.0f, 127.0f)) {
                lab2.l = std::clamp(lab2.l, 0.0f, 100.0f);
                rgb2 = LabToRgb(lab2);
                cmyk2 = RgbToCmyk(rgb2);
                hsv2 = RgbToHsv(rgb2);
            }

            ImGui::TextDisabled("Click to copy gradient color:");
            EmitCopyableData("Grad RGB", "rgb(%d, %d, %d)", (int)std::round(rgb2.r * 255.0f), (int)std::round(rgb2.g * 255.0f), (int)std::round(rgb2.b * 255.0f));
            EmitCopyableData("Grad CMYK", "cmyk(%.0f%%, %.0f%%, %.0f%%, %.0f%%)", cmyk2.c * 100.0f, cmyk2.m * 100.0f, cmyk2.y * 100.0f, cmyk2.k * 100.0f);
            EmitCopyableData("Grad HSV", "hsv(%.0f, %.0f%%, %.0f%%)", hsv2.h, hsv2.s * 100.0f, hsv2.v * 100.0f);
            EmitCopyableData("Grad CIE LAB", "lab(%.0f%% %.0f %.0f)", lab2.l, lab2.a, lab2.b);
        }

        ImGui::End();
        ImGui::Render();

        vertices.clear();
        float c1[4] = {rgb1.r, rgb1.g, rgb1.b, 1.0f};
        float c2[4] = {useGradient ? rgb2.r : rgb1.r, useGradient ? rgb2.g : rgb1.g, useGradient ? rgb2.b : rgb1.b, 1.0f};

        float aspect = (float)fbHeight / (float)fbWidth;

        if (currentShape == Shape::SQUARE) {
            float* cTL = gradDir == 0 ? c1 : c1;
            float* cTR = gradDir == 0 ? c2 : c1;
            float* cBL = gradDir == 0 ? c1 : c2;
            float* cBR = gradDir == 0 ? c2 : c2;

            vertices = {
                {{-0.5f * aspect, -0.5f}, {cBL[0], cBL[1], cBL[2], 1.0f}},
                {{ 0.5f * aspect, -0.5f}, {cBR[0], cBR[1], cBR[2], 1.0f}},
                {{-0.5f * aspect,  0.5f}, {cTL[0], cTL[1], cTL[2], 1.0f}},
                {{ 0.5f * aspect, -0.5f}, {cBR[0], cBR[1], cBR[2], 1.0f}},
                {{ 0.5f * aspect,  0.5f}, {cTR[0], cTR[1], cTR[2], 1.0f}},
                {{-0.5f * aspect,  0.5f}, {cTL[0], cTL[1], cTL[2], 1.0f}}
            };
        } else if (currentShape == Shape::TRIANGLE) {
            float tx1 = 0.0f * aspect, ty1 = 0.5f;
            float tx2 = -0.5f * aspect, ty2 = -0.5f;
            float tx3 = 0.5f * aspect, ty3 = -0.5f;

            float t1 = (gradDir == 0) ? ((tx1 / aspect) + 0.5f) : (0.5f - ty1);
            float t2 = (gradDir == 0) ? ((tx2 / aspect) + 0.5f) : (0.5f - ty2);
            float t3 = (gradDir == 0) ? ((tx3 / aspect) + 0.5f) : (0.5f - ty3);

            vertices = {
                {{tx1, ty1}, {c1[0]*(1.0f-t1)+c2[0]*t1, c1[1]*(1.0f-t1)+c2[1]*t1, c1[2]*(1.0f-t1)+c2[2]*t1, 1.0f}},
                {{tx2, ty2}, {c1[0]*(1.0f-t2)+c2[0]*t2, c1[1]*(1.0f-t2)+c2[1]*t2, c1[2]*(1.0f-t2)+c2[2]*t2, 1.0f}},
                {{tx3, ty3}, {c1[0]*(1.0f-t3)+c2[0]*t3, c1[1]*(1.0f-t3)+c2[1]*t3, c1[2]*(1.0f-t3)+c2[2]*t3, 1.0f}}
            };
        } else if (currentShape == Shape::CIRCLE) {
            int segments = 64;

            for (int i = 0; i < segments; ++i) {
                float theta1 = 2.0f * 3.1415926f * float(i) / float(segments);
                float theta2 = 2.0f * 3.1415926f * float(i + 1) / float(segments);
                
                float x0 = 0.0f, y0 = 0.0f;
                float x1 = (0.5f * cosf(theta1)) * aspect, y1 = 0.5f * sinf(theta1);
                float x2 = (0.5f * cosf(theta2)) * aspect, y2 = 0.5f * sinf(theta2);

                float t0 = (gradDir == 0) ? ((x0 / aspect) + 0.5f) : (0.5f - y0);
                float t1 = (gradDir == 0) ? ((x1 / aspect) + 0.5f) : (0.5f - y1);
                float t2 = (gradDir == 0) ? ((x2 / aspect) + 0.5f) : (0.5f - y2);

                vertices.push_back({{x0, y0}, {c1[0] * (1.0f - t0) + c2[0] *t0, c1[1] * (1.0f - t0) + c2[1] * t0, c1[2] * (1.0f - t0) + c2[2] * t0, 1.0f}});
                vertices.push_back({{x1, y1}, {c1[0] * (1.0f - t1) + c2[0] *t1, c1[1] * (1.0f - t1) + c2[1] * t1, c1[2] * (1.0f - t1) + c2[2] * t1, 1.0f}});
                vertices.push_back({{x2, y2}, {c1[0] * (1.0f - t2) + c2[0] *t2, c1[1] * (1.0f - t2) + c2[1] * t2, c1[2] * (1.0f - t2) + c2[2] * t2, 1.0f}});
            }
        }

        if (!vertices.empty()) {
            if (vertexBuffer) vertexBuffer->release();
            vertexBuffer = device->newBuffer(vertices.data(), vertices.size() * sizeof(VertexData), MTL::ResourceStorageModeShared);
        }

        MTL::CommandBuffer* commandBuffer = commandQueue->commandBuffer();
        MTL::RenderCommandEncoder* renderEncoder = commandBuffer->renderCommandEncoder(passDescriptor);

        if (!vertices.empty() && vertexBuffer) {
            renderEncoder->setRenderPipelineState(pipelineState);
            renderEncoder->setVertexBuffer(vertexBuffer, 0, 0);
            renderEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(vertices.size()));
        }

        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), 
                                       (__bridge id<MTLCommandBuffer>)commandBuffer, 
                                       (__bridge id<MTLRenderCommandEncoder>)renderEncoder);
                                       
        renderEncoder->endEncoding();
        commandBuffer->presentDrawable(drawable);
        commandBuffer->commit();

        passDescriptor->release();
        pool->release();
    }

    if (vertexBuffer) vertexBuffer->release();

    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    vertexFn->release();
    fragFn->release();
    pDesc->release();
    vDesc->release();
    pipelineState->release();
    library->release();
    commandQueue->release();
    device->release();
    glfwDestroyWindow(window);
    glfwTerminate();

    return 0;
}