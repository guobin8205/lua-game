package org.cocos2dx.enginedata;

public class EngineDataManager {

    public boolean init(IEngineDataManager.OnSystemCommandListener listener) {
        return false;
    }

    public void destroy() {}

    public void pause() {}

    public void resume() {}

    public String getVendorInfo() {
        return "";
    }

    public void notifyGameStatus(IEngineDataManager.GameStatus status, int cpuLevel, int gpuLevel) {}

    public void notifyContinuousFrameLost(int cycle, int continuousFrameLostThreshold, int times) {}

    public void notifyLowFps(int cycle, float lowFpsThreshold, int lostFrameCount) {}

    public void notifyFpsChanged(float oldFps, float newFps) {}
}
