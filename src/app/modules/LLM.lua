--[[
    LLM.lua - LiteRT-LM Lua 封装模块（Java 层流式下载）

    功能：
    - Java 层流式下载模型文件（不 OOM）
    - 真实下载进度回调
    - 初始化 LiteRT-LM 引擎
    - 支持异步聊天（带回调）
    - 支持流式输出
    - 保持对话上下文

    使用示例：
        local llm = require("app.modules.LLM")

        -- 自动下载模型并初始化
        llm.initWithDownload({
            backend = "GPU",
            onProgress = function(percent)
                print("下载进度:", percent .. "%")
            end,
            onInit = function(success, error)
                print("Init:", success, error)
            end
        })

        -- 聊天
        llm.chat("Hello!", function(response, error)
            if error then
                print("Error:", error)
            else
                print("Response:", response)
            end
        end)
]]

local LLM = {}

-- ==================== 配置 ====================

local CONFIG = {
    -- 默认模型下载地址 (ModelScope)
    defaultModelUrl = "https://modelscope.cn/models/litert-community/gemma-4-E2B-it-litert-lm/resolve/master/gemma-4-E2B-it.litertlm",
    -- 模型文件名
    modelFileName = "gemma-4-E2B-it.litertlm",
}

-- ==================== 私有变量 ====================

local _initialized = false
local _initializing = false
local _downloading = false
local _downloadProgress = 0
local _lastError = nil
local _platform = cc.Application:getInstance():getTargetPlatform()
local _initCallbacks = {}
local _callbackIdCounter = 0
local _callbackMap = {}

-- 下载回调（单次下载，不需要 ID 映射）
local _downloadProgressCallback = nil
local _downloadCompleteCallback = nil

-- Java 类名
local CLASS_NAME = "org/cocos2dx/lua/llm/LLMService"

-- ==================== 平台检测 ====================

local function isAndroid()
    return _platform == cc.PLATFORM_OS_ANDROID
end

local function getLuaj()
    if isAndroid() then
        return require("cocos.cocos2d.luaj")
    end
    return nil
end

-- ==================== 回调管理 ====================

local function generateCallbackId()
    _callbackIdCounter = _callbackIdCounter + 1
    return _callbackIdCounter
end

local function registerCallback(callback)
    if type(callback) ~= "function" then
        return 0
    end
    local id = generateCallbackId()
    _callbackMap[id] = callback
    return id
end

local function popCallback(id)
    local callback = _callbackMap[id]
    _callbackMap[id] = nil
    return callback
end

-- ==================== 全局回调函数 ====================

-- 初始化回调（Java 层调用）
cc.exports.__LLM_ON_INIT__ = function(result)
    if result == "SUCCESS" then
        _initialized = true
        _lastError = nil
    else
        _initialized = false
        if string.find(result, "^ERROR:") then
            _lastError = string.sub(result, 7)
        else
            _lastError = result
        end
    end
    _initializing = false

    -- 调用所有注册的回调
    local callbacks = _initCallbacks
    _initCallbacks = {}
    for _, cb in ipairs(callbacks) do
        if type(cb) == "function" then
            cb(_initialized, _lastError)
        end
    end
end

-- Token 回调（流式输出）
cc.exports.__LLM_ON_TOKEN__ = function(data)
    local colonPos = string.find(data, ":")
    if colonPos then
        local id = tonumber(string.sub(data, 1, colonPos - 1))
        local token = string.sub(data, colonPos + 1)
        local callback = _callbackMap[id]
        if callback then
            callback(token)
        end
    end
end

-- 简单聊天回调
cc.exports.__LLM_ON_CHAT__ = function(data)
    local colonPos = string.find(data, ":")
    if colonPos then
        local id = tonumber(string.sub(data, 1, colonPos - 1))
        local response = string.sub(data, colonPos + 1)
        local callback = popCallback(id)

        if callback then
            if string.find(response, "^ERROR:") then
                callback(nil, string.sub(response, 7))
            else
                callback(response, nil)
            end
        end
    end
end

-- 流式聊天完成回调
cc.exports.__LLM_ON_COMPLETE__ = function(data)
    local colonPos = string.find(data, ":")
    if colonPos then
        local id = tonumber(string.sub(data, 1, colonPos - 1))
        local response = string.sub(data, colonPos + 1)
        local callback = popCallback(id)
        if callback then
            callback(response)
        end
    end
end

-- 流式聊天错误回调
cc.exports.__LLM_ON_ERROR__ = function(data)
    local colonPos = string.find(data, ":")
    if colonPos then
        local id = tonumber(string.sub(data, 1, colonPos - 1))
        local errorMsg = string.sub(data, colonPos + 1)
        local callback = popCallback(id)
        if callback then
            callback(errorMsg)
        end
    end
end

-- 下载进度回调（Java 层调用，数据为纯数字字符串）
cc.exports.__LLM_ON_DOWNLOAD_PROGRESS__ = function(data)
    local percent = tonumber(data)
    if percent then
        _downloadProgress = percent
        if _downloadProgressCallback then
            _downloadProgressCallback(percent)
        end
    end
end

-- 下载完成回调（Java 层调用，数据为文件路径）
cc.exports.__LLM_ON_DOWNLOAD_COMPLETE__ = function(data)
    _downloading = false
    _downloadProgress = 100
    print("[LLM] Download completed:", data)
    if _downloadCompleteCallback then
        if string.find(data, "^ERROR:") then
            _downloadCompleteCallback(nil, string.sub(data, 7))
        else
            _downloadCompleteCallback(data, nil)
        end
    end
end

-- 下载错误回调（Java 层调用，数据为错误信息）
cc.exports.__LLM_ON_DOWNLOAD_ERROR__ = function(data)
    _downloading = false
    print("[LLM] Download error:", data)
    if _downloadCompleteCallback then
        _downloadCompleteCallback(nil, data)
    end
end

-- ==================== 模型路径相关 ====================

--[[
    获取模型存储目录（通过 Java 层获取正确路径）
]]
function LLM.getModelDir()
    if isAndroid() then
        local luaj = getLuaj()
        local ok, ret = luaj.callStaticMethod(
            CLASS_NAME,
            "getModelDir",
            {},
            "()Ljava/lang/String;"
        )
        if ok and ret then
            return ret
        end
    end
    return "/sdcard/Android/data/org.cocos2dx.hellolua/files/models"
end

--[[
    获取模型文件完整路径
]]
function LLM.getModelPath()
    return LLM.getModelDir() .. "/" .. CONFIG.modelFileName
end

-- ==================== 下载相关 ====================

--[[
    检查模型是否已下载
]]
function LLM.isModelDownloaded()
    if isAndroid() then
        local luaj = getLuaj()
        local ok, ret = luaj.callStaticMethod(
            CLASS_NAME,
            "checkModelExists",
            {LLM.getModelPath()},
            "(Ljava/lang/String;)Z"
        )
        return ok and ret
    end
    return false
end

--[[
    获取下载进度
]]
function LLM.getDownloadProgress()
    return _downloadProgress
end

--[[
    是否正在下载
]]
function LLM.isDownloading()
    return _downloading
end

--[[
    下载模型（Java 层流式下载，不会 OOM）

    @param config table
        - modelUrl: string 模型下载地址（可选，使用默认地址）
        - onProgress: function 进度回调 function(percent)
        - onComplete: function 完成回调 function(filePath, error)

    @return boolean 是否开始下载
]]
function LLM.downloadModel(config)
    if not isAndroid() then
        if config and config.onComplete then
            config.onComplete(nil, "Not Android platform")
        end
        return false
    end

    if _downloading then
        print("[LLM] Already downloading")
        return false
    end

    -- 检查是否已下载
    if LLM.isModelDownloaded() then
        print("[LLM] Model already downloaded")
        if config and config.onComplete then
            config.onComplete(LLM.getModelPath(), nil)
        end
        return true
    end

    _downloading = true
    _downloadProgress = 0

    -- 注册回调
    _downloadProgressCallback = config and config.onProgress
    _downloadCompleteCallback = config and config.onComplete

    local modelUrl = config and config.modelUrl or CONFIG.defaultModelUrl
    local modelPath = LLM.getModelPath()

    print("[LLM] Starting download:", modelUrl)
    print("[LLM] Target path:", modelPath)

    -- 调用 Java 层流式下载
    local luaj = getLuaj()
    local ok, ret = luaj.callStaticMethod(
        CLASS_NAME,
        "downloadModel",
        {modelUrl, modelPath},
        "(Ljava/lang/String;Ljava/lang/String;)Z"
    )

    if not ok then
        _downloading = false
        print("[LLM] Failed to start download:", ret)
        if _downloadCompleteCallback then
            _downloadCompleteCallback(nil, "Failed to start download: " .. (ret or "unknown"))
        end
        return false
    end

    return true
end

--[[
    取消下载
]]
function LLM.cancelDownload()
    if isAndroid() and _downloading then
        local luaj = getLuaj()
        luaj.callStaticMethod(
            CLASS_NAME,
            "cancelDownload",
            {},
            "()V"
        )
        _downloading = false
        print("[LLM] Download cancelled")
    end
end

-- ==================== 初始化相关 ====================

--[[
    初始化 LLM 服务

    @param config table 配置表
        - modelPath: string 模型文件路径（必填）
        - backend: string 后端类型 "CPU"/"GPU"/"NPU"，默认 "CPU"
        - onInit: function 初始化完成回调 function(success, error)

    @return boolean 是否成功启动初始化
]]
function LLM.init(config)
    if not isAndroid() then
        print("[LLM] Warning: LLM only works on Android platform")
        if config and config.onInit then
            config.onInit(false, "Not Android platform")
        end
        return false
    end

    if _initialized then
        print("[LLM] Already initialized")
        if config and config.onInit then
            config.onInit(true, nil)
        end
        return true
    end

    if _initializing then
        print("[LLM] Already initializing, queuing callback")
        if config and config.onInit then
            table.insert(_initCallbacks, config.onInit)
        end
        return true
    end

    local modelPath = config and config.modelPath
    if not modelPath or modelPath == "" then
        print("[LLM] Error: modelPath is required")
        if config and config.onInit then
            config.onInit(false, "modelPath is required")
        end
        return false
    end

    local backend = config and config.backend or "CPU"

    -- 注册回调
    if config and config.onInit then
        table.insert(_initCallbacks, config.onInit)
    end

    _initializing = true
    _lastError = nil

    local luaj = getLuaj()
    local ok, ret = luaj.callStaticMethod(
        CLASS_NAME,
        "init",
        {modelPath, backend},
        "(Ljava/lang/String;Ljava/lang/String;)Z"
    )

    if not ok then
        print("[LLM] Failed to call init:", ret)
        _initializing = false
        _initCallbacks = {}
        return false
    end

    print("[LLM] Initialization started, backend:", backend)
    return true
end

--[[
    初始化并自动下载模型（如果需要）
    流程：检查模型 → 下载（带进度） → 初始化引擎

    @param config table 配置表
        - modelUrl: string 模型下载地址（可选）
        - backend: string 后端类型，默认 "GPU"
        - onProgress: function 下载进度回调 function(percent)
        - onInit: function 初始化完成回调 function(success, error)

    @return boolean
]]
function LLM.initWithDownload(config)
    if not isAndroid() then
        print("[LLM] Warning: LLM only works on Android platform")
        if config and config.onInit then
            config.onInit(false, "Not Android platform")
        end
        return false
    end

    local modelPath = LLM.getModelPath()

    -- 如果模型已存在，直接初始化
    if LLM.isModelDownloaded() then
        print("[LLM] Model exists, initializing...")
        return LLM.init({
            modelPath = modelPath,
            backend = config and config.backend or "GPU",
            onInit = config and config.onInit
        })
    end

    -- 下载模型
    print("[LLM] Model not found, downloading...")
    return LLM.downloadModel({
        modelUrl = config and config.modelUrl,
        onProgress = config and config.onProgress,
        onComplete = function(filePath, error)
            if error then
                if config and config.onInit then
                    config.onInit(false, "Download failed: " .. error)
                end
            else
                -- 下载完成，初始化引擎
                LLM.init({
                    modelPath = filePath,
                    backend = config and config.backend or "GPU",
                    onInit = config and config.onInit
                })
            end
        end
    })
end

--[[
    检查 LLM 是否已初始化完成
]]
function LLM.isReady()
    if not isAndroid() then
        return false
    end

    if _initialized then
        return true
    end

    local luaj = getLuaj()
    local ok, ret = luaj.callStaticMethod(
        CLASS_NAME,
        "isReady",
        {},
        "()Z"
    )

    if ok and ret then
        _initialized = true
    end

    return _initialized
end

--[[
    获取最后的错误信息
]]
function LLM.getLastError()
    return _lastError
end

-- ==================== 聊天相关 ====================

--[[
    发送消息并获取完整响应（异步）

    @param prompt string 输入提示
    @param callback function 回调函数 function(response, error)

    @return boolean 是否成功发送
]]
function LLM.chat(prompt, callback)
    if not isAndroid() then
        if callback then
            callback(nil, "Not Android platform")
        end
        return false
    end

    if not LLM.isReady() then
        if callback then
            callback(nil, "LLM not initialized")
        end
        return false
    end

    local luaj = getLuaj()
    local callbackId = registerCallback(function(response, error)
        if callback then
            callback(response, error)
        end
    end)

    local ok, ret = luaj.callStaticMethod(
        CLASS_NAME,
        "chat",
        {prompt, callbackId},
        "(Ljava/lang/String;I)V"
    )

    if not ok then
        popCallback(callbackId)
        print("[LLM] Failed to send message:", ret)
        if callback then
            callback(nil, ret)
        end
        return false
    end

    return true
end

--[[
    发送消息并流式输出（异步）

    @param prompt string 输入提示
    @param onToken function 每个 token 的回调 function(token)
    @param onComplete function 完成回调 function(fullResponse)
    @param onError function 错误回调 function(errorMessage)

    @return boolean 是否成功发送
]]
function LLM.chatStream(prompt, onToken, onComplete, onError)
    if not isAndroid() then
        if onError then
            onError("Not Android platform")
        end
        return false
    end

    if not LLM.isReady() then
        if onError then
            onError("LLM not initialized")
        end
        return false
    end

    local luaj = getLuaj()

    local onTokenId = onToken and registerCallback(onToken) or 0
    local onCompleteId = onComplete and registerCallback(onComplete) or 0
    local onErrorId = onError and registerCallback(onError) or 0

    local ok, ret = luaj.callStaticMethod(
        CLASS_NAME,
        "chatWithCallback",
        {prompt, onTokenId, onCompleteId, onErrorId},
        "(Ljava/lang/String;III)V"
    )

    if not ok then
        if onTokenId > 0 then popCallback(onTokenId) end
        if onCompleteId > 0 then popCallback(onCompleteId) end
        if onErrorId > 0 then popCallback(onErrorId) end

        print("[LLM] Failed to send message:", ret)
        if onError then
            onError(ret)
        end
        return false
    end

    return true
end

-- ==================== 会话管理 ====================

--[[
    重置对话历史（开始新对话）
]]
function LLM.resetConversation()
    if not isAndroid() then
        return
    end

    local luaj = getLuaj()
    luaj.callStaticMethod(
        CLASS_NAME,
        "resetConversation",
        {},
        "()V"
    )

    print("[LLM] Conversation reset")
end

--[[
    释放资源
]]
function LLM.release()
    if not isAndroid() then
        return
    end

    local luaj = getLuaj()
    luaj.callStaticMethod(
        CLASS_NAME,
        "release",
        {},
        "()V"
    )

    _initialized = false
    _initializing = false
    _lastError = nil
    _callbackMap = {}
    _initCallbacks = {}
    _downloadProgressCallback = nil
    _downloadCompleteCallback = nil

    print("[LLM] Resources released")
end

return LLM
