import Foundation

/// The clock a piece runs on, added before any of its own code. Time stands still until the player steps it, one frame
/// of 1/60 s at a time: `performance.now`, `Date`, `requestAnimationFrame`, timers, CSS and Web Animations, video and
/// audio elements and `Math.random` (seeded) all read it, so a moment always draws the same way however it is reached.
///
/// The page sees `window.__hmm`: `step(frames)` moves the clock on and returns the time in seconds, `onFrame(fn)` is
/// called with the time after every step (the Lottie host turns its animation there), `errors` keeps what threw.
public enum HmmWebClock {
    public static let script = #"""
    (() => {
      if (window.__hmm) return;
      const perFrame = 1000 / 60;
      const epoch = Date.UTC(2026, 0, 1, 12);
      let frame = 0, now = 0, nextId = 1, seed = 0x2545F491;
      let frames = new Map();
      const timers = new Map(), hooks = [], errors = [], born = new WeakMap();
      const report = e => { if (errors.length < 20) errors.push(String(e && e.stack || e)); };
      const RealDate = Date;
      class HmmDate extends RealDate {
        constructor(...a) { if (a.length === 0) super(epoch + now); else super(...a); }
        static now() { return epoch + now; }
      }
      window.Date = HmmDate;
      Object.defineProperty(performance, 'now', { value: () => now, configurable: true });
      window.requestAnimationFrame = fn => { const id = nextId++; frames.set(id, fn); return id; };
      window.cancelAnimationFrame = id => { frames.delete(id); };
      window.setTimeout = (fn, ms, ...args) => {
        const id = nextId++; timers.set(id, { at: now + Math.max(0, +ms || 0), fn, args }); return id;
      };
      window.setInterval = (fn, ms, ...args) => {
        const id = nextId++, every = Math.max(1, +ms || 0); timers.set(id, { at: now + every, fn, args, every }); return id;
      };
      window.clearTimeout = window.clearInterval = id => { timers.delete(id); };
      window.queueMicrotask = window.queueMicrotask || (fn => Promise.resolve().then(fn));
      Math.random = () => {
        seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 4294967296;
      };
      const call = (fn, args, at) => {
        try { typeof fn === 'function' ? fn(...(args || [at])) : (0, eval)(String(fn)); } catch (e) { report(e); }
      };
      const runTimers = until => {
        for (;;) {
          let best = null, bestId = 0;
          for (const [id, t] of timers) {
            if (t.at <= until && (!best || t.at < best.at || (t.at === best.at && id < bestId))) { best = t; bestId = id; }
          }
          if (!best) break;
          now = best.at;
          if (best.every) best.at += best.every; else timers.delete(bestId);
          call(best.fn, best.args);
        }
        now = until;
      };
      const runFrame = () => {
        const due = frames; frames = new Map();
        for (const fn of due.values()) call(fn, [now], now);
      };
      const syncMedia = () => {
        if (document.getAnimations) {
          for (const a of document.getAnimations()) {
            if (!born.has(a)) born.set(a, now);
            try { a.pause(); a.currentTime = Math.max(0, now - born.get(a)); } catch (e) { report(e); }
          }
        }
        for (const m of document.querySelectorAll('video,audio')) {
          try { m.muted = true; m.pause(); m.currentTime = now / 1000; } catch (e) { report(e); }
        }
        for (const fn of hooks) call(fn, [now / 1000]);
      };
      window.__hmm = {
        get time() { return now / 1000; },
        get frame() { return frame; },
        errors,
        onFrame(fn) { hooks.push(fn); },
        prime() { runTimers(0); runFrame(); syncMedia(); return 0; },
        step(count) {
          for (let i = 0; i < count; i++) { frame += 1; runTimers(frame * perFrame); runFrame(); }
          syncMedia();
          return now / 1000;
        }
      };
      window.addEventListener('error', e => report(e.message));
      window.addEventListener('unhandledrejection', e => report(e.reason));
    })();
    """#

    /// Waits for the page to have loaded with its fonts, then draws frame 0: the first round of animation frames, at time 0.
    public static let ready = #"""
    await new Promise(r => document.readyState === 'complete' ? r() : window.addEventListener('load', r, { once: true }));
    if (document.fonts && document.fonts.ready) await document.fonts.ready;
    await new Promise(r => Promise.resolve().then(r));
    window.__hmm.prime();
    return true;
    """#

    /// JavaScript that steps the clock `frames` frames on and returns the time it reaches.
    public static func step(_ frames: Int) -> String {
        "return window.__hmm.step(\(max(frames, 0)));"
    }
}
