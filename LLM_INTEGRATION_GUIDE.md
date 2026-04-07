# LiteRT-LM 集成指南

## 一、已创建/修改的文件清单

### Lua 层

| 文件 | 路径 | 说明 |
|------|------|------|
| LLM.lua | `src/app/modules/LLM.lua` | LLM 模块封装 |
| ChatScene.lua | `src/app/views/ChatScene.lua` | 类似微信的聊天界面 |
| MyApp.lua | `src/app/MyApp.lua` | ✅ 已修改，启动聊天界面 |

### Java 层

| 文件 | 路径 | 说明 |
|------|------|------|
| LLMEngine.java | `app/src/org/cocos2dx/lua/llm/LLMEngine.java` | LiteRT-LM 引擎封装 |
| LLMService.java | `app/src/org/cocos2dx/lua/llm/LLMService.java` | Lua 调用入口 |

### 配置文件

| 文件 | 路径 | 修改内容 |
|------|------|----------|
| build.gradle | `app/build.gradle` | 添加 LiteRT-LM 依赖 + 升级 SDK |
| AndroidManifest.xml | `app/AndroidManifest.xml` | 添加 GPU 库支持 |

---

## 二、模型文件下载

模型文件较大（约 2.5GB），请手动下载：

### 下载步骤

1. 访问 HuggingFace：
   ```
   https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
   ```

2. 点击 **Files and versions** 标签

3. 下载文件： `gemma-4-E2B-it.litertlm`

4. 放置到项目目录：
   ```
   frameworks/runtime-src/proj.android-studio/app/assets/models/gemma-4-E2B-it.litertlm
   ```

---

## 三、编译运行

### 编译项目

```bash
cd frameworks/runtime-src/proj.android-studio
./gradlew assembleDebug
```

### 安装到设备

```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

---

## 四、聊天界面功能

### 界面布局

```
┌─────────────────────────────────┐
│          AI 助手                 │  ← 标题栏
├─────────────────────────────────┤
│                                 │
│  ┌──────────────────┐           │  ← AI 消息（左侧白色）
│  │ 你好！有什么可以  │           │
│  │ 帮助你的吗？      │           │
│  └──────────────────┘           │
│                                 │
│           ┌──────────────────┐  │  ← 用户消息（右侧绿色）
│           │ 你好，介绍一下    │  │
│           │ Cocos2d-x        │  │
│           └──────────────────┘  │
│                                 │
│  ┌──────────────────┐           │  ← AI 流式输出
│  │ Cocos2d-x 是...  │           │
│  └──────────────────┘           │
│                                 │
├─────────────────────────────────┤
│ [  输入消息...        ] [发送]  │  ← 输入区域
└─────────────────────────────────┘
```

### API 使用

```lua
local llm = require("app.modules.LLM")

-- 初始化
llm.init({
    modelPath = "models/gemma-4-E2B-it.litertlm",
    backend = "GPU",
    onInit = function(success, error)
        print("Init:", success, error)
    end
})

-- 简单聊天
llm.chat("Hello!", function(response, error)
    print("Response:", response)
end)

-- 流式输出
llm.chatStream("Tell me a story",
    function(token) print(token) end,
    function(response) print("Done") end,
    function(error) print("Error:", error) end
)

-- 重置对话
llm.resetConversation()

-- 释放资源
llm.release()
```

---

## 五、注意事项

1. **系统要求**: Android 12+ (minSdk 21)
2. **内存要求**: 约 3GB 可用内存
3. **GPU 加速**: 推荐使用支持 OpenCL 的设备
4. **模型文件**: 首次加载需要时间，请耐心等待
5. **异步处理**: 所有推理都是异步的，不会阻塞游戏

---

## 六、故障排除

### 模型加载失败

- 检查模型文件是否存在于 `app/assets/models/` 目录
- 检查文件名是否正确： `gemma-4-E2B-it.litertlm`
- 查看日志： `adb logcat | grep LLM`

### 推理无响应

- 检查设备内存是否充足
- 尝试使用 CPU 后端： `backend = "CPU"`
- 检查 LiteRT-LM 依赖是否正确添加

### Java 层错误

- 检查 LLMService.java 和 LLMEngine.java 编译是否通过
- 查看 logcat 日志排查问题

---

## 七、后续优化

1. **添加语音输入**: 集成 Android Speech API
2. **多模型支持**: 添加模型切换功能
3. **对话历史**: 实现对话历史保存和加载
4. **自定义人设**: 允许用户自定义 AI 角色设定

---

*生成日期: 2026-04-07*
