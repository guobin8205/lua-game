package org.cocos2dx.lua.llm;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxHelper;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class LLMService {
    private static final String TAG = "LLMService";
    private static final Handler sHandler = new Handler(Looper.getMainLooper());

    // 下载取消标志
    private static volatile boolean sDownloadCancelled = false;

    // ==================== 初始化相关 ====================

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

    public static boolean initWithDefault(String modelPath) {
        return init(modelPath, "CPU");
    }

    public static boolean isReady() {
        return LLMEngine.getInstance().isInitialized();
    }

    public static String getLastError() {
        return LLMEngine.getInstance().getLastError();
    }

    // ==================== 推理相关 ====================

    public static void chatWithCallback(String prompt,
                                        final int onTokenCallback,
                                        final int onCompleteCallback,
                                        final int onErrorCallback) {
        LLMEngine.getInstance().sendMessageAsync(prompt, new LLMEngine.LLMCallback() {
            private StringBuilder mFullResponse = new StringBuilder();

            @Override
            public void onToken(String token) {
                mFullResponse.append(token);

                if (onTokenCallback != 0) {
                    final String data = onTokenCallback + ":" + token;
                    runOnGLThread(() -> {
                        try {
                            Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_TOKEN__", data);
                        } catch (Exception e) {
                            Log.e(TAG, "Failed to call Lua onToken callback", e);
                        }
                    });
                }
            }

            @Override
            public void onComplete(String fullResponse) {
                if (onCompleteCallback != 0) {
                    final String data = onCompleteCallback + ":" + fullResponse;
                    runOnGLThread(() -> {
                        try {
                            Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_COMPLETE__", data);
                        } catch (Exception e) {
                            Log.e(TAG, "Failed to call Lua onComplete callback", e);
                        }
                    });
                }
            }

            @Override
            public void onError(String errorMessage) {
                if (onErrorCallback != 0) {
                    final String data = onErrorCallback + ":" + errorMessage;
                    runOnGLThread(() -> {
                        try {
                            Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_ERROR__", data);
                        } catch (Exception e) {
                            Log.e(TAG, "Failed to call Lua onError callback", e);
                        }
                    });
                }
            }
        });
    }

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
                    final String data = callbackId + ":" + fullResponse;
                    runOnGLThread(() -> {
                        try {
                            Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_CHAT__", data);
                        } catch (Exception e) {
                            Log.e(TAG, "Failed to call Lua chat callback", e);
                        }
                    });
                }
            }

            @Override
            public void onError(String errorMessage) {
                if (callbackId != 0) {
                    final String data = callbackId + ":ERROR:" + errorMessage;
                    runOnGLThread(() -> {
                        try {
                            Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_CHAT__", data);
                        } catch (Exception e) {
                            Log.e(TAG, "Failed to call Lua chat error callback", e);
                        }
                    });
                }
            }
        });
    }

    public static String chatSync(String prompt) {
        try {
            return LLMEngine.getInstance().sendMessageSync(prompt);
        } catch (Exception e) {
            Log.e(TAG, "Failed to send message sync", e);
            return "ERROR:" + e.getMessage();
        }
    }

    // ==================== 文件操作 ====================

    public static boolean checkModelExists(String filePath) {
        if (filePath == null || filePath.isEmpty()) {
            return false;
        }
        File file = new File(filePath);
        return file.exists() && file.length() > 0;
    }

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

    public static boolean saveFile(String filePath, byte[] data) {
        if (filePath == null || data == null) {
            Log.e(TAG, "saveFile: invalid parameters");
            return false;
        }

        File file = new File(filePath);
        File parentDir = file.getParentFile();

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

    public static void resetConversation() {
        LLMEngine.getInstance().resetConversation();
        Log.i(TAG, "Conversation reset");
    }

    public static void release() {
        LLMEngine.getInstance().release();
        Log.i(TAG, "Resources released");
    }

    // ==================== 内部辅助方法 ====================

    /**
     * 在 GL 线程执行 Runnable（Lua bridge 必须在 GL 线程调用）
     */
    private static void runOnGLThread(Runnable r) {
        Cocos2dxHelper.runOnGLThread(r);
    }

    private static void notifyLuaInitResult(final boolean success, final String errorMessage) {
        final String result = success ? "SUCCESS" : "ERROR:" + errorMessage;
        runOnGLThread(() -> {
            try {
                Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__LLM_ON_INIT__", result);
            } catch (Exception e) {
                Log.e(TAG, "Failed to notify Lua init result", e);
            }
        });
    }

    // ==================== 模型下载相关 ====================

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
                if (tempFile.exists()) {
                    tempFile.delete();
                }

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

                    if (fileSize > 0) {
                        int percent = (int) ((totalRead * 100) / fileSize);
                        if (percent != lastReportedPercent) {
                            lastReportedPercent = percent;
                            final int finalPercent = percent;
                            runOnGLThread(() -> {
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

                runOnGLThread(() -> {
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

    public static void cancelDownload() {
        sDownloadCancelled = true;
        Log.i(TAG, "Download cancel requested");
    }

    private static void notifyDownloadError(final String errorMessage) {
        runOnGLThread(() -> {
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
