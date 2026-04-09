package org.cocos2dx.lua.llm;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.google.ai.edge.litertlm.Backend;
import com.google.ai.edge.litertlm.Content;
import com.google.ai.edge.litertlm.Contents;
import com.google.ai.edge.litertlm.Engine;
import com.google.ai.edge.litertlm.EngineConfig;
import com.google.ai.edge.litertlm.Conversation;
import com.google.ai.edge.litertlm.ConversationConfig;
import com.google.ai.edge.litertlm.Message;
import com.google.ai.edge.litertlm.MessageCallback;
import com.google.ai.edge.litertlm.SamplerConfig;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * LiteRT-LM 引擎封装类
 * 负责模型加载、初始化和推理
 */
public class LLMEngine {
    private static final String TAG = "LLMEngine";

    // 单例实例
    private static volatile LLMEngine sInstance;

    // LiteRT-LM 引擎
    private Engine mEngine;
    private Conversation mConversation;

    // 状态管理
    private volatile boolean mInitialized = false;
    private volatile boolean mInitializing = false;
    private String mLastError = null;

    // 线程池用于异步操作
    private final ExecutorService mExecutor = Executors.newSingleThreadExecutor();
    private final Handler mMainHandler = new Handler(Looper.getMainLooper());

    // 上下文引用
    private Context mContext;

    // 引擎配置
    private String mModelPath;
    private String mBackend = "CPU";

    private LLMEngine() {}

    /**
     * 获取单例实例
     */
    public static LLMEngine getInstance() {
        if (sInstance == null) {
            synchronized (LLMEngine.class) {
                if (sInstance == null) {
                    sInstance = new LLMEngine();
                }
            }
        }
        return sInstance;
    }

    /**
     * 初始化引擎（异步）
     */
    public void initializeAsync(Context context, String modelPath, String backend,
                                final InitCallback callback) {
        if (mInitialized) {
            if (callback != null) {
                mMainHandler.post(() -> callback.onSuccess());
            }
            return;
        }

        if (mInitializing) {
            if (callback != null) {
                mMainHandler.post(() -> callback.onError("Engine is already initializing"));
            }
            return;
        }

        mInitializing = true;
        mContext = context.getApplicationContext();
        mModelPath = modelPath;
        mBackend = backend != null ? backend : "CPU";

        mExecutor.execute(() -> {
            try {
                initializeInternal();
                mMainHandler.post(() -> {
                    mInitialized = true;
                    mInitializing = false;
                    mLastError = null;
                    Log.i(TAG, "Engine initialized successfully");
                    if (callback != null) {
                        callback.onSuccess();
                    }
                });
            } catch (final Exception e) {
                Log.e(TAG, "Failed to initialize engine", e);
                mMainHandler.post(() -> {
                    mInitializing = false;
                    mLastError = e.getMessage();
                    if (callback != null) {
                        callback.onError(e.getMessage());
                    }
                });
            }
        });
    }

    /**
     * 内部初始化逻辑 - 使用 LiteRT-LM SDK
     */
    private void initializeInternal() throws Exception {
        // 解析模型路径
        String absoluteModelPath = resolveModelPath(mModelPath);

        File modelFile = new File(absoluteModelPath);
        if (!modelFile.exists()) {
            throw new Exception("Model file not found: " + absoluteModelPath);
        }

        Log.i(TAG, "Loading model from: " + absoluteModelPath);
        Log.i(TAG, "Model size: " + (modelFile.length() / 1024 / 1024) + " MB");
        Log.i(TAG, "Backend: " + mBackend);

        // 创建 Backend (SDK 0.10.0: Backend 是 sealed class，用构造函数创建)
        Backend backend;
        switch (mBackend.toUpperCase()) {
            case "GPU":
                backend = new Backend.GPU();
                break;
            case "NPU":
                backend = new Backend.CPU();  // NPU 需要设备路径，降级为 CPU
                break;
            default:
                backend = new Backend.CPU();
                break;
        }

        // 创建 EngineConfig(path, textBackend, visionBackend, audioBackend, maxNumTokens, cacheDir)
        // 为多模态设置 visionBackend 和 audioBackend
        Backend visionBackend = null;
        try {
            visionBackend = new Backend.GPU();
            Log.i(TAG, "Using GPU vision backend");
        } catch (Exception e) {
            Log.w(TAG, "GPU vision backend failed, trying CPU", e);
            try {
                visionBackend = new Backend.CPU();
                Log.i(TAG, "Using CPU vision backend");
            } catch (Exception e2) {
                Log.w(TAG, "CPU vision backend also failed, vision disabled", e2);
            }
        }

        Backend audioBackend = null;
        try {
            audioBackend = new Backend.CPU();
            Log.i(TAG, "Using CPU audio backend");
        } catch (Exception e) {
            Log.w(TAG, "Audio backend creation failed", e);
        }

        EngineConfig config = new EngineConfig(absoluteModelPath, backend, visionBackend, audioBackend, null, null);

        // 创建并初始化 Engine
        mEngine = new Engine(config);
        mEngine.initialize();

        // 创建 ConversationConfig (SDK 0.10.0: systemInstruction, initialMessages, tools, samplerConfig)
        ConversationConfig convConfig = new ConversationConfig(
            Contents.Companion.of("你是一个有用的AI助手，请用中文回答问题。"),
            java.util.Collections.emptyList(),
            java.util.Collections.emptyList(),
            new SamplerConfig(64, 0.95, 0.8, 0)
        );
        mConversation = mEngine.createConversation(convConfig);

        Log.i(TAG, "Engine initialization completed");
    }

    /**
     * 解析模型路径
     */
    private String resolveModelPath(String modelPath) {
        // 如果是绝对路径，直接返回
        if (modelPath.startsWith("/")) {
            return modelPath;
        }

        // 检查是否在 files 目录
        File filesModel = new File(mContext.getFilesDir(), modelPath);
        if (filesModel.exists()) {
            return filesModel.getAbsolutePath();
        }

        // 检查是否在外部存储
        File externalModel = new File(mContext.getExternalFilesDir(null), modelPath);
        if (externalModel.exists()) {
            return externalModel.getAbsolutePath();
        }

        // 尝试从 assets 复制到内部存储
        try {
            return copyAssetToFiles(modelPath);
        } catch (Exception e) {
            Log.w(TAG, "Failed to copy from assets: " + e.getMessage());
        }

        return modelPath;
    }

    /**
     * 从 assets 复制文件到内部存储
     */
    private String copyAssetToFiles(String assetPath) throws Exception {
        File destFile = new File(mContext.getFilesDir(), assetPath);

        // 如果已存在，直接返回
        if (destFile.exists()) {
            return destFile.getAbsolutePath();
        }

        // 创建父目录
        destFile.getParentFile().mkdirs();

        // 复制文件
        InputStream is = mContext.getAssets().open(assetPath);
        FileOutputStream fos = new FileOutputStream(destFile);

        byte[] buffer = new byte[8192];
        int read;
        while ((read = is.read(buffer)) != -1) {
            fos.write(buffer, 0, read);
        }

        fos.flush();
        fos.close();
        is.close();

        Log.i(TAG, "Copied model from assets to: " + destFile.getAbsolutePath());
        return destFile.getAbsolutePath();
    }

    /**
     * 发送消息并获取完整响应（异步）
     */
    public void sendMessageAsync(String message, final LLMCallback callback) {
        if (!mInitialized || mConversation == null) {
            if (callback != null) {
                mMainHandler.post(() -> callback.onError("Engine not initialized"));
            }
            return;
        }

        mExecutor.execute(() -> {
            try {
                generateResponse(message, callback);
            } catch (final Exception e) {
                Log.e(TAG, "Failed to generate response", e);
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onError(e.getMessage());
                    }
                });
            }
        });
    }

    /**
     * 生成响应 - 使用 LiteRT-LM SDK 异步流式输出
     */
    private void generateResponse(String text, final LLMCallback callback) {
        final StringBuilder fullResponse = new StringBuilder();

        mConversation.sendMessageAsync(text, new MessageCallback() {
            @Override
            public void onMessage(Message msg) {
                final String token = msg.toString();
                fullResponse.append(token);
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onToken(token);
                    }
                });
            }

            @Override
            public void onDone() {
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onComplete(fullResponse.toString());
                    }
                });
            }

            @Override
            public void onError(Throwable throwable) {
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onError(throwable.getMessage());
                    }
                });
            }
        }, java.util.Collections.emptyMap());
    }

    /**
     * 发送多模态消息（图片/音频 + 文本），异步流式输出
     */
    public void sendMultimodalMessageAsync(String text, String imagePath, String audioPath,
                                            final LLMCallback callback) {
        if (!mInitialized || mConversation == null) {
            if (callback != null) {
                mMainHandler.post(() -> callback.onError("Engine not initialized"));
            }
            return;
        }

        mExecutor.execute(() -> {
            try {
                generateMultimodalResponse(text, imagePath, audioPath, callback);
            } catch (final Exception e) {
                Log.e(TAG, "Failed to generate multimodal response", e);
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onError(e.getMessage());
                    }
                });
            }
        });
    }

    /**
     * 生成多模态响应 - 图片/音频 + 文本
     */
    private void generateMultimodalResponse(String text, String imagePath, String audioPath,
                                             final LLMCallback callback) {
        final StringBuilder fullResponse = new StringBuilder();

        // 构建多模态 Contents
        Contents contents;
        String promptText = (text != null && !text.isEmpty()) ? text : "请分析以上内容。";

        boolean hasImage = imagePath != null && !imagePath.isEmpty() && new File(imagePath).exists();
        boolean hasAudio = audioPath != null && !audioPath.isEmpty() && new File(audioPath).exists();

        if (hasImage && hasAudio) {
            contents = Contents.Companion.of(
                new Content.ImageFile(imagePath),
                new Content.AudioFile(audioPath),
                new Content.Text(promptText)
            );
        } else if (hasImage) {
            contents = Contents.Companion.of(
                new Content.ImageFile(imagePath),
                new Content.Text(promptText)
            );
        } else if (hasAudio) {
            contents = Contents.Companion.of(
                new Content.AudioFile(audioPath),
                new Content.Text(promptText)
            );
        } else {
            contents = Contents.Companion.of(new Content.Text(promptText));
        }

        mConversation.sendMessageAsync(contents, new MessageCallback() {
            @Override
            public void onMessage(Message msg) {
                final String token = msg.toString();
                fullResponse.append(token);
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onToken(token);
                    }
                });
            }

            @Override
            public void onDone() {
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onComplete(fullResponse.toString());
                    }
                });
            }

            @Override
            public void onError(Throwable throwable) {
                mMainHandler.post(() -> {
                    if (callback != null) {
                        callback.onError(throwable.getMessage());
                    }
                });
            }
        }, java.util.Collections.emptyMap());
    }

    /**
     * 发送消息并获取完整响应（同步，阻塞）
     */
    public String sendMessageSync(String message) throws Exception {
        if (!mInitialized || mConversation == null) {
            throw new Exception("Engine not initialized");
        }

        final String[] result = new String[1];
        final Exception[] error = new Exception[1];
        final CountDownLatch latch = new CountDownLatch(1);

        sendMessageAsync(message, new LLMCallback() {
            @Override
            public void onToken(String token) {}

            @Override
            public void onComplete(String fullResponse) {
                result[0] = fullResponse;
                latch.countDown();
            }

            @Override
            public void onError(String errorMsg) {
                error[0] = new Exception(errorMsg);
                latch.countDown();
            }
        });

        boolean completed = latch.await(120, TimeUnit.SECONDS);

        if (!completed) {
            throw new Exception("Response timeout");
        }

        if (error[0] != null) {
            throw error[0];
        }

        return result[0];
    }

    /**
     * 重置会话（清除对话历史）
     */
    public void resetConversation() {
        mExecutor.execute(() -> {
            try {
                if (mEngine != null) {
                    if (mConversation != null) {
                        mConversation.close();
                    }
                    ConversationConfig convConfig = new ConversationConfig(
                        Contents.Companion.of("你是一个有用的AI助手，请用中文回答问题。"),
                        null,
                        null,
                        new SamplerConfig(64, 0.95, 0.8, 0)
                    );
                    mConversation = mEngine.createConversation(convConfig);
                    Log.i(TAG, "Conversation reset");
                }
            } catch (Exception e) {
                Log.e(TAG, "Failed to reset conversation", e);
            }
        });
    }

    /**
     * 检查是否已初始化
     */
    public boolean isInitialized() {
        return mInitialized;
    }

    /**
     * 提交异步任务到引擎线程池
     */
    public void submitTask(Runnable task) {
        mExecutor.execute(task);
    }

    /**
     * 获取最后的错误信息
     */
    public String getLastError() {
        return mLastError;
    }

    /**
     * 释放资源
     */
    public void release() {
        mExecutor.execute(() -> {
            try {
                if (mConversation != null) {
                    mConversation.close();
                    mConversation = null;
                }
                if (mEngine != null) {
                    mEngine.close();
                    mEngine = null;
                }
            } catch (Exception e) {
                Log.e(TAG, "Error releasing engine", e);
            }
            mInitialized = false;
            Log.i(TAG, "Engine released");
        });
    }

    /**
     * 初始化回调接口
     */
    public interface InitCallback {
        void onSuccess();
        void onError(String errorMessage);
    }

    /**
     * 消息回调接口（本地定义，避免与 SDK 的 MessageCallback 冲突）
     */
    public interface LLMCallback {
        void onToken(String token);
        void onComplete(String fullResponse);
        void onError(String errorMessage);
    }
}
