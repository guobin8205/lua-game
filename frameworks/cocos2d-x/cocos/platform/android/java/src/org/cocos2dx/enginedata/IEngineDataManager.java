package org.cocos2dx.enginedata;

public interface IEngineDataManager {

    enum GameStatus {
        INVALID,
        LAUNCHING,
        LOADING,
        GAMING,
        SCENE_TRANSITION
    }

    interface OnSystemCommandListener {
        void onQueryFps(int[] expectedFps, int[] realFps);
        void onChangeContinuousFrameLostConfig(int cycle, int maxFrameMissed);
        void onChangeLowFpsConfig(int cycle, float maxFrameDx);
        void onChangeExpectedFps(int fps);
        void onChangeSpecialEffectLevel(int level);
        void onChangeMuteEnabled(boolean enabled);
    }
}
