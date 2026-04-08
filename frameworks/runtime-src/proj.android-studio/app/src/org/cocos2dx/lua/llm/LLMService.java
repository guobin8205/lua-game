package org.cocos2dx.lua.llm;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

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
    private static final Handler sHandler = new Handler(Looper.getMainLooper());

    // 下载取消标志
    private static volatile boolean sDownloadCancelled = false;

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
        LLMEngine.getInstance().sendMessageAsync(prompt, new LLMEngine.LLMCallback() {
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
        LLMEngine.getInstance().sendMessageAsync(prompt, new LLMEngine.LLMCallback() {
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

    // ==================== 模型下载相关 ====================

    /**
     * 获取模型存储目录的绝对路径
     *
     * @return 模型目录路径
     */
    public static String getModelDir() {
        Context context = Cocos2dxActivity.getContext();
        if (context == null) {
            return "/sdcard/Android/data/org.cocos2dx.hellolua/files/models";
        }
        File dir = new File(context.getExternalFilesDir(null), "models");
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return dir.getAbsolutePath();
    }

    /**
     * 流式下载模型文件（异步，不阻塞主线程）
     * 通过 Lua 全局回调报告进度和结果：
     * - __LLM_ON_DOWNLOAD_PROGRESS__ : 进度百分比（如 "42"）
     * - __LLM_ON_DOWNLOAD_COMPLETE__ : 文件路径（成功）或 "ERROR:msg"（失败）
     * - __LLM_ON_DOWNLOAD_ERROR__ : 错误信息
     *
     * @param urlString 下载 URL
     * @param destPath  目标文件绝对路径
     * @return true 表示开始下载，false 表示参数无效
     */
    public static boolean downloadModel(final String urlString, final String destPath) {
        if (urlString == null || urlString.isEmpty() || destPath == null || destPath.isEmpty()) {
            Log.e(TAG, "downloadModel: invalid parameters");
            return false;
        }

        Log.i(TAG, "Starting download: " + urlString);
        Log.i(TAG, "Destination: " + destPath);

        sDownloadCancelled = false;

        LLMEngine.getInstance().submitTask(() -> {
            File tempFile = new File(destPath + ".tmp");
            HttpURLConnection connection = null;

            try {
                // 如果已有临时文件，删除重新下载
                if (tempFile.exists()) {
                    tempFile.delete();
                }

                // 确保父目录存在
                File parentDir = tempFile.getParentFile();
                if (parentDir != null && !parentDir.exists()) {
                    parentDir.mkdirs();
                }

                URL url = new URL(urlString);
                connection = (HttpURLConnection) url.openConnection();
                connection.setConnectTimeout(30000);
                connection.setReadTimeout(60000);
                connection.setRequestMethod("GET");
                connection.connect();

                int responseCode = connection.getResponseCode();
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    notifyDownloadError("HTTP error: " + responseCode);
                    return;
                }

                long fileSize = connection.getContentLength();
                Log.i(TAG, "File size: " + (fileSize > 0 ? (fileSize / 1024 / 1024) + " MB" : "unknown"));

                InputStream is = connection.getInputStream();
                FileOutputStream fos = new FileOutputStream(tempFile);

                byte[] buffer = new byte[8192];
                long totalRead = 0;
                int bytesRead;
                int lastReportedPercent = -1;

                while ((bytesRead = is.read(buffer)) != -1) {
                    if (sDownloadCancelled) {
                        is.close();
                        fos.close();
                        tempFile.delete();
                        notifyDownloadError("Download cancelled");
                        return;
                    }

                    fos.write(buffer, 0, bytesRead);
                    totalRead += bytesRead;

                    // 计算并报告真实进度
                    if (fileSize > 0) {
                        int percent = (int) ((totalRead * 100) / fileSize);
                        if (percent != lastReportedPercent) {
                            lastReportedPercent = percent;
                            final int finalPercent = percent;
                            sHandler.post(() -> {
                                try {
                                    Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString(
                                        "__LLM_ON_DOWNLOAD_PROGRESS__",
                                        String.valueOf(finalPercent)
                                    );
                                } catch (Exception e) {
                                    Log.e(TAG, "Failed to report progress", e);
                                }
                            });
                        }
                    }
                }

                fos.flush();
                fos.close();
                is.close();

                // 重命名为最终文件
                File destFile = new File(destPath);
                if (destFile.exists()) {
                    destFile.delete();
                }
                boolean renamed = tempFile.renameTo(destFile);
                if (!renamed) {
                    notifyDownloadError("Failed to rename temp file");
                    return;
                }

                Log.i(TAG, "Download completed: " + destPath + ", size: " + destFile.length());

                // 通知下载完成
                sHandler.post(() -> {
                    try {
                        Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString(
                            "__LLM_ON_DOWNLOAD_COMPLETE__",
                            destPath
                        );
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to notify download complete", e);
                    }
                });

            } catch (final Exception e) {
                Log.e(TAG, "Download failed", e);
                // 清理临时文件
                if (tempFile.exists()) {
                    tempFile.delete();
                }
                notifyDownloadError(e.getMessage());
            } finally {
                if (connection != null) {
                    connection.disconnect();
                }
            }
        });

        return true;
    }

    /**
     * 取消正在进行的下载
     */
    public static void cancelDownload() {
        sDownloadCancelled = true;
        Log.i(TAG, "Download cancel requested");
    }

    /**
     * 通知 Lua 下载错误
     */
    private static void notifyDownloadError(final String errorMessage) {
        sHandler.post(() -> {
            try {
                Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString(
                    "__LLM_ON_DOWNLOAD_ERROR__",
                    errorMessage != null ? errorMessage : "Unknown error"
                );
            } catch (Exception e) {
                Log.e(TAG, "Failed to notify download error", e);
            }
        });
    }
}
