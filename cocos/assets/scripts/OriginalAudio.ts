import { _decorator, AssetManager, AudioClip, AudioSource, Component, game, Game, Node, sys } from 'cc';
import type { SoundName } from './GameModel';
const { ccclass } = _decorator;
const NAMES: SoundName[] = ['grab', 'founder', 'down', 'resource_down', 'cash_down', 'unpack', 'aha', 'battle_start', 'battle_end', 'hit'];

/** Godot Sfx.gd's ten voices and Settings.gd's default linear volume. */
@ccclass('OriginalAudio')
export class OriginalAudio extends Component {
    private clips = new Map<SoundName, AudioClip>();
    private voices: { source: AudioSource; name: SoundName | '' }[] = [];
    private cursor = 0;
    private active = true;
    private primed = false;
    sfxVolume = .8;
    musicVolume = .6;
    private music!: AudioSource;
    private events: { type: string; name: string; time: number; volume: number }[] = [];
    private hide = () => { this.active = false; this.voices.forEach(v => { if (v.source.isValid) v.source.stop(); }); this.music?.pause(); };
    private show = () => { this.active = true; this.primed = false; };
    onLoad() {
        try {
            const saved = JSON.parse(sys.localStorage.getItem('startx.audio') || '{}');
            if (typeof saved.sfx === 'number') this.sfxVolume = Math.max(0, Math.min(1, saved.sfx));
            if (typeof saved.music === 'number') this.musicVolume = Math.max(0, Math.min(1, saved.music));
        } catch { /* Keep the original defaults when local preferences are unavailable. */ }
        const music = new Node('BackgroundMusic'); this.node.addChild(music);
        this.music = music.addComponent(AudioSource); this.music.playOnAwake = false; this.music.loop = true; this.music.volume = this.musicVolume;
        for (let i = 0; i < 10; i++) {
            const n = new Node('SfxVoice-' + i); this.node.addChild(n);
            const source = n.addComponent(AudioSource); source.playOnAwake = false; source.volume = this.sfxVolume;
            const voice = { source, name: '' as SoundName | '' }; this.voices.push(voice);
            n.on(AudioSource.EventType.STARTED, () => this.record('started', voice.name, source.volume));
        }
        game.on(Game.EVENT_HIDE, this.hide); game.on(Game.EVENT_SHOW, this.show);
        if (typeof window !== 'undefined') { window.addEventListener('blur', this.hide); window.addEventListener('focus', this.show); }
    }
    async preload(bundle: AssetManager.Bundle) {
        await Promise.all(NAMES.map(name => new Promise<void>((resolve, reject) =>
            bundle.load('audio/' + name, AudioClip, (e, clip) => {
                if (e) { reject(e); return; } this.clips.set(name, clip); resolve();
            }))));
        this.music.clip = await new Promise<AudioClip>((resolve, reject) => bundle.load('audio/daily1', AudioClip, (e, clip) => e ? reject(e) : resolve(clip)));
    }
    prime() {
        const clip = this.clips.get('grab');
        if (!this.primed && this.active && clip) {
            this.primed = true; this.voices[0].source.playOneShot(clip, 0);
        }
        if (this.active && this.music.clip && !this.music.playing && this.musicVolume > 0) this.music.play();
    }
    adjustVolume(kind: 'sfx' | 'music', delta: number) {
        if (kind === 'sfx') {
            this.sfxVolume = Math.max(0, Math.min(1, Math.round((this.sfxVolume + delta) * 10) / 10));
            this.voices.forEach(v => { v.source.volume = this.sfxVolume; });
        } else {
            this.musicVolume = Math.max(0, Math.min(1, Math.round((this.musicVolume + delta) * 10) / 10));
            this.music.volume = this.musicVolume;
        }
        try { sys.localStorage.setItem('startx.audio', JSON.stringify({ sfx: this.sfxVolume, music: this.musicVolume })); } catch { /* Session values still apply. */ }
        this.prime(); if (kind === 'sfx') this.play('grab');
    }
    play(name: SoundName, ratio = 1) {
        const clip = this.clips.get(name); if (!this.active || !clip || ratio <= 0) return;
        const voice = this.voices[this.cursor]; this.cursor = (this.cursor + 1) % this.voices.length;
        voice.source.stop(); voice.name = name; voice.source.clip = clip;
        voice.source.volume = this.sfxVolume * Math.min(1, ratio); this.record('request', name, voice.source.volume); voice.source.play();
    }
    private record(type: string, name: string, volume: number) {
        this.events.push({ type, name, time: Date.now(), volume });
        if (this.events.length > 128) this.events.shift();
    }
    snapshot() {
        return { loaded: this.clips.size, active: this.active, sfxVolume: this.sfxVolume, musicVolume: this.musicVolume,
            music: { loaded: !!this.music.clip, playing: this.music.playing, volume: this.music.volume }, events: this.events.slice(),
            voices: this.voices.map(v => ({ name: v.name, playing: v.source.playing, volume: v.source.volume })) };
    }
    onDestroy() {
        this.hide(); game.off(Game.EVENT_HIDE, this.hide); game.off(Game.EVENT_SHOW, this.show);
        if (typeof window !== 'undefined') { window.removeEventListener('blur', this.hide); window.removeEventListener('focus', this.show); }
    }
}
