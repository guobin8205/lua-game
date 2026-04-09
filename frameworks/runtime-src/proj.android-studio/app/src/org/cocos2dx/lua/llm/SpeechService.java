package org.cocos2dx.lua.llm;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxHelper;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * 录音服务：录制 WAV 格式音频发送给大模型分析
 */
public class SpeechService {
    private static final String TAG = "SpeechService";
    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNEL = AudioFormat.CHANNEL_IN_MONO;
    private static final int ENCODING = AudioFormat.ENCODING_PCM_16BIT;
    private static final int BUFFER_SIZE = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING) * 2;

    private static AudioRecord sAudioRecord;
    private static boolean sIsRecording = false;
    private static String sCurrentAudioPath = null;
    private static Thread sRecordingThread;
    private static final Handler sHandler = new Handler(Looper.getMainLooper());

    // ==================== 开始录音 ====================

    public static boolean startListening() {
        if (sIsRecording) return false;

        final Context ctx = Cocos2dxActivity.getContext();
        if (ctx == null) return false;

        try {
            File audioDir = new File(ctx.getFilesDir(), "chat_audio");
            if (!audioDir.exists()) audioDir.mkdirs();

            sCurrentAudioPath = new File(audioDir, "audio_" + System.currentTimeMillis() + ".wav").getAbsolutePath();

            sAudioRecord = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL,
                ENCODING,
                BUFFER_SIZE
            );

            if (sAudioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord not initialized");
                notifyResult(null, "AudioRecord initialization failed");
                return false;
            }

            sAudioRecord.startRecording();
            sIsRecording = true;

            // 录音线程
            sRecordingThread = new Thread(() -> {
                try {
                    recordAudio();
                } catch (Exception e) {
                    Log.e(TAG, "Recording error", e);
                    sHandler.post(() -> {
                        sIsRecording = false;
                        notifyResult(null, "Recording error: " + e.getMessage());
                    });
                }
            });
            sRecordingThread.start();

            Log.i(TAG, "Recording started: " + sCurrentAudioPath);

            Cocos2dxHelper.runOnGLThread(() -> {
                try {
                    Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString(
                        "__SPEECH_ON_START__", "OK");
                } catch (Exception e) { /* ignore */ }
            });
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to start recording", e);
            sIsRecording = false;
            notifyResult(null, "Failed to start recording: " + e.getMessage());
            return false;
        }
    }

    private static void recordAudio() throws IOException {
        ByteBuffer pcmBuffer = ByteBuffer.allocate(1024 * 1024); // 1MB buffer
        pcmBuffer.order(ByteOrder.LITTLE_ENDIAN);
        byte[] readBuffer = new byte[BUFFER_SIZE];

        while (sIsRecording) {
            int read = sAudioRecord.read(readBuffer, 0, readBuffer.length);
            if (read > 0) {
                pcmBuffer.put(readBuffer, 0, read);
            } else {
                break;
            }
        }

        sAudioRecord.stop();
        sAudioRecord.release();
        sAudioRecord = null;

        // 写入 WAV 文件
        int dataSize = pcmBuffer.position();
        byte[] pcmData = new byte[dataSize];
        pcmBuffer.flip();
        pcmBuffer.get(pcmData);

        writeWavFile(sCurrentAudioPath, pcmData);

        final String path = sCurrentAudioPath;
        sHandler.post(() -> {
            sIsRecording = false;
            Log.i(TAG, "Recording stopped: " + path + ", size: " + pcmData.length);
            notifyResult(path, null);
        });
    }

    private static void writeWavFile(String path, byte[] pcmData) throws IOException {
        int channels = 1;
        int bitsPerSample = 16;
        int byteRate = SAMPLE_RATE * channels * bitsPerSample / 8;
        int blockAlign = channels * bitsPerSample / 8;

        ByteBuffer wavBuffer = ByteBuffer.allocate(44 + pcmData.length);
        wavBuffer.order(ByteOrder.LITTLE_ENDIAN);

        // RIFF header
        wavBuffer.put("RIFF".getBytes());
        wavBuffer.putInt(36 + pcmData.length);
        wavBuffer.put("WAVE".getBytes());

        // fmt chunk
        wavBuffer.put("fmt ".getBytes());
        wavBuffer.putInt(16); // chunk size
        wavBuffer.putShort((short) 1); // PCM format
        wavBuffer.putShort((short) channels);
        wavBuffer.putInt(SAMPLE_RATE);
        wavBuffer.putInt(byteRate);
        wavBuffer.putShort((short) blockAlign);
        wavBuffer.putShort((short) bitsPerSample);

        // data chunk
        wavBuffer.put("data".getBytes());
        wavBuffer.putInt(pcmData.length);
        wavBuffer.put(pcmData);

        try (FileOutputStream fos = new FileOutputStream(path)) {
            fos.write(wavBuffer.array());
            fos.flush();
        }
    }

    // ==================== 停止录音 ====================

    public static boolean stopListening() {
        if (!sIsRecording) return false;
        sIsRecording = false;
        // 录音线程会自动处理停止并回调
        return true;
    }

    // ==================== 状态查询 ====================

    public static boolean isRecording() {
        return sIsRecording;
    }

    // ==================== 销毁 ====================

    public static void destroy() {
        sIsRecording = false;
        if (sAudioRecord != null) {
            try {
                sAudioRecord.stop();
                sAudioRecord.release();
            } catch (Exception e) {
                Log.e(TAG, "Failed to release AudioRecord", e);
            }
            sAudioRecord = null;
        }
        if (sRecordingThread != null) {
            try {
                sRecordingThread.join(1000);
            } catch (InterruptedException ignored) {}
            sRecordingThread = null;
        }
    }

    // ==================== Lua 回调 ====================

    private static void notifyResult(final String audioPath, final String error) {
        final String result = (error != null) ? "ERROR:" + error : audioPath;
        Cocos2dxHelper.runOnGLThread(() -> {
            try {
                Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString(
                    "__SPEECH_ON_RESULT__", result);
            } catch (Exception e) {
                Log.e(TAG, "Failed to notify Lua speech result", e);
            }
        });
    }
}
