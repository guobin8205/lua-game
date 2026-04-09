/****************************************************************************
Copyright (c) 2008-2010 Ricardo Quesada
Copyright (c) 2010-2016 cocos2d-x.org
Copyright (c) 2013-2017 Chukong Technologies Inc.

http://www.cocos2d-x.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
****************************************************************************/
package org.cocos2dx.lua;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;
import org.cocos2dx.lib.Cocos2dxHelper;
import android.util.Log;
import android.content.Intent;

import org.cocos2dx.lua.llm.MediaService;
import org.cocos2dx.lua.llm.SpeechService;


public class AppActivity extends Cocos2dxActivity {

    private boolean mFirstResume = true;
    private static final int PERM_REQ_AUDIO = 2001;
    private static final int PERM_REQ_CAMERA = 2002;
    private static final int PERM_REQ_STORAGE = 2003;
    private static int sPermCallbackId = 0;

    @Override
    protected void onResume() {
        super.onResume();
        if (mFirstResume) {
            mFirstResume = false;
            return;
        }
        this.runOnGLThread(new Runnable() {
            @Override
            public void run() {
                try {
                    Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__ON_APP_RESUME__", "");
                } catch (Exception e) {
                    Log.w("AppActivity", "Failed to call __ON_APP_RESUME__: " + e.getMessage());
                }
            }
        });
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        MediaService.handleActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        SpeechService.destroy();
    }

    // ==================== 权限请求 ====================

    public static void requestAudioPermission(int callbackId) {
        sPermCallbackId = callbackId;
        final AppActivity activity = (AppActivity) Cocos2dxActivity.getContext();
        if (activity == null) return;
        if (activity.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            notifyPermResult(true);
        } else {
            activity.requestPermissions(
                new String[]{android.Manifest.permission.RECORD_AUDIO}, PERM_REQ_AUDIO);
        }
    }

    public static void requestCameraPermission(int callbackId) {
        sPermCallbackId = callbackId;
        final AppActivity activity = (AppActivity) Cocos2dxActivity.getContext();
        if (activity == null) return;
        if (activity.checkSelfPermission(android.Manifest.permission.CAMERA)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            notifyPermResult(true);
        } else {
            activity.requestPermissions(
                new String[]{android.Manifest.permission.CAMERA}, PERM_REQ_CAMERA);
        }
    }

    public static void requestStoragePermission(int callbackId) {
        sPermCallbackId = callbackId;
        final AppActivity activity = (AppActivity) Cocos2dxActivity.getContext();
        if (activity == null) return;
        if (activity.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            notifyPermResult(true);
        } else {
            activity.requestPermissions(
                new String[]{android.Manifest.permission.READ_EXTERNAL_STORAGE}, PERM_REQ_STORAGE);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode < PERM_REQ_AUDIO || requestCode > PERM_REQ_STORAGE) {
            return; // 不是我们的权限请求，忽略
        }
        boolean granted = grantResults.length > 0
            && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED;
        notifyPermResult(granted);
    }

    private static void notifyPermResult(final boolean granted) {
        final int cbId = sPermCallbackId;
        Cocos2dxHelper.runOnGLThread(() -> {
            try {
                String result = cbId + ":" + (granted ? "GRANTED" : "DENIED");
                Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString("__ON_PERM_RESULT__", result);
            } catch (Exception e) {
                Log.w("AppActivity", "Failed to notify perm result: " + e.getMessage());
            }
        });
    }
}
