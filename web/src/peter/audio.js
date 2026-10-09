/**
 * Reproduces Peter's sound_play semantics (FUN_0042cf20): one channel per sound; replaying a
 * sound that is still playing only restarts it when `restart` is set, but always updates its
 * volume, balance and looping. Peter's only loop counts here are 1 and endless (< 1).
 */
export class AudioMixer {
  channels = new Map();
  muted = false;
  context;

  constructor(context) {
    this.context = context;
  }

  play(buffer, volume = 1, balance = 0, loops = 1, restart = true) {
    if (this.muted) return;
    const vol = Math.min(Math.abs(volume), 1);
    const bal = Math.max(-1, Math.min(1, balance));
    const l = vol * (bal > 0 ? 1 - bal : 1);
    const r = vol * (bal <= 0 ? 1 + bal : 1);
    const endless = loops < 1;

    let ch = this.channels.get(buffer);
    if (ch && restart) {
      this.stop(buffer);
      ch = undefined;
    }
    if (!ch) {
      ch = this.start(buffer);
      this.channels.set(buffer, ch);
    }
    ch.left.gain.value = l;
    ch.right.gain.value = r;
    ch.source.loop = endless;
  }

  stop(buffer) {
    const targets = buffer ? [buffer] : [...this.channels.keys()];
    for (const b of targets) {
      const ch = this.channels.get(b);
      if (!ch) continue;
      this.channels.delete(b);
      ch.source.onended = null;
      try {
        ch.source.stop();
      } catch {
        // already stopped
      }
      ch.source.disconnect();
    }
  }

  start(buffer) {
    const ctx = this.context;
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const split = ctx.createChannelSplitter(2);
    const merge = ctx.createChannelMerger(2);
    const left = ctx.createGain();
    const right = ctx.createGain();
    source.connect(split);
    split.connect(left, 0);
    split.connect(right, 1);
    left.connect(merge, 0, 0);
    right.connect(merge, 0, 1);
    merge.connect(ctx.destination);
    const ch = { source, left, right };
    source.onended = () => {
      if (this.channels.get(buffer) === ch) this.channels.delete(buffer);
      source.disconnect();
    };
    source.start();
    return ch;
  }
}
