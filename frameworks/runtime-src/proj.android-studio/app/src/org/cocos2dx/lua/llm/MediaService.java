package org.cocos2dx.lua.llm;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxHelper;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * 图片服务：拍照、相册选图、图片压缩保存
 */
public class MediaService {
    private static final String TAG = "MediaService";
    private static final int REQ_TAKE_PHOTO = 1001;
    private static final int REQ_PICK_IMAGE = 1002;
    private static final int MAX_IMAGE_DIMENSION = 1024;
    private static final int COMPRESS_QUALITY = 80;

    private static Uri sCameraImageUri;
    private static final Handler sHandler = new Handler(Looper.getMainLooper());

    // ==================== 拍照 ====================

    public static boolean takePhoto() {
        final Activity activity = (Activity) Cocos2dxActivity.getContext();
        if (activity == null) return false;

        sHandler.post(() -> {
            try {
                File photoFile = createTempImageFile(activity);
                sCameraImageUri = androidx.core.content.FileProvider.getUriForFile(
                    activity,
                    activity.getPackageName() + ".fileprovider",
                    photoFile
                );
                Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                intent.putExtra(MediaStore.EXTRA_OUTPUT, sCameraImageUri);
                intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                activity.startActivityForResult(intent, REQ_TAKE_PHOTO);
            } catch (Exception e) {
                Log.e(TAG, "Failed to take photo", e);
                notifyImageResult(null, "Failed to start camera: " + e.getMessage());
            }
        });
        return true;
    }

    // ==================== 相册选图 ====================

    public static boolean pickImage() {
        final Activity activity = (Activity) Cocos2dxActivity.getContext();
        if (activity == null) return false;

        sHandler.post(() -> {
            try {
                Intent intent = new Intent(Intent.ACTION_PICK);
                intent.setType("image/*");
                activity.startActivityForResult(intent, REQ_PICK_IMAGE);
            } catch (Exception e) {
                Log.e(TAG, "Failed to pick image", e);
                notifyImageResult(null, "Failed to open gallery: " + e.getMessage());
            }
        });
        return true;
    }

    // ==================== Activity Result ====================

    public static boolean handleActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_TAKE_PHOTO) {
            if (resultCode == Activity.RESULT_OK && sCameraImageUri != null) {
                String path = processAndSaveImage(sCameraImageUri);
                if (path != null) {
                    notifyImageResult(path, null);
                } else {
                    notifyImageResult(null, "Failed to process photo");
                }
            } else {
                notifyImageResult(null, "Camera cancelled or failed");
            }
            sCameraImageUri = null;
            return true;
        }
        if (requestCode == REQ_PICK_IMAGE) {
            if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null) {
                String path = processAndSaveImage(data.getData());
                if (path != null) {
                    notifyImageResult(path, null);
                } else {
                    notifyImageResult(null, "Failed to process image");
                }
            } else {
                notifyImageResult(null, "Gallery cancelled or failed");
            }
            return true;
        }
        return false;
    }

    // ==================== 图片处理 ====================

    private static String processAndSaveImage(Uri uri) {
        try {
            Context ctx = Cocos2dxActivity.getContext();

            // 先获取图片尺寸
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inJustDecodeBounds = true;
            try (InputStream is = ctx.getContentResolver().openInputStream(uri)) {
                BitmapFactory.decodeStream(is, null, opts);
            }

            // 计算 inSampleSize
            int sampleSize = 1;
            if (opts.outWidth > MAX_IMAGE_DIMENSION || opts.outHeight > MAX_IMAGE_DIMENSION) {
                sampleSize = Math.max(opts.outWidth, opts.outHeight) / MAX_IMAGE_DIMENSION;
            }

            // 解码缩放后的图片
            opts.inJustDecodeBounds = false;
            opts.inSampleSize = sampleSize;
            Bitmap bitmap;
            try (InputStream is = ctx.getContentResolver().openInputStream(uri)) {
                bitmap = BitmapFactory.decodeStream(is, null, opts);
            }

            if (bitmap == null) return null;

            // 保存到 app 私有目录
            File imageDir = new File(ctx.getFilesDir(), "chat_images");
            if (!imageDir.exists()) imageDir.mkdirs();

            String filename = "img_" + System.currentTimeMillis() + ".jpg";
            File outputFile = new File(imageDir, filename);

            try (FileOutputStream fos = new FileOutputStream(outputFile)) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, COMPRESS_QUALITY, fos);
                fos.flush();
            }
            bitmap.recycle();

            return outputFile.getAbsolutePath();
        } catch (Exception e) {
            Log.e(TAG, "Failed to process image", e);
            return null;
        }
    }

    private static File createTempImageFile(Context ctx) throws Exception {
        File imageDir = new File(ctx.getFilesDir(), "chat_images");
        if (!imageDir.exists()) imageDir.mkdirs();
        return File.createTempFile("camera_", ".jpg", imageDir);
    }

    // ==================== Lua 回调 ====================

    private static void notifyImageResult(final String imagePath, final String error) {
        final String result = (error != null) ? "ERROR:" + error : imagePath;
        Cocos2dxHelper.runOnGLThread(() -> {
            try {
                Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__MEDIA_ON_IMAGE__", result);
            } catch (Exception e) {
                Log.e(TAG, "Failed to notify Lua image result", e);
            }
        });
    }
}
