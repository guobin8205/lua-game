package org.cocos2dx.lua.llm;

import android.content.Context;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

/**
 * LLM 服务类 - 提供 Lua 可调用的静态方法
 * 通过 LuaJavaBridge 暴露给 Lua 层
 *
 * Lua 调用示例:
 * local luaj = require("cocos.cocos2d.luaj")
 * local className = "org/cocos2dx/lua/llm/LLMService"
 *
 * -- 初始化
 * luaj.callStaticMethod(className, "init", {modelPath, backend}, "(Ljava/lang/String;Ljava/lang/String;)Z")
 *
 * -- 检查状态
 * luaj.callStaticMethod(className, "isReady", {}, "()Z")
 *
 * -- 发送消息
 * luaj.callStaticMethod(className, "chat", {prompt, callbackId}, "(Ljava/lang/String;I)V")
 */
public class LLMService {
    private static final String TAG = "LLMService";

    // ==================== 初始化相关 ====================

    /**
     * 初始化 LLM 服务
     *
     * @param modelPath 模型文件路径
     * @param backend 后端类型：CPU, GPU, NPU
     * @return true 表示开始初始化（异步），false 表示失败
     */
    public static boolean init(String modelPath, String backend) {
        Context context = Cocos2dxActivity.getContext();
        if (context == null) {
            Log.e(TAG, "Context is null");
            return false;
        }

        LLMEngine.getInstance().initializeAsync(
            context,
            modelPath,
            backend,
            new LLMEngine.InitCallback() {
                @Override
                public void onSuccess() {
                    notifyLuaInitResult(true, null);
                }

                @Override
                public void onError(String errorMessage) {
                    notifyLuaInitResult(false, errorMessage);
                }
            }
        );

        return true;
    }

    /**
     * 使用默认配置初始化（CPU 后端）
     *
     * @param modelPath 模型文件路径
     * @return true 表示开始初始化
     */
    public static boolean initWithDefault(String modelPath) {
        return init(modelPath, "CPU");
    }

    /**
     * 检查是否已初始化完成
     *
     * @return true 已初始化，false 未初始化
     */
    public static boolean isReady() {
        return LLMEngine.getInstance().isInitialized();
    }

    /**
     * 获取最后的错误信息
     *
     * @return 错误信息字符串
     */
    public static String getLastError() {
        return LLMEngine.getInstance().getLastError();
    }

    // ==================== 推理相关 ====================

    /**
     * 发送消息并异步回调（流式输出）
     *
     * @param prompt 输入提示
     * @param onTokenCallback 每个 token 的回调函数 ID
     * @param onCompleteCallback 完成时的回调函数 ID
     * @param onErrorCallback 错误时的回调函数 ID
     */
    public static void chatWithCallback(String prompt,
                                        final int onTokenCallback,
                                        final int onCompleteCallback,
                                        final int onErrorCallback) {
        LLMEngine.getInstance().sendMessageAsync(prompt, new LLMEngine.MessageCallback() {
            private StringBuilder mFullResponse = new StringBuilder();

            @Override
            public void onToken(String token) {
                mFullResponse.append(token);

                // 流式回调到 Lua
                if (onTokenCallback != 0) {
                    try {
                        // 格式: "callbackId:token"
                        String data = onTokenCallback + ":" + token;
                        Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_TOKEN__", data);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to call Lua onToken callback", e);
                    }
                }
            }

            @Override
            public void onComplete(String fullResponse) {
                // 完成回调到 Lua
                if (onCompleteCallback != 0) {
                    try {
                        // 格式: "callbackId:response"
                        String data = onCompleteCallback + ":" + fullResponse;
                        Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_COMPLETE__", data);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to call Lua onComplete callback", e);
                    }
                }
            }

            @Override
            public void onError(String errorMessage) {
                // 错误回调到 Lua
                if (onErrorCallback != 0) {
                    try {
                        // 格式: "callbackId:errorMessage"
                        String data = onErrorCallback + ":" + errorMessage;
                        Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_ERROR__", data);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to call Lua onError callback", e);
                    }
                }
            }
        });
    }

    /**
     * 简化的聊天接口 - 只回调完整结果
     *
     * @param prompt 输入提示
     * @param callbackId 回调函数 ID
     */
    public static void chat(String prompt, final int callbackId) {
        LLMEngine.getInstance().sendMessageAsync(prompt, new LLMEngine.MessageCallback() {
            private StringBuilder mFullResponse = new StringBuilder();

            @Override
            public void onToken(String token) {
                mFullResponse.append(token);
            }

            @Override
            public void onComplete(String fullResponse) {
                if (callbackId != 0) {
                    try {
                        // 格式: "callbackId:response"
                        String data = callbackId + ":" + fullResponse;
                        Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_CHAT__", data);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to call Lua chat callback", e);
                    }
                }
            }

            @Override
            public void onError(String errorMessage) {
                if (callbackId != 0) {
                    try {
                        // 格式: "callbackId:ERROR:errorMessage"
                        String data = callbackId + ":ERROR:" + errorMessage;
                        Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_CHAT__", data);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to call Lua chat error callback", e);
                    }
                }
            }
        });
    }

    /**
     * 同步聊天（阻塞调用，不推荐在主线程使用）
     *
     * @param prompt 输入提示
     * @return 完整响应文本，或错误信息（以 "ERROR:" 开头）
     */
    public static String chatSync(String prompt) {
        try {
            return LLMEngine.getInstance().sendMessageSync(prompt);
        } catch (Exception e) {
            Log.e(TAG, "Failed to send message sync", e);
            return "ERROR:" + e.getMessage();
        }
    }

    // ==================== 文件操作（供 Lua 层下载使用） ====================

    /**
     * 检查模型文件是否存在
     *
     * @param filePath 文件路径
     * @return true 存在，false 不存在
     */
    public static boolean checkModelExists(String filePath) {
        if (filePath == null || filePath.isEmpty()) {
            return false;
        }
        File file = new File(filePath);
        return file.exists() && file.length() > 0;
    }

    /**
     * 创建目录（包括父目录）
     *
     * @param dirPath 目录路径
     */
    public static void createDirs(String dirPath) {
        if (dirPath == null || dirPath.isEmpty()) {
            return;
        }
        File dir = new File(dirPath);
        if (!dir.exists()) {
            boolean created = dir.mkdirs();
            Log.i(TAG, "Create dirs " + dirPath + ": " + created);
        }
    }

    /**
     * 保存下载数据到文件
     *
     * @param filePath 文件路径
     * @param data 字节数据
     * @return true 成功，false 失败
     */
    public static boolean saveFile(String filePath, byte[] data) {
        if (filePath == null || data == null) {
            Log.e(TAG, "saveFile: invalid parameters");
            return false;
        }

        File file = new File(filePath);
        File parentDir = file.getParentFile();

        // 确保父目录存在
        if (parentDir != null && !parentDir.exists()) {
            if (!parentDir.mkdirs()) {
                Log.e(TAG, "Failed to create parent dir: " + parentDir);
                return false;
            }
        }

        try (FileOutputStream fos = new FileOutputStream(file)) {
            fos.write(data);
            fos.flush();
            Log.i(TAG, "File saved: " + filePath + ", size: " + data.length);
            return true;
        } catch (IOException e) {
            Log.e(TAG, "Failed to save file: " + filePath, e);
            return false;
        }
    }

    /**
     * 获取模型文件大小
     *
     * @param filePath 文件路径
     * @return 文件大小（字节），不存在返回 -1
     */
    public static long getFileSize(String filePath) {
        if (filePath == null || filePath.isEmpty()) {
            return -1;
        }
        File file = new File(filePath);
        if (file.exists()) {
            return file.length();
        }
        return -1;
    }

    // ==================== 会话管理 ====================

    /**
     * 重置对话历史
     */
    public static void resetConversation() {
        LLMEngine.getInstance().resetConversation();
        Log.i(TAG, "Conversation reset");
    }

    /**
     * 释放资源
     */
    public static void release() {
        LLMEngine.getInstance().release();
        Log.i(TAG, "Resources released");
    }

    // ==================== 内部辅助方法 ====================

    /**
     * 通知 Lua 初始化结果
     */
    private static void notifyLuaInitResult(final boolean success, final String errorMessage) {
        try {
            String result = success ? "SUCCESS" : "ERROR:" + errorMessage;
            Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_INIT__", result);
        } catch (Exception e) {
            Log.e(TAG, "Failed to notify Lua init result", e);
        }
    }
}
