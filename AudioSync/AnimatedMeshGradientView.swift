import SwiftUI
import MetalKit

struct AnimatedMeshGradientView: View {
    var colors: [Color]
    
    var body: some View {
        MetalMeshGradientView(colors: colors)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

struct MetalMeshGradientView: NSViewRepresentable {
    var colors: [Color]
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = context.coordinator.device
        mtkView.delegate = context.coordinator
        // 设置背景透明，以便 SwiftUI 背景可以透过
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false // 需要能够读取 framebuffer 内容（虽然这里不直接读取，但通常设为 false 以免问题）
        mtkView.autoResizeDrawable = true
        mtkView.enableSetNeedsDisplay = true // 允许按需重绘
        mtkView.isPaused = false // 确保视图不暂停
        mtkView.preferredFramesPerSecond = 60 // 目标帧率
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // 当 SwiftUI 视图更新时，通知 Coordinator 更新颜色
        context.coordinator.updateColors(colors)
        // 请求重绘
        nsView.setNeedsDisplay(nsView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(colors: colors)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let pipelineState: MTLRenderPipelineState
        var vertexBuffer: MTLBuffer
        var timeBuffer: MTLBuffer
        var colorBuffer: MTLBuffer
        var gridPointsBuffer: MTLBuffer // 存储网格点位置
        var startTime: TimeInterval
        
        // 顶点结构体
        struct Vertex {
            var position: SIMD2<Float>
        }
        
        // 时间 uniform 结构体
        struct TimeUniforms {
            var time: Float
        }
        
        // 颜色 uniform 结构体 (着色器中会定义为数组)
        // struct ColorUniforms {
        //     var colors: [SIMD4<Float>] // 实际在着色器中是 float4 colors[9]
        // }
        
        // 网格点结构体
        struct GridPoint {
            var position: SIMD2<Float>
        }
        
        init(colors: [Color]) {
            // 获取默认 Metal 设备
            guard let device = MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue() else {
                fatalError("Metal is not supported on this device")
            }
            
            self.device = device
            self.commandQueue = commandQueue
            self.startTime = CACurrentMediaTime() // 记录开始时间，用于动画
            
            // 创建渲染管线
            let library: MTLLibrary
            do {
                // 从 metalShaderSource 字符串编译着色器
                library = try device.makeLibrary(source: metalShaderSource, options: nil)
            } catch {
                fatalError("Failed to compile Metal shaders: \(error)")
            }

            guard let vertexFunction = library.makeFunction(name: "vertexShader"),
                  let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
                fatalError("Failed to load shader functions from Metal library")
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // 与 MTKView 格式匹配

            // 配置顶点描述符 (虽然我们的顶点着色器很简单，但这是标准做法)
            let vertexDescriptor = MTLVertexDescriptor()
            // 属性0: 位置
            vertexDescriptor.attributes[0].format = .float2 // SIMD2<Float>
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0 // 对应顶点缓冲区的索引

            // 布局0: 描述顶点数据如何排列
            vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride // 单个顶点的步长
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stepFunction = .perVertex

            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                fatalError("Failed to create pipeline state: \(error)")
            }
            
            // 创建顶点缓冲区 (一个覆盖全屏的大三角形)
            // 这些坐标是归一化设备坐标 (NDC)
            let vertices: [Vertex] = [
                Vertex(position: SIMD2<Float>(-1, -1)), // 左下
                Vertex(position: SIMD2<Float>(-1,  3)), // 左上延伸 (确保覆盖)
                Vertex(position: SIMD2<Float>( 3, -1))  // 右下延伸 (确保覆盖)
            ]
            
            vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<Vertex>.stride * vertices.count,
                options: .storageModeManaged // CPU 和 GPU 共享内存
            )!
            
            // 创建时间缓冲区
            var initialTime = TimeUniforms(time: 0)
            timeBuffer = device.makeBuffer(
                bytes: &initialTime,
                length: MemoryLayout<TimeUniforms>.stride,
                options: .storageModeManaged
            )!
            
            // 创建颜色缓冲区 (9个颜色, 每个颜色是 SIMD4<Float>)
            colorBuffer = device.makeBuffer(
                length: MemoryLayout<SIMD4<Float>>.stride * 9, // 9 个颜色
                options: .storageModeManaged
            )!
            
            // 创建网格点缓冲区 (9个点, 每个点是 SIMD2<Float>)
            gridPointsBuffer = device.makeBuffer(
                length: MemoryLayout<GridPoint>.stride * 9, // 9 个网格点
                options: .storageModeManaged
            )!
            
            super.init()
            
            // 初始化颜色和网格点
            updateColors(colors) // 初始颜色加载
            updateGridPoints(time: 0) // 初始网格点位置
        }
        
        func updateColors(_ swiftUIColors: [Color]) {
            // 确保有9个颜色，如果不够则随机补充
            var adjustedColors = swiftUIColors
            while adjustedColors.count < 9 {
                adjustedColors.append(adjustedColors.randomElement() ?? .blue) // 默认补充蓝色
            }
            
            // 将 SwiftUI Color 转换为 Metal 使用的 SIMD4<Float> (RGBA)
            var floatColors: [SIMD4<Float>] = adjustedColors.prefix(9).map { color in
                // NSColor 用于更准确地获取 RGBA 分量
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.blue
                return SIMD4<Float>(
                    Float(nsColor.redComponent),
                    Float(nsColor.greenComponent),
                    Float(nsColor.blueComponent),
                    Float(nsColor.alphaComponent)
                )
            }
            
            // 更新颜色缓冲区内容
            // `memcpy` 用于将数据从 `floatColors` 数组复制到 Metal 缓冲区的内存中
            memcpy(colorBuffer.contents(), &floatColors, MemoryLayout<SIMD4<Float>>.stride * 9)
            // 通知 Metal 缓冲区内容已修改 (对于 .storageModeManaged)
            colorBuffer.didModifyRange(0..<colorBuffer.length)
        }
        
        func updateGridPoints(time: Float) {
            // 计算动画偏移量，这里使用 sin 函数制造周期性摆动
            // 0.3 是振幅，0.8 是一个调节系数，可以调整动画的幅度
            let dynamicOffset = 0.25 * sin(time * 0.7) // 调整时间和幅度使动画更明显
            
            // 定义9个网格点的动态位置
            // 这些坐标是归一化的 [0,1] 范围，对应 UV 坐标空间
            let gridPoints: [GridPoint] = [
                // 第一行
                GridPoint(position: SIMD2<Float>(0.0 + dynamicOffset * 0.5, 0.0 - dynamicOffset * 0.3)),
                GridPoint(position: SIMD2<Float>(0.5, 0.0 + dynamicOffset)),
                GridPoint(position: SIMD2<Float>(1.0 - dynamicOffset * 0.5, 0.0 + dynamicOffset * 0.3)),
                
                // 第二行
                GridPoint(position: SIMD2<Float>(0.0 - dynamicOffset, 0.5)),
                GridPoint(position: SIMD2<Float>(0.5 + dynamicOffset * 0.2, 0.5 - dynamicOffset * 0.2)), // 中心点也稍微动一下
                GridPoint(position: SIMD2<Float>(1.0 + dynamicOffset, 0.5)),
                
                // 第三行
                GridPoint(position: SIMD2<Float>(0.0 + dynamicOffset * 0.3, 1.0 + dynamicOffset * 0.5)),
                GridPoint(position: SIMD2<Float>(0.5, 1.0 - dynamicOffset)),
                GridPoint(position: SIMD2<Float>(1.0 - dynamicOffset * 0.3, 1.0 - dynamicOffset * 0.5))
            ]
            
            // 更新网格点缓冲区内容
            memcpy(gridPointsBuffer.contents(), gridPoints, MemoryLayout<GridPoint>.stride * 9)
            gridPointsBuffer.didModifyRange(0..<gridPointsBuffer.length)
        }
        
        // MTKViewDelegate 方法：当视图大小改变时调用
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // 通常在这里处理投影矩阵等的更新，但对于这个2D效果不是必需的
        }
        
        // MTKViewDelegate 方法：每帧绘制时调用
        func draw(in view: MTKView) {
            // 获取当前的 drawable 和 render pass descriptor
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            // renderPassDescriptor.colorAttachments[0].loadAction = .clear // 确保清除背景
            // renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0) // 清除为透明

            // 更新时间 uniform
            let currentTime = CACurrentMediaTime() - startTime // 计算经过的时间
            var timeUniforms = TimeUniforms(time: Float(currentTime))
            memcpy(timeBuffer.contents(), &timeUniforms, MemoryLayout<TimeUniforms>.stride)
            timeBuffer.didModifyRange(0..<timeBuffer.length)
            
            // 根据当前时间更新网格点的位置
            updateGridPoints(time: timeUniforms.time)
            
            // 创建命令缓冲区
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  // 创建渲染命令编码器
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            // 设置渲染管线状态
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // 设置顶点缓冲区
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0) // 顶点数据
            // 注意：时间缓冲区在这里没有直接给顶点着色器，因为顶点位置是固定的。
            // 如果顶点也需要随时间变化，则需要在这里传递。

            // 设置片段着色器所需的缓冲区
            renderEncoder.setFragmentBuffer(colorBuffer, offset: 0, index: 0)       // 颜色数据
            renderEncoder.setFragmentBuffer(gridPointsBuffer, offset: 0, index: 1)  // 网格点位置
            renderEncoder.setFragmentBuffer(timeBuffer, offset: 0, index: 2)        // 时间数据 (片段着色器也可能需要)
            
            // 绘制三角形 (3个顶点)
            renderEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 3
            )
            
            // 结束编码
            renderEncoder.endEncoding()
            
            // 呈现 drawable
            commandBuffer.present(drawable)
            
            // 提交命令缓冲区执行
            commandBuffer.commit()
        }
    }
}

// Metal 着色器代码字符串
// 修改了片段着色器以使用反距离加权法来混合颜色
let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

// 顶点着色器的输入结构
struct VertexIn {
    float2 position [[attribute(0)]]; // 从顶点缓冲区读取的位置属性
};

// 顶点着色器的输出结构 (传递给片段着色器)
struct VertexOut {
    float4 position [[position]]; // 裁剪空间中的顶点位置 (必需)
    float2 uv;                   // 纹理/归一化坐标
};

// Uniform 结构体，从 CPU 传递给 GPU
struct TimeUniforms {
    float time;
};

struct ColorUniforms { // 在着色器中，我们将直接使用 float4 colors[9]
    float4 colors[9]; // 9个颜色
};

struct GridPoint {
    float2 position; // 网格点的归一化位置
};

// 顶点着色器
vertex VertexOut vertexShader(
    VertexIn in [[stage_in]] // [[stage_in]] 表示这是顶点着色器的输入
) {
    VertexOut out;
    
    // 直接将输入的2D位置转换为裁剪空间的4D位置
    // z=0, w=1 是2D渲染的常见设置
    out.position = float4(in.position, 0.0, 1.0);
    
    // 将输入的顶点位置从 [-1, 1] (NDC范围的一部分) 映射到 [0, 1] 的 UV 坐标
    // 这个 UV 坐标将覆盖整个渲染区域
    out.uv = (in.position + 1.0) * 0.5; 
    
    return out;
}

// 片段着色器
fragment float4 fragmentShader(
    VertexOut in [[stage_in]], // 从顶点着色器接收插值后的数据
    constant float4 *colorsArray [[buffer(0)]],        // 颜色数组 (9个颜色)
    constant GridPoint *gridPoints [[buffer(1)]],   // 网格点数组 (9个点)
    constant TimeUniforms &timeUniforms [[buffer(2)]] // 时间 (如果需要直接在片段着色器中使用)
) {
    float2 uv = in.uv; // 当前片段的 UV 坐标 [0,1]
    
    float4 totalColor = float4(0.0); // 初始化累积颜色
    float totalWeight = 0.0;         // 初始化累积权重
    
    // sharpness 控制颜色点的“锐度”或影响范围
    // 数值越大，影响范围越小，颜色点越清晰；数值越小，混合越平滑模糊
    float sharpness = 25.0; // 可以调整这个值以获得期望的效果

    // 遍历所有9个网格点
    for (int i = 0; i < 9; ++i) {
        float2 pointPos = gridPoints[i].position; // 当前网格点的位置
        float dist = distance(uv, pointPos);       // 计算当前片段到网格点的距离
        
        // 使用高斯型权重函数 (exp(-k * d^2))
        // 这种权重衰减方式比简单的反比更平滑
        float weight = exp(-sharpness * dist * dist);
        
        totalColor += colorsArray[i] * weight; // 累加加权颜色
        totalWeight += weight;                 // 累加权重
    }

    float4 finalColor;
    if (totalWeight == 0.0 || totalWeight < 0.0001) { // 避免除以零或极小的权重
        // 如果总权重几乎为零 (例如像素离所有点都很远，或者 sharpness 极高)
        // 可以返回一个默认颜色，或者第一个点的颜色，或者透明
        finalColor = float4(0.0, 0.0, 0.0, 0.0); // 返回透明黑色
    } else {
        finalColor = totalColor / totalWeight; // 标准化颜色
    }
    
    // 可以选择性地对最终的 alpha 进行平滑处理，如果需要的话
    // finalColor.a = smoothstep(0.0, 1.0, finalColor.a); 
    // 如果颜色本身已经包含了alpha，并且希望它平滑过渡，可以保留此行。
    // 如果希望alpha直接由混合决定，可以注释掉。

    return finalColor;
}
"""

// 这个函数不是必须的，因为着色器是在 Coordinator 初始化时编译的。
// 但如果需要在应用启动时做一些全局的 Metal 初始化，可以保留。
// func registerMetalShaders() {
//     do {
//         let _ =  MTKTextureLoader(device: MTLCreateSystemDefaultDevice()!)
        
//         let library = try MTLCreateSystemDefaultDevice()!.makeLibrary(
//             source: metalShaderSource,
//             options: nil
//         )
        
//         _ = library.makeFunction(name: "vertexShader")
//         _ = library.makeFunction(name: "fragmentShader")
//     } catch {
//         print("Failed to register Metal shaders: \(error)")
//     }
// }


