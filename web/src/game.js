import { pictureHeight, pictureWidth } from "./peter/assets";
import { css } from "./peter/sheet";

const Bullet = {
  None: 0,
  Hit: 1,
  Shell: 2,
  Potsherd: 3,
  FlyingFlame: 4,
  StandingFlame: 5,
  Color: 6,
  Termite: 7,
};

const MAX_BULLETS = 200;
const COLOR_NAMES = ["red", "green", "blue", "yellow", "purple", "cyan", "orange", "pink"];

export const CAPTION = "Desktop Games;   (c) Miroslav Nemecek, www.gemtree.com;   freeware";

/**
 * Port of the Peter program "Desktop Games" (c) Miroslav Němeček, recovered from
 * stress_relief.exe. Mirrors Sources/DesktopGames/DesktopGames.swift and re/program.txt.
 */
export class DesktopGames {
  a;
  introPicture;
  toolSelectionPicture;
  stampPrints;

  selectionCursor;
  tool;
  bullets = [];
  bulletType = new Array(MAX_BULLETS).fill(Bullet.None);
  speedX = new Array(MAX_BULLETS).fill(0);
  speedY = new Array(MAX_BULLETS).fill(0);
  writeIndex = 0;

  selectedFunction = 0;
  lastSelectedFunction = 0;
  noInterruptOfActiveTool = true;
  buttonState = false;
  stereobase = 0;

  desktopStorage;
  desktopOriginal;

  waitBackground;
  waitText;
  paintColors;
  termiteColor;
  sawColor;
  rt;
  host;

  constructor(rt, host) {
    this.rt = rt;
    this.host = host;
    const a = (this.a = rt.assets);
    this.introPicture = a.picture("introduction_picture");
    this.toolSelectionPicture = a.picture("picture_of_tool_selection");
    this.stampPrints = Array.from({ length: 10 }, (_, i) => a.picture(`picture_of_stamp_print_${i + 1}`));
    this.selectionCursor = rt.makeSprite(a.sprite("sprite_of_selection_cursor"));
    this.tool = rt.makeSprite(a.sprite("sprite_of_tool"));
    for (let i = 0; i < MAX_BULLETS; i++) this.bullets.push(rt.makeSprite(a.sprite("bullet")));
    this.waitBackground = a.iconColors[4];
    this.waitText = a.iconColors[5];
    this.paintColors = a.iconColors.slice(6, 14);
    this.termiteColor = a.iconColors[14];
    this.sawColor = a.iconColors[15];
  }

  // Helpers mirroring Peter built-ins

  random(x = 1) {
    return x > 0 ? Math.random() * x : 0;
  }

  randomInt(n) {
    return Math.trunc(this.random(n));
  }

  get mouseX() {
    return this.rt.mouseX;
  }

  get mouseY() {
    return this.rt.mouseY;
  }

  get mapWidth() {
    return this.rt.mapWidth;
  }

  get mapHeight() {
    return this.rt.mapHeight;
  }

  play(name, volume = 1, balance = 0, loops = 1, restart = true) {
    this.rt.audio.play(this.a.sound(name), volume, balance, loops, restart);
  }

  sprite(name) {
    return this.a.sprite(name);
  }

  // Desktop Games (main function)

  async run() {
    const rt = this.rt;
    const language = (navigator.language || "en").slice(0, 2);
    if (!["cs", "pl", "sk"].includes(language)) {
      this.introPicture = this.a.picture("introduction_picture_english");
      this.toolSelectionPicture = this.a.picture("picture_of_tool_selection_english");
      this.stampPrints[2] = this.a.picture("picture_of_stamp_print_3_english");
      this.stampPrints[3] = this.a.picture("picture_of_stamp_print_4_english");
    }

    rt.sheet.draw(this.introPicture, 0, 0);
    // waiting on press key or mouse
    for (;;) {
      const left = rt.leftClick(), right = rt.rightClick();
      if (left || right) break;
      const key = rt.readKey();
      if (key) {
        if (key.kind === "escape") rt.exit();
        break;
      }
      await rt.wait();
    }

    await this.initializationOfDesktopMode();
    this.selectedFunction = 0;
    for (;;) {
      if (this.selectedFunction < 0) await this.makeSelectionOfFunction();
      this.lastSelectedFunction = this.selectedFunction;
      this.selectedFunction = -1;
      this.buttonState = rt.leftClick();
      this.buttonState = rt.rightClick();
      this.buttonState = false;
      this.noInterruptOfActiveTool = true;
      switch (this.lastSelectedFunction) {
        case 0: await this.hammerService(); break;
        case 1: await this.chainSawService(); break;
        case 2: await this.serviceOfMachineGun(); break;
        case 3: await this.serviceOfFlameThrower(); break;
        case 4: await this.serviceOfColorThrower(); break;
        case 5: await this.phaserService(); break;
        case 6: await this.serviceOfStamp(); break;
        case 7: await this.serviceOfTermite(); break;
        case 8: await this.serviceOfWashing(); break;
        default: rt.exit();
      }
      rt.audio.stop();
    }
  }

  async initializationOfDesktopMode() {
    const rt = this.rt;
    // printout text "Wait..."
    rt.sheet.fillAll(this.waitBackground);
    const ctx = rt.sheet.ctx;
    const ppu = rt.sheet.pixelsPerUnit;
    ctx.fillStyle = css(this.waitText);
    ctx.font = `bold ${Math.round(3 * ppu * 0.7)}px Arial, Helvetica, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "alphabetic";
    ctx.fillText("Wait...", rt.sheet.width / 2, rt.sheet.height - 4 * ppu);
    await rt.waitSeconds(0.2);

    // set the window over the whole screen and grab what is under it
    const { shot, cssWidth, cssHeight, scale, display } = this.host.takeOverDesktop();
    const sheet = rt.makeSheet(cssWidth, cssHeight, scale);
    sheet.ctx.drawImage(shot, 0, 0, sheet.width, sheet.height);
    rt.present(sheet, display);
    this.desktopStorage = sheet.snapshot();
    this.desktopOriginal = this.desktopStorage;
    rt.setCursorVisible(false);
  }

  // Selection

  async makeSelectionOfFunction() {
    const rt = this.rt;
    const x0 = (this.mapWidth - pictureWidth(this.toolSelectionPicture)) / 2;
    const y0 = (this.mapHeight - pictureHeight(this.toolSelectionPicture)) / 2;
    this.desktopStorage = rt.sheet.snapshot();
    rt.sheet.draw(this.toolSelectionPicture, x0, y0);
    this.buttonState = rt.leftClick();
    this.buttonState = rt.rightClick();
    this.noInterruptOfActiveTool = true;
    this.tool.setVisible(false);
    rt.audio.stop();
    // switch off bullets (termites will not be switched off)
    for (let i = 0; i < MAX_BULLETS; i++) if (this.bulletType[i] !== Bullet.Termite) this.bullets[i].setVisible(false);
    rt.setCursorVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.mouseInRegion(x0, y0 + 1, 12, 9)) {
        const column = Math.trunc((this.mouseX - x0) / 4);
        this.selectionCursor.x = column * 4 + x0;
        const row = Math.trunc((this.mouseY - y0 - 1) / 3);
        this.selectionCursor.y = row * 3 + y0 + 1;
        this.selectionCursor.setVisible(true);
        if (rt.leftClick()) {
          this.selectedFunction = column + (2 - row) * 3;
          break;
        }
      } else {
        this.buttonState = rt.leftClick();
        this.selectionCursor.setVisible(false);
      }
      if (rt.rightClick()) {
        this.selectedFunction = this.lastSelectedFunction;
        break;
      }
      await rt.wait();
      this.serviceOfSelectionByKeyboard();
    }
    while (rt.mouseLeft) await rt.wait();
    this.selectionCursor.setVisible(false);
    if (this.desktopStorage) rt.sheet.draw(this.desktopStorage, 0, 0);
    rt.setCursorVisible(false);
  }

  serviceOfSelectionByKeyboard() {
    this.noInterruptOfActiveTool = false;
    const key = this.rt.readKey();
    if (key?.kind === "escape") this.rt.exit();
    else if (key?.kind === "tool") this.selectedFunction = key.n;
    else this.noInterruptOfActiveTool = true;
  }

  calculationOfSoundStereobase() {
    this.stereobase = (this.mouseX / this.mapWidth - 0.5) * 1.4;
  }

  // Bullets

  serviceOfBulletsFlight() {
    const rt = this.rt;
    let thereWasFoundFire = false;
    let thereWasFoundTermite = false;
    for (let i = 0; i < MAX_BULLETS; i++) {
      const bullet = this.bullets[i];
      if (!bullet.visible) continue;
      switch (this.bulletType[i]) {
        case Bullet.Hit:
          if (bullet.phase === 0) bullet.setVisible(false);
          break;
        case Bullet.Shell:
          bullet.x += this.speedX[i];
          bullet.y += this.speedY[i];
          this.speedY[i] -= 0.2;
          if (bullet.y < 0) {
            // test of shell drop
            bullet.setVisible(false);
            this.play(`drop_of_shell_${this.randomInt(9) + 1}`, 0.5, (bullet.x / this.mapWidth - 0.7) * 4);
          }
          break;
        case Bullet.Potsherd:
          bullet.x += this.speedX[i];
          bullet.y += this.speedY[i];
          this.speedY[i] -= 0.2;
          if (bullet.y < 0) bullet.setVisible(false);
          break;
        case Bullet.FlyingFlame:
          if (bullet.phase === 0) {
            // test of flame arrival
            bullet.setDef(this.sprite("sprite_of_standing_flame"));
            bullet.x += this.random(8) - 4;
            bullet.y += this.random(8) - 4;
            this.bulletType[i] = Bullet.StandingFlame;
          }
          break;
        case Bullet.StandingFlame: {
          const picture = this.a.picture(`picture_of_flame_thrower_hit_${this.randomInt(4) + 1}`);
          rt.sheet.draw(picture, bullet.x + this.random() - 0.5, bullet.y + this.random() - 0.5);
          this.deathOfTermites(bullet.x - 0.75, bullet.y - 0.75);
          if (!bullet.moving) bullet.setVisible(false);
          else thereWasFoundFire = true;
          break;
        }
        case Bullet.Color:
          if (bullet.phase === 0) {
            // test of color arrival
            this.play("color_thrower_drop", 1, (bullet.x / this.mapWidth - 0.5) * 4);
            const blot = this.a.picture(`picture_of_hit_by_color_thrower_${this.randomInt(5) + 1}`);
            rt.sheet.draw(blot, bullet.x - 1, bullet.y - 1);
            const color = this.paintColors[Math.max(0, COLOR_NAMES.findIndex((n) => bullet.def.name === `sprite_of_color_${n}`))];
            rt.sheet.floodFill(color, bullet.x + 1, bullet.y + 1);
            this.deathOfTermites(bullet.x + 1, bullet.y + 1);
            bullet.setVisible(false);
          }
          break;
        case Bullet.Termite:
          thereWasFoundTermite = true;
          rt.sheet.point(this.termiteColor, 5, bullet.x + 0.5, bullet.y + 0.5);
          if (this.random() < 0.05) {
            // termite movement
            const nx = Math.min(Math.max(bullet.x - 0.5 + this.random(), 0), this.mapWidth - 1);
            const ny = Math.min(Math.max(bullet.y - 0.5 + this.random(), 0), this.mapHeight - 1);
            bullet.x = nx;
            bullet.y = ny;
          }
          break;
      }
    }
    if (thereWasFoundFire) this.play("fire", 1, 0, 0, false);
    else rt.audio.stop(this.a.sound("fire"));
    if (thereWasFoundTermite) this.play("termite_sound", 0.2, 0, 0, false);
    else rt.audio.stop(this.a.sound("termite_sound"));
  }

  /** creation of bullet: returns the list index of the new bullet. */
  creationOfBullet(type, def) {
    let index = this.writeIndex;
    for (let k = 0; k < MAX_BULLETS; k++) {
      if (!this.bullets[index].visible) break;
      index = (index + 1) % MAX_BULLETS;
    }
    this.writeIndex = index;
    this.bulletType[index] = type;
    this.speedX[index] = 0;
    this.speedY[index] = 0;
    this.bullets[index].setVisible(false);
    this.bullets[index].setDef(def);
    this.bullets[index].phase = 1;
    this.writeIndex = (this.writeIndex + 1) % MAX_BULLETS;
    return index;
  }

  creationOfHit(picture, dispersion, sprite) {
    const i = this.creationOfBullet(Bullet.Hit, sprite);
    const x = this.mouseX + this.random(dispersion) - dispersion / 2 - pictureWidth(picture) / 2;
    const y = this.mouseY + this.random(dispersion) - dispersion / 2 - pictureHeight(picture) / 2;
    this.bullets[i].x = x;
    this.bullets[i].y = y;
    this.rt.sheet.draw(picture, x, y);
    this.bullets[i].setVisible(true);
  }

  deathOfTermites(x, y) {
    for (let i = 0; i < MAX_BULLETS; i++) {
      const b = this.bullets[i];
      if (b.visible && this.bulletType[i] === Bullet.Termite && Math.abs(x - (b.x + 0.5)) < 1.5 && Math.abs(y - (b.y + 0.5)) < 1.5) {
        this.rt.sheet.draw(this.a.picture("dead_termite"), b.x, b.y);
        b.setVisible(false);
        this.play("squishy_termite", 2);
      }
    }
  }

  // 0: hammer

  async hammerService() {
    const rt = this.rt, tool = this.tool;
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX;
      tool.y = this.mouseY - 4.66; // height of drop place in sprite
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // hit
        tool.setDef(this.sprite("sprite_of_knock_hammer"));
        if (!this.buttonState) {
          // hit service
          this.deathOfTermites(this.mouseX, this.mouseY);
          let brightness = 0;
          let oy = -0.5;
          for (let r = 0; r < 11; r++) {
            // detection of color brightness in destination place
            let ox = -0.5;
            for (let c = 0; c < 11; c++) {
              brightness += this.colorBrightness(ox, oy);
              ox += 0.1;
            }
            oy += 0.1;
          }
          const smash = Math.min(7, Math.trunc((brightness / 11 / 11) * 8));
          rt.audio.stop();
          this.play(`smash_${smash + 1}`, 2, this.stereobase);
          const picture = this.a.picture(`picture_of_hammer_hit_${this.randomInt(8) + 1}`);
          rt.sheet.draw(
            picture,
            this.mouseX - pictureWidth(picture) / 2 - (this.random() - 0.5) * 0.2,
            this.mouseY - pictureHeight(picture) / 2 - (this.random() - 0.5) * 0.2,
          );
          for (let k = 0; k < Math.trunc(brightness / 5); k++) this.createPotsherd();
        }
        this.buttonState = true;
      } else {
        tool.setDef(this.sprite("sprite_of_quiet_hammer"));
        this.buttonState = false;
      }
      await rt.wait();
      this.serviceOfSelectionByKeyboard();
    }
  }

  /** determine color brightness by offset */
  colorBrightness(ox, oy) {
    const c = this.rt.sheet.color(this.mouseX + ox, this.mouseY + oy);
    return (c.r + c.g + c.b) / 256 / 3;
  }

  createPotsherd() {
    const i = this.creationOfBullet(Bullet.Potsherd, this.sprite(`sprite_of_potsherd_${this.randomInt(5) + 1}`));
    this.speedX[i] = this.random(2) - 1;
    this.speedY[i] = this.random(2) - 1;
    this.bullets[i].x = this.mouseX + this.random() - 0.5;
    this.bullets[i].y = this.mouseY + this.random() - 0.5;
    this.bullets[i].setVisible(true);
  }

  // 1: chain-saw

  async chainSawService() {
    const rt = this.rt, tool = this.tool;
    let oldX = 0, oldY = 0;
    tool.setDef(this.sprite("sprite_of_quiet_chain_saw"));
    tool.x = this.mouseX - 3;
    tool.y = this.mouseY - 3;
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // sawing
        tool.setDef(this.sprite("sprite_of_sawing_chain_saw"));
        tool.x = this.mouseX - 3;
        tool.y = this.mouseY - 3;
        this.deathOfTermites(tool.x + 3, tool.y + 3);
        const newX = tool.x + 3, newY = tool.y + 3;
        if (!this.buttonState) {
          // start sawing
          rt.audio.stop();
          oldX = newX;
          oldY = newY;
        }
        this.buttonState = true;
        rt.sheet.line(this.sawColor, 2, oldX, oldY, newX, newY);
        const distance = Math.hypot(oldX - newX, oldY - newY);
        for (let k = 0; k < Math.trunc(distance * 7); k++) this.createSplinter(newX, newY);
        oldX = newX;
        oldY = newY;
        this.play("sawing_chain_saw", 2, this.stereobase, 0, false);
      } else {
        // transportation
        tool.setDef(this.sprite("sprite_of_quiet_chain_saw"));
        tool.x = this.mouseX - 3;
        tool.y = this.mouseY - 3;
        if (this.buttonState) rt.audio.stop(); // stop sawing
        this.play("quiet_chain_saw", 1, this.stereobase, 0, false);
        this.buttonState = false;
      }
      await rt.wait();
      this.serviceOfSelectionByKeyboard();
    }
  }

  createSplinter(x, y) {
    const i = this.creationOfBullet(Bullet.Potsherd, this.sprite(`sprite_of_splinter_${this.randomInt(5) + 1}`));
    this.speedX[i] = this.random(2) - 1;
    this.speedY[i] = this.random(2) - 1;
    this.bullets[i].x = x + this.random() - 0.5;
    this.bullets[i].y = y + this.random() - 0.5;
    this.bullets[i].setVisible(true);
  }

  // 2: machine gun

  async serviceOfMachineGun() {
    const rt = this.rt, tool = this.tool;
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX;
      tool.y = this.mouseY - 6;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // shooting
        tool.setDef(this.sprite("sprite_of_shooting_machine_gun"));
        if (!this.buttonState) rt.audio.stop();
        this.buttonState = true;
        this.play("machine_gun", 1, this.stereobase, 0, false);
        const hit = this.a.picture(`picture_of_hit_by_machine_gun_${this.randomInt(4)}`);
        this.deathOfTermites(this.mouseX, this.mouseY);
        this.creationOfHit(hit, 0.5, this.sprite("sprite_of_hit_by_machine_gun"));
        this.createShell();
      } else {
        tool.setDef(this.sprite("sprite_of_quiet_machine_gun"));
        if (this.buttonState) {
          rt.audio.stop();
          this.play("machine_gun_reverberation");
        }
        this.buttonState = false;
      }
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  createShell() {
    const i = this.creationOfBullet(Bullet.Shell, this.sprite("sprite_of_shell_from_machine_gun"));
    const x = this.mouseX + 3 + this.random();
    const y = this.mouseY - 3 - this.random();
    this.speedX[i] = this.random();
    this.speedY[i] = this.random();
    this.bullets[i].x = x;
    this.bullets[i].y = y;
    this.bullets[i].setVisible(true);
  }

  // 3: flame-thrower

  async serviceOfFlameThrower() {
    const rt = this.rt, tool = this.tool;
    tool.setDef(this.sprite("sprite_of_flame_thrower"));
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX;
      tool.y = this.mouseY - 8;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // shooting
        if (!this.buttonState) {
          rt.audio.stop();
          this.play("flame_begin", 1, this.stereobase);
        }
        this.play("flame", 1, this.stereobase, 0, false);
        this.buttonState = true;
        this.createFlame();
      } else {
        if (this.buttonState) {
          // terminate sounds
          this.play("flame", 1, this.stereobase, 1, false);
          this.play("flame_end", 1, this.stereobase);
        }
        this.buttonState = false;
      }
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  createFlame() {
    const b = this.bullets[this.creationOfBullet(Bullet.FlyingFlame, this.sprite("sprite_of_flame"))];
    b.x = this.mouseX + 3 + this.random(0.2);
    b.y = this.mouseY - 3.4 - this.random(0.2);
    b.setVisible(true);
    b.x = b.x - 3 - this.random();
    b.y = b.y + 2 + this.random();
  }

  // 4: color-thrower

  async serviceOfColorThrower() {
    const rt = this.rt, tool = this.tool;
    let rechargeCounter = 0;
    tool.setDef(this.sprite("sprite_of_color_thrower"));
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX;
      tool.y = this.mouseY - 8;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      rechargeCounter--;
      if (rt.mouseLeft && rechargeCounter <= 0) {
        // shooting
        rt.audio.stop();
        this.play("color_thrower_shooting", 1, this.stereobase);
        rechargeCounter = 9;
        this.createColor();
      }
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  createColor() {
    const name = COLOR_NAMES[this.randomInt(8)];
    const b = this.bullets[this.creationOfBullet(Bullet.Color, this.sprite(`sprite_of_color_${name}`))];
    b.x = this.mouseX + 3 + this.random(0.2);
    b.y = this.mouseY - 3.4 - this.random(0.2);
    b.setVisible(true);
    b.x = b.x - 4 - this.random();
    b.y = b.y + 2.4 + this.random();
  }

  // 5: phaser

  async phaserService() {
    const rt = this.rt, tool = this.tool;
    let dischargeCounter = 0;
    tool.setDef(this.sprite("sprite_of_phaser"));
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX - 2;
      tool.y = this.mouseY - 8;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.leftClick() && dischargeCounter <= 0) {
        // begin shoot
        dischargeCounter = 6;
        rt.audio.stop();
        this.play("phaser", 1, this.stereobase);
      }
      if (dischargeCounter > 0) {
        // service of shoot
        dischargeCounter--;
        tool.setDef(this.sprite("sprite_of_shooting_phaser"));
        this.deathOfTermites(this.mouseX, this.mouseY);
        const hit = this.a.picture(`picture_of_phaser_hit_${this.randomInt(10) + 1}`);
        rt.sheet.draw(hit, tool.x + 0.2 - this.random(0.1), tool.y + 6 + this.random(0.1));
      } else {
        tool.setDef(this.sprite("sprite_of_phaser"));
      }
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  // 6: stamp

  async serviceOfStamp() {
    const rt = this.rt, tool = this.tool;
    tool.setDef(this.sprite("sprite_of_stamp"));
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX - 1.5;
      tool.y = this.mouseY - 1.5;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // print of stamp
        tool.setDef(this.sprite("sprite_of_stamp_down"));
        if (rt.leftClick()) {
          // it is first print
          rt.audio.stop();
          this.play("stamp", 1, this.stereobase);
          rt.sheet.draw(this.stampPrints[this.randomInt(10)], tool.x, tool.y);
          this.deathOfTermites(this.mouseX, this.mouseY);
        }
      } else {
        tool.setDef(this.sprite("sprite_of_stamp"));
      }
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  // 7: termite

  async serviceOfTermite() {
    const rt = this.rt, tool = this.tool;
    tool.setDef(this.sprite("sprite_of_termite_on_hand"));
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX - 1;
      tool.y = this.mouseY - 1;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // put termite down
        tool.setDef(this.sprite("sprite_of_termite_down"));
        if (!this.buttonState) {
          // it is first push
          const i = this.creationOfBullet(Bullet.Termite, this.sprite("termite"));
          this.bullets[i].x = this.mouseX - 0.5;
          this.bullets[i].y = this.mouseY - 0.5;
          this.bullets[i].setVisible(true);
        }
      } else {
        tool.setDef(this.sprite("sprite_of_termite_on_hand"));
      }
      this.buttonState = rt.mouseLeft;
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  // 8: washing

  async serviceOfWashing() {
    const rt = this.rt, tool = this.tool;
    tool.setDef(this.sprite("sprite_of_washing"));
    tool.setVisible(true);
    while (this.noInterruptOfActiveTool) {
      if (rt.rightClick()) break;
      tool.x = this.mouseX - 2;
      tool.y = this.mouseY - 8;
      this.calculationOfSoundStereobase();
      this.serviceOfBulletsFlight();
      if (rt.mouseLeft) {
        // service of washing
        tool.setDef(this.sprite("sprite_of_proceeding_washing"));
        if (!this.buttonState) rt.audio.stop();
        this.play("sound_of_washing", 1, this.stereobase, 0, false);
        this.restoreOnePart(1, 2.5);
        this.restoreOnePart(1.5, 2.25);
        this.restoreOnePart(2, 2);
        this.restoreOnePart(2.25, 1.5);
        this.restoreOnePart(2.5, 1);
      } else {
        tool.setDef(this.sprite("sprite_of_washing"));
        if (this.buttonState) rt.audio.stop();
      }
      this.buttonState = rt.mouseLeft;
      this.serviceOfSelectionByKeyboard();
      await rt.wait();
    }
  }

  restoreOnePart(width, height) {
    if (!this.desktopOriginal) return;
    const h = height + this.random(0.4) - 0.2;
    const w = width + this.random(0.4) - 0.2;
    const x = Math.max(0, this.mouseX - w / 2);
    const y = Math.max(0, this.mouseY - h / 2);
    this.rt.sheet.draw(this.desktopOriginal, x, y, { x, y, w, h });
  }
}
