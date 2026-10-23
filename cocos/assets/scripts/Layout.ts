import { view, screen, sys, ResolutionPolicy } from 'cc';

type WechatWindow = { windowWidth: number; windowHeight: number; safeArea?: { top: number; bottom: number } };
type WechatLayout = { getWindowInfo(): WechatWindow; getMenuButtonBoundingClientRect(): { bottom: number } };

export interface LayoutMetrics { width: number; height: number; scale: number; wide: boolean; nearSquare: boolean; top: number; bottom: number; }

export function measureLayout(): LayoutMetrics {
    const wx = (globalThis as unknown as { wx?: WechatLayout }).wx;
    let cw = screen.windowSize.width, ch = screen.windowSize.height;
    if (typeof window !== 'undefined' && window.innerWidth) { cw = window.innerWidth; ch = window.innerHeight; }
    let topInset = 0, bottomInset = 0;
    if (wx?.getWindowInfo) {
        const info = wx.getWindowInfo(); cw = info.windowWidth; ch = info.windowHeight;
        topInset = Math.max(info.safeArea?.top ?? 0, wx.getMenuButtonBoundingClientRect?.().bottom ?? 0) + 12;
        bottomInset = Math.max(16, ch - (info.safeArea?.bottom ?? ch));
    } else if (sys.isMobile) {
        // Both rectangles are in design coordinates, independent of the phone's pixel density.
        const safe = sys.getSafeAreaRect(false);
        const size = view.getVisibleSize();
        topInset = Math.max(0, (size.height - safe.y - safe.height) * ch / size.height);
        bottomInset = Math.max(0, safe.y * ch / size.height);
    }
    const nearSquare = cw >= 600 && cw / ch >= .8 && cw / ch <= 1.3;
    const wide = cw >= 960 && cw > ch || nearSquare;
    const scale = wide ? Math.max(1, 900 / ch) : 720 / cw;
    const width = cw * scale, height = ch * scale;
    view.setDesignResolutionSize(width, height, ResolutionPolicy.EXACT_FIT);
    return { width, height, scale, wide, nearSquare, top: topInset * scale, bottom: bottomInset * scale };
}
