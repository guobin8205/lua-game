# Google AI Edge Gallery 技术方案分析

> 本文档详细拆解 Google AI Edge Gallery 项目如何在 Android 设备上本地运行 Gemma 4 等大语言模型

---

## 目录

- [一、项目概述](#一项目概述)
- [二、整体架构](#二整体架构)
- [三、核心技术组件](#三核心技术组件)
- [四、模型来源与格式](#四模型来源与格式)
- [五、技术实现流程](#五技术实现流程)
- [六、硬件加速机制](#六硬件加速机制)
- [七、关键技术优势](#七关键技术优势)
- [八、本地构建步骤](#八本地构建步骤)
- [九、总结](#九总结)

---

## 一、项目概述

**Google AI Edge Gallery** 是 Google 推出的开源示例应用，展示如何在 Android/iOS 移动设备上本地运行大语言模型（LLM）。

### 核心目标

- **100% 本地推理**：所有计算在设备端完成
- **隐私保护**：用户数据不离开设备
- **离线可用**：无需网络连接
- **硬件加速**：充分利用 GPU/NPU

### 项目地址

- GitHub: https://github.com/google-ai-edge/gallery

---

## 二、整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Android Application                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐   │
│  │ HuggingFace │   │   CameraX   │   │    UI Layer     │   │
│  │    OAuth    │   │  (图像输入)  │   │(Jetpack Compose)│   │
│  └──────┬──────┘   └──────┬──────┘   └────────┬────────┘   │
│         │                 │                    │            │
│         ▼                 ▼                    ▼            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                                                       │  │
│  │                  LiteRT-LM 推理引擎                    │  │
│  │         (Google 生产级高性能 LLM 推理框架)             │  │
│  │                                                       │  │
│  └───────────────────────────┬───────────────────────────┘  │
│                              │                              │
│            ┌─────────────────┼─────────────────┐            │
│            ▼                 ▼                 ▼            │
│     ┌───────────┐     ┌───────────┐     ┌───────────┐      │
│     │    CPU    │     │    GPU    │     │    NPU    │      │
│     │   (后备)  │     │   (加速)  │     │ (硬件加速) │      │
│     └───────────┘     └───────────┘     └───────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼
                 ┌───────────────────────────┐
                 │     .litertlm 模型文件     │
                 │     (来自 HuggingFace)     │
                 └───────────────────────────┘
```

### 架构层次说明

| 层级 | 组件 | 职责 |
|------|------|------|
| 应用层 | UI Layer | 用户界面交互（Jetpack Compose） |
| 输入层 | CameraX / Audio | 多模态输入（图像、音频） |
| 认证层 | HuggingFace OAuth | 模型下载授权 |
| 推理层 | LiteRT-LM | 模型加载与推理执行 |
| 硬件层 | CPU / GPU / NPU | 计算加速 |

---

## 三、核心技术组件

### 3.1 LiteRT-LM 推理引擎

**LiteRT-LM** 是整个方案的核心，是 Google 推出的生产级高性能 LLM 推理框架。

#### 技术特性

| 特性 | 说明 |
|------|------|
| 基础框架 | LiteRT（TensorFlow Lite 继任者） |
| 模型格式 | `.litertlm` 专用格式 |
| 硬件加速 | GPU / NPU 自动调度 |
| 多模态支持 | 文本、图像、音频输入 |
| 高级功能 | Tool Use / Function Calling / Thinking Mode |

#### 项目地址

- GitHub: https://github.com/google-ai-edge/LiteRT-LM

### 3.2 关键依赖配置

```kotlin
// build.gradle.kts 核心依赖

// LiteRT-LM 推理引擎（核心）
implementation(libs.litertlm)

// TensorFlow Lite 基础组件
implementation(libs.tflite)          // TFLite 运行时
implementation(libs.tflite.gpu)      // GPU 加速插件
implementation(libs.tflite.support)  // 支持库

// 多模态输入
implementation(libs.camerax.core)    // 相机图像输入

// HuggingFace 认证
implementation(libs.openid.appauth)  // OAuth 2.0 客户端
```

### 3.3 系统要求

| 配置项 | 值 |
|--------|-----|
| minSdk | 31 (Android 12+) |
| targetSdk | 35 |
| 推荐设备 | 支持 GPU/NPU 的设备 |

### 3.4 HuggingFace 集成配置

```kotlin
// ProjectConfig.kt

object ProjectConfig {
    // HuggingFace OAuth 配置
    const val clientId = "YOUR_HUGGINGFACE_CLIENT_ID"
    const val redirectUri = "YOUR_REDIRECT_URI"

    // OAuth 端点
    private const val authEndpoint = "https://huggingface.co/oauth/authorize"
    private const val tokenEndpoint = "https://huggingface.co/oauth/token"
}
```

#### 配置步骤

1. 访问 https://huggingface.co/settings/applications
2. 创建新的 Developer Application
3. 配置回调 URI
4. 获取 clientId 并填入项目配置

---

## 四、模型来源与格式

### 4.1 支持的模型列表

| 模型 | HuggingFace 仓库路径 | 参数量 |
|------|---------------------|--------|
| **Gemma 4** | `litert-community/gemma-4-E2B-it-litert-lm` | 2B |
| Llama 3.2 | `litert-community/Llama-3.2-1B-Instruct-litert-lm` | 1B |
| Phi-4 | `litert-community/Phi-4-mini-instruct-litert-lm` | Mini |
| Qwen 2.5 | `litert-community/Qwen2.5-1.5B-Instruct-litert-lm` | 1.5B |

### 4.2 .litertlm 模型格式

`.litertlm` 是 LiteRT-LM 专用的模型格式，针对移动端优化。

#### 格式组成

```
┌─────────────────────────────────────┐
│          .litertlm 文件结构          │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │      模型元数据 (Metadata)   │   │
│  │  - 模型版本                  │   │
│  │  - 输入/输出规格             │   │
│  │  - 硬件加速配置              │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │     量化模型权重 (Weights)   │   │
│  │  - INT8 / INT4 量化          │   │
│  │  - 压缩存储                  │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │      推理配置 (Config)       │   │
│  │  - KV Cache 配置             │   │
│  │  - Tokenizer 配置            │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

#### 量化优势

| 指标 | 原始模型 | 量化后 (.litertlm) |
|------|----------|-------------------|
| 模型大小 | ~5-10 GB | ~1-3 GB |
| 内存占用 | 高 | 低（适配移动端） |
| 推理速度 | 慢 | 快（硬件加速） |

---

## 五、技术实现流程

### 5.1 模型部署流程

```
┌─────────────────────────────────────────────────────────────┐
│                      模型部署完整流程                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step 1: HuggingFace OAuth 认证                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  用户点击登录 → 跳转 HuggingFace 授权页              │   │
│  │  → 用户同意 → 获取 Access Token                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            ▼                               │
│  Step 2: 下载 .litertlm 模型文件                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  选择模型 → 从 HuggingFace 下载 .litertlm 文件       │   │
│  │  → 存储到设备本地                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            ▼                               │
│  Step 3: LiteRT-LM 加载模型                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  初始化 LiteRT-LM 引擎                               │   │
│  │  → 加载 .litertlm 文件                               │   │
│  │  → 解析模型元数据和权重                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            ▼                               │
│  Step 4: 硬件加速初始化                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  检测设备硬件能力                                    │   │
│  │  → 优先选择 NPU → 次选 GPU → 兜底 CPU               │   │
│  │  → 编译优化后的执行图                                │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                               │
│                            ▼                               │
│  Step 5: 执行本地推理                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  用户输入 → Tokenizer 编码 → 模型推理               │   │
│  │  → 解码输出 → 返回结果                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 推理调用示例

#### CLI 命令行使用

```bash
# 使用 LiteRT-LM CLI 运行模型
litert-lm run \
   --from-huggingface-repo=litert-community/gemma-4-E2B-it-litert-lm \
   gemma-4-E2B-it.litertlm \
   --prompt="What is the capital of France?"
```

#### Android 代码调用（伪代码）

```kotlin
// 初始化 LiteRT-LM 引擎
val engine = LiteRTLMEngine.create(context)

// 加载模型
engine.loadModel(modelPath = "gemma-4-E2B-it.litertlm")

// 执行推理
val response = engine.generate(
    prompt = "What is the capital of France?",
    maxTokens = 256,
    temperature = 0.7f
)

// 流式输出
engine.generateStream(prompt) { token ->
    // 实时接收生成的 token
    updateUI(token)
}
```

---

## 六、硬件加速机制

### 6.1 加速器调度策略

```
┌─────────────────────────────────────────────────────────────┐
│                   LiteRT-LM 硬件调度器                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │              Step 1: 硬件能力检测                    │  │
│   │                                                     │  │
│   │   检查 NPU 是否可用？  ──────→  检查 GPU 是否可用？  │  │
│   │          │                      │                   │  │
│   │          ▼                      ▼                   │  │
│   │      [可用]                  [可用]                 │  │
│   │          │                      │                   │  │
│   │          ▼                      ▼                   │  │
│   │   ┌─────────────────────────────────────────┐      │  │
│   │   │  Step 2: 选择最优执行路径               │      │  │
│   │   │                                         │      │  │
│   │   │  优先级: NPU > GPU > CPU                │      │  │
│   │   │                                         │      │  │
│   │   │  - NPU: 神经处理单元，AI 专用           │      │  │
│   │   │  - GPU: 图形处理器，并行计算能力强      │      │  │
│   │   │  - CPU: 通用处理器，兼容性最好          │      │  │
│   │   └─────────────────────────────────────────┘      │  │
│   │                      │                              │  │
│   │                      ▼                              │  │
│   │   ┌─────────────────────────────────────────┐      │  │
│   │   │  Step 3: 编译优化执行图                 │      │  │
│   │   │                                         │      │  │
│   │   │  针对选定硬件优化算子执行顺序           │      │  │
│   │   └─────────────────────────────────────────┘      │  │
│   │                                                     │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 各加速器性能对比

| 加速器 | 性能 | 功耗 | 兼容性 | 适用场景 |
|--------|------|------|--------|----------|
| **NPU** | ⭐⭐⭐⭐⭐ | 最低 | 中等 | AI 专用，最佳性能 |
| **GPU** | ⭐⭐⭐⭐ | 中等 | 高 | 广泛兼容，次优选择 |
| **CPU** | ⭐⭐ | 最高 | 100% | 兜底方案，所有设备 |

### 6.3 硬件加速原理

```
┌─────────────────────────────────────────────────────────┐
│                    矩阵运算加速原理                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Transformer 模型核心计算:  Y = X × W + b               │
│                                                         │
│  其中:                                                   │
│    X = 输入向量 (batch × seq_len × hidden_dim)         │
│    W = 权重矩阵 (hidden_dim × hidden_dim)              │
│    b = 偏置向量 (hidden_dim)                            │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │              GPU/NPU 并行计算优势                  │ │
│  │                                                   │ │
│  │  CPU: 串行计算，逐元素处理                        │ │
│  │       O(n³) 时间复杂度                            │ │
│  │                                                   │ │
│  │  GPU/NPU: 并行计算，数千核心同时处理              │ │
│  │           大幅降低实际执行时间                    │ │
│  │                                                   │ │
│  └───────────────────────────────────────────────────┘ │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 七、关键技术优势

### 7.1 优势列表

| 优势 | 说明 | 技术实现 |
|------|------|----------|
| **隐私保护** | 100% 本地推理，数据不离开设备 | 无网络请求 |
| **离线可用** | 无需网络连接 | 模型本地存储 |
| **低延迟** | 硬件加速推理 | GPU/NPU 加速 |
| **多模态** | 支持图像、音频输入 | CameraX / Audio API |
| **Agent 能力** | Tool Use / Function Calling | LiteRT-LM 内置支持 |
| **Thinking Mode** | 显示推理过程 | Gemma 4 原生支持 |

### 7.2 与云端方案对比

| 对比项 | 云端推理 | 本地推理 (AI Edge) |
|--------|----------|-------------------|
| 网络依赖 | 必须 | 无需 |
| 隐私保护 | 数据上传云端 | 数据不离设备 |
| 延迟 | 网络延迟 + 推理延迟 | 仅推理延迟 |
| 成本 | 按请求计费 | 一次性设备成本 |
| 可用性 | 依赖服务可用性 | 永久可用 |
| 模型大小 | 无限制 | 受设备内存限制 |

---

## 八、本地构建步骤

### 8.1 前置条件

- Android Studio Hedgehog 或更高版本
- Android SDK 35
- HuggingFace 账号

### 8.2 详细步骤

#### Step 1: 配置 HuggingFace Developer Application

```
1. 访问 https://huggingface.co/settings/applications
2. 点击 "Create new application"
3. 填写应用信息:
   - Name: AI Edge Gallery Local
   - Redirect URI: your-app-scheme://auth
4. 记录 clientId
```

#### Step 2: 克隆项目

```bash
git clone https://github.com/google-ai-edge/gallery.git
cd gallery
```

#### Step 3: 配置 OAuth

编辑 `Android/src/app/src/main/java/com/google/ai/edge/gallery/ProjectConfig.kt`:

```kotlin
object ProjectConfig {
    const val clientId = "你的_HUGGINGFACE_CLIENT_ID"
    const val redirectUri = "你的_REDIRECT_URI"
    // ...
}
```

#### Step 4: 构建项目

```bash
# 使用 Android Studio 打开项目
# 或使用命令行
./gradlew assembleDebug
```

#### Step 5: 运行应用

1. 连接 Android 设备 (Android 12+)
2. 安装 APK
3. 首次启动需要 HuggingFace 登录
4. 下载模型后即可离线使用

---

## 九、总结

### 技术方案核心

Google AI Edge Gallery 的技术方案核心是 **LiteRT-LM 推理引擎**。

### 关键技术点

1. **模型优化**: 通过 `.litertlm` 格式实现模型量化和压缩
2. **硬件加速**: 自动调度 NPU/GPU/CPU 实现最优性能
3. **本地推理**: 100% 设备端计算，保护隐私
4. **多模态支持**: 文本、图像、音频输入

### 技术栈总结

```
┌─────────────────────────────────────────┐
│              技术栈全景图                │
├─────────────────────────────────────────┤
│                                         │
│  推理引擎:  LiteRT-LM                   │
│  基础框架:  LiteRT (TFLite 继任者)      │
│  模型格式:  .litertlm                   │
│  硬件加速:  GPU / NPU                   │
│  模型来源:  HuggingFace                 │
│  认证方式:  OAuth 2.0                   │
│  多模态:    CameraX / Audio API         │
│  UI 框架:   Jetpack Compose             │
│                                         │
└─────────────────────────────────────────┘
```

### 适用场景

- 隐私敏感应用（医疗、金融）
- 离线环境应用
- 低延迟要求的实时应用
- 边缘 AI 部署

---

## 附录

### A. 相关资源链接

| 资源 | 链接 |
|------|------|
| AI Edge Gallery | https://github.com/google-ai-edge/gallery |
| LiteRT-LM | https://github.com/google-ai-edge/LiteRT-LM |
| LiteRT | https://github.com/google-ai-edge/LiteRT |
| HuggingFace LiteRT 社区 | https://huggingface.co/litert-community |
| Gemma 官方 | https://ai.google.dev/gemma |

### B. 参考文档

- [LiteRT-LM 官方文档](https://github.com/google-ai-edge/LiteRT-LM#readme)
- [Android GPU 加速指南](https://www.tensorflow.org/lite/performance/gpu)
- [HuggingFace OAuth 文档](https://huggingface.co/docs/hub/oauth)

---

*文档生成日期: 2026-04-07*
