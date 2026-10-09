import { POINTS_PER_UNIT } from "./sheet";

const pixel = (v) => Math.round(v * POINTS_PER_UNIT);

/**
 * A Peter sprite instance, reproducing the interpreter's movement and animation rules
 * (FUN_004194d0 position setter, FUN_00419830 visibility, FUN_00419950 definition swap,
 * FUN_0041ad10 timer tick). Reading x/y returns the current, animated position.
 */
export class Sprite {
  visible = false;
  moving = false;
  direction = 0;
  animating = false;
  countdown = 0;
  stepsLeft = 0;
  phaseValue = 0;
  requestedPhase = -1;
  targetX = 0;
  targetY = 0;
  currentX = 0;
  currentY = 0;
  stepX = 0;
  stepY = 0;

  def;

  constructor(def) {
    this.def = def;
  }

  get x() {
    return this.currentX;
  }

  set x(v) {
    this.setPosition(v, this.targetY);
  }

  get y() {
    return this.currentY;
  }

  set y(v) {
    this.setPosition(this.targetX, v);
  }

  get phase() {
    return this.requestedPhase >= 0 ? this.requestedPhase : this.phaseValue;
  }

  set phase(v) {
    this.requestedPhase = v >= 0 && v < this.def.phases ? v : -1;
  }

  setVisible(v) {
    if (v === this.visible) return;
    if (v) {
      this.visible = true;
      this.startAnimating();
      return;
    }
    this.visible = false;
    this.animating = false;
    if (this.moving) {
      this.currentX = this.targetX;
      this.currentY = this.targetY;
      this.stepsLeft = -1;
      this.moving = false;
    }
    while (this.phaseValue >= this.def.restPhases) this.phaseValue -= this.def.restPhases;
  }

  setDef(next) {
    if (next === this.def) return;
    const def = this.def;
    if (this.visible && def.restPhases > 1 && next.restPhases === 1) this.animating = false;
    if (this.phaseValue < def.restPhases) {
      if (next.restPhases <= this.phaseValue) this.phaseValue = 0;
    } else {
      this.phaseValue += next.restPhases - def.restPhases;
      if (next.phases <= this.phaseValue) this.phaseValue = next.restPhases;
    }
    this.def = next;
    if (next.phases <= this.phaseValue) this.phaseValue = 0;
    if (this.direction >= next.directions) this.direction %= next.directions;
    if (this.visible) this.startAnimating();
  }

  setPosition(nx, ny) {
    this.targetX = nx;
    this.targetY = ny;
    if (!this.visible) {
      this.currentX = nx;
      this.currentY = ny;
      return;
    }
    const def = this.def;
    if (pixel(nx) !== pixel(this.currentX) || pixel(ny) !== pixel(this.currentY)) {
      this.animating = false;
      const dx = nx - this.currentX, dy = ny - this.currentY;
      const sector = (2 * Math.PI) / def.directions;
      let dir = Math.round(Math.atan2(dy, dx) / sector);
      while (dir >= def.directions) dir -= def.directions;
      while (dir < 0) dir += def.directions;
      this.direction = dir;
      if (!this.moving) {
        this.moving = true;
        this.countdown = 1;
      }
      if (this.phaseValue < def.restPhases && def.restPhases < def.phases) this.phaseValue = def.restPhases - 1;
      let steps = Math.round(Math.sqrt(dx * dx + dy * dy) * def.steps);
      if (steps === 0) {
        if (def.steps === 0) {
          this.currentX = nx;
          this.currentY = ny;
          this.stepsLeft = -1;
          this.moving = false;
          this.startAnimating();
          return;
        }
        steps = 1;
      }
      this.stepsLeft = steps;
      this.stepX = dx / steps;
      this.stepY = dy / steps;
      return;
    }
    this.currentX = nx;
    this.currentY = ny;
    if (this.moving) {
      this.stepsLeft = -1;
      this.moving = false;
    }
    if (def.restPhases === 1) this.phaseValue = 0;
    this.startAnimating();
  }

  startAnimating() {
    if (this.animating || this.def.restPhases <= 1) return;
    this.animating = true;
    if (this.countdown < 1) this.countdown = this.def.delayTicks;
  }

  get pendingPhaseValid() {
    return this.requestedPhase >= 0 && this.requestedPhase < this.def.phases;
  }

  takeRequestedPhase() {
    this.phaseValue = this.requestedPhase;
    this.requestedPhase = -1;
  }

  /** One 55 ms timer tick. */
  tick() {
    const def = this.def;
    if (this.moving) {
      if (--this.countdown >= 1) return;
      this.stepsLeft--;
      if (this.stepsLeft < 0) {
        this.currentX = this.targetX;
        this.currentY = this.targetY;
        if (this.pendingPhaseValid) {
          this.takeRequestedPhase();
        } else {
          if (def.restPhases <= this.phaseValue) this.phaseValue -= def.restPhases;
          this.phaseValue = (this.phaseValue + 1) % def.restPhases;
        }
        this.moving = false;
        if (def.restPhases > 1) {
          this.animating = true;
          this.countdown = def.delayTicks;
        }
      } else {
        this.currentX += this.stepX;
        this.currentY += this.stepY;
        this.countdown = def.delayTicks;
        if (this.pendingPhaseValid) {
          this.takeRequestedPhase();
        } else {
          this.phaseValue++;
          if (def.phases <= this.phaseValue) {
            this.phaseValue = def.restPhases;
            if (def.phases <= this.phaseValue) this.phaseValue = 0;
          }
        }
      }
    } else if (this.animating) {
      if (--this.countdown >= 1) return;
      if (this.pendingPhaseValid) this.takeRequestedPhase();
      else this.phaseValue = (this.phaseValue + 1) % def.restPhases;
      this.countdown = def.delayTicks;
    }
  }

  /** Sort key: higher levels on top, lower sprites in front within a level. */
  get z() {
    return this.def.level - this.currentY / 10000;
  }

  /** Draw onto a context whose units are CSS pixels, y pointing down, `height` CSS pixels tall. */
  render(ctx, height) {
    if (!this.moving && !this.animating && this.countdown < 1 && this.pendingPhaseValid) this.takeRequestedPhase();
    if (!this.visible) return;
    const def = this.def;
    const dir = Math.min(this.direction, def.frames.length - 1);
    const ph = Math.min(this.phaseValue, def.frames[dir].length - 1);
    ctx.drawImage(def.frames[dir][ph], pixel(this.currentX), height - pixel(this.currentY) - def.height);
  }
}
