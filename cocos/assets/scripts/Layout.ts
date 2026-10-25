import { director, view, screen, sys, ResolutionPolicy, Vec2 } from 'cc';

type WechatWindow = { windowWidth: number; windowHeight: number; safeArea?: { top: number; bottom: number } };
type WechatLayout = { getWindowInfo(): WechatWindow; getMenuButtonBoundingClientRect(): { bottom: number } };

export interface LayoutMetrics { width: number; height: number; scale: number; wide: boolean; nearSquare: boolean; top: number; bottom: number; }

// Match the approved 390px portrait view in screen pixels, independent of the board's design resolution.
export function fixedUiUnit(scale: number) { return scale * 390 / 720; }
export const PACK_SCREEN_SIZE = 64;
export const INSPECTOR_SCREEN_SIZE = 160 * .8;
export const INSPECTOR_CONTENT_SCALE = .8;
// Shared screen-pixel size for click hints and founder speech, independent of list/header text.
export const HINT_SCREEN_SIZE = 12;

type DisplayOrientation = 'landscape' | 'portrait';
let displayOrientation: DisplayOrientation | null = null;
let orientationLoaded = false;
let frameRotated = false;
let layoutWidth = 1, layoutHeight = 1;
export function canSetDisplayOrientation() { return typeof document !== 'undefined' && !!document.getElementById('GameDiv'); }
export function getDisplayOrientation(): DisplayOrientation { return displayOrientation || (layoutWidth > layoutHeight ? 'landscape' : 'portrait'); }
export function setDisplayOrientation(value: DisplayOrientation) {
    displayOrientation = value;
    try { sys.localStorage.setItem('startx.display-orientation', value); } catch { /* Keep the session choice. */ }
}

/** CSS rotation keeps the canvas full size; convert its input back into logical UI coordinates. */
export function orientUiPoint(point: Vec2) {
    return frameRotated ? new Vec2(layoutWidth - point.y, point.x) : point;
}

export function measureLayout(): LayoutMetrics {
    if (!orientationLoaded) {
        orientationLoaded = true;
        try {
            const saved = sys.localStorage.getItem('startx.display-orientation');
            if (saved === 'landscape' || saved === 'portrait') displayOrientation = saved;
        } catch { /* Follow the window until a mode is selected. */ }
    }
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
    const frame = typeof document !== 'undefined' ? document.getElementById('GameDiv') : null;
    frameRotated = !!frame && !!displayOrientation && (displayOrientation === 'landscape' ? cw < ch : cw > ch);
    if (frame) {
        const physicalWidth = cw;
        if (frameRotated) [cw, ch] = [ch, cw];
        // Override the web template's full-window sizes when the selected direction differs.
        for (const [key, value] of Object.entries({ width: cw + 'px', height: ch + 'px', left: frameRotated ? physicalWidth + 'px' : '0px',
            top: '0px', right: 'auto', bottom: 'auto', margin: '0px', transform: frameRotated ? 'rotate(90deg)' : 'none', transformOrigin: '0 0' })) {
            frame.style.setProperty(key.replace(/[A-Z]/g, letter => '-' + letter.toLowerCase()), value, 'important');
        }
        if (frameRotated) topInset = bottomInset = 0;
    }
    const nearSquare = cw >= 600 && cw / ch >= .8 && cw / ch <= 1.3;
    const wide = cw >= 960 && cw > ch || nearSquare;
    const scale = wide ? Math.max(1, 900 / ch) : 720 / cw;
    const width = cw * scale, height = ch * scale;
    layoutWidth = width; layoutHeight = height;
    view.setDesignResolutionSize(width, height, ResolutionPolicy.EXACT_FIT);
    if (frame && director.root) {
        const size = screen.resolution, target = director.root.mainWindow;
        if (target && (target.width !== size.width || target.height !== size.height)) director.root.resize(size.width, size.height);
    }
    return { width, height, scale, wide, nearSquare, top: topInset * scale, bottom: bottomInset * scale };
}
