document.documentElement.classList.add("js");

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

/* menubar clock */

const clock = $("[data-clock]");
function tickClock() {
  const now = new Date();
  clock.textContent = now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
}
tickClock();
setInterval(tickClock, 10_000);

/* staggered entrance order */

$$(".desk .win, .desk .sticker, .desk .pill").forEach((el, i) => el.style.setProperty("--i", i));

/* draggable windows */

let topZ = 10;
for (const win of $$("[data-win]")) {
  const handle = $("[data-drag]", win);
  let start = null;

  win.addEventListener("pointerdown", () => { win.style.zIndex = ++topZ; });

  handle.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || matchMedia("(max-width: 980px)").matches) return;
    handle.setPointerCapture(event.pointerId);
    start = {
      id: event.pointerId,
      px: event.clientX,
      py: event.clientY,
      x: parseFloat(win.style.getPropertyValue("--x")) || 0,
      y: parseFloat(win.style.getPropertyValue("--y")) || 0,
    };
  });

  handle.addEventListener("pointermove", (event) => {
    if (!start || event.pointerId !== start.id) return;
    win.style.setProperty("--x", `${start.x + event.clientX - start.px}px`);
    win.style.setProperty("--y", `${start.y + event.clientY - start.py}px`);
  });

  const end = (event) => { if (start && event.pointerId === start.id) start = null; };
  handle.addEventListener("pointerup", end);
  handle.addEventListener("pointercancel", end);
}

/* dictation demo */

// [brackets] mark words the cleanup pass removes.
const samples = [
  {
    raw: "[um] so essentially what i want is [like] for us to figure out the design of the landing page, [you know,] not lame",
    clean: "Essentially, I want us to figure out the design of the landing page. Not lame.",
  },
  {
    raw: "ok [so] the bug is that the [uh] the pill doesn't remember which display it was on",
    clean: "The bug is that the pill doesn't remember which display it was on.",
  },
  {
    raw: "refactor this function so it [um] returns early instead of [like] nesting everything",
    clean: "Refactor this function so it returns early instead of nesting everything.",
  },
  {
    raw: "hey [uh] are we still on for friday, [like] i can bring the speakers",
    clean: "Hey, are we still on for Friday? I can bring the speakers.",
  },
];

function tokenize(raw) {
  const tokens = [];
  const pattern = /\[([^\]]+)\]|(\S+)/g;
  for (const match of raw.matchAll(pattern)) {
    if (match[1]) for (const word of match[1].split(" ")) tokens.push({ word, filler: true });
    else tokens.push({ word: match[2], filler: false });
  }
  return tokens;
}

const desk = $("[data-desk]");
const field = $("[data-field]");
const pill = $("[data-pill]");
const timer = $("[data-timer]");
const stateLabel = $("[data-state-label]");
const micState = $("[data-mic-state]");
const hint = $("[data-hint]");

const demo = {
  state: "idle", // idle | listening | finishing
  sampleIndex: 0,
  tokens: [],
  shown: 0,
  partial: null,
  wordTimer: 0,
  startedAt: 0,
  auto: true,
  autoTimer: 0,
};

function setState(state) {
  demo.state = state;
  const live = state === "listening";
  pill.toggleAttribute("data-live", live);
  micState.toggleAttribute("data-on", live);
  micState.textContent = live ? "listening" : "mic off";
  stateLabel.toggleAttribute("data-live", live);
  stateLabel.textContent = { idle: "idle", listening: "listening", finishing: "tidying" }[state];
  dispatchEvent(new CustomEvent("listen:state", { detail: state }));
}

function renderPartial() {
  demo.partial.replaceChildren();
  demo.tokens.slice(0, demo.shown).forEach((token, i) => {
    const span = document.createElement("span");
    span.textContent = (i ? " " : "") + token.word;
    if (token.filler) span.className = "filler";
    demo.partial.append(span);
  });
  field.scrollTop = field.scrollHeight;
}

function streamNextWord() {
  if (demo.state !== "listening") return;
  if (demo.shown < demo.tokens.length) {
    demo.shown += 1;
    renderPartial();
  }
  demo.wordTimer = setTimeout(streamNextWord, 110 + Math.random() * 150);
}

function startDictation({ auto = false } = {}) {
  if (!auto) stopAuto();
  if (demo.state !== "idle") return;

  const sample = samples[demo.sampleIndex % samples.length];
  demo.sampleIndex += 1;
  demo.tokens = tokenize(sample.raw);
  demo.clean = sample.clean;
  demo.shown = 0;
  demo.startedAt = performance.now();

  if (auto) field.replaceChildren();
  const needsSpace = field.textContent.length > 0 && !/\s$/.test(field.textContent);
  if (needsSpace) field.append(" ");

  demo.partial = document.createElement("span");
  demo.partial.className = "partial";
  demo.partial.contentEditable = "false";
  field.append(demo.partial);

  setState("listening");
  streamNextWord();
}

function finishDictation() {
  if (demo.state !== "listening") return;
  clearTimeout(demo.wordTimer);
  setState("finishing");

  // the recognizer catches up with whatever was said before release
  demo.shown = demo.tokens.length;
  renderPartial();

  const partial = demo.partial;
  const swapDelay = reduceMotion ? 250 : 520;
  setTimeout(() => partial.classList.add("tidy"), 120);
  setTimeout(() => partial.classList.add("swap"), swapDelay);
  setTimeout(() => {
    const committed = document.createElement("span");
    committed.className = "fresh";
    committed.textContent = demo.clean;
    partial.replaceWith(committed);
    requestAnimationFrame(() => requestAnimationFrame(() => committed.classList.add("settled")));
    // unwrap later so the field is plain, editable text again
    setTimeout(() => committed.replaceWith(document.createTextNode(committed.textContent)), 1000);
    demo.partial = null;
    setState("idle");
    if (demo.auto) scheduleAuto(2600);
  }, swapDelay + 200);
}

function cancelDictation() {
  if (demo.state !== "listening") return;
  clearTimeout(demo.wordTimer);
  demo.partial.remove();
  demo.partial = null;
  setState("idle");
}

/* autoplay until someone tries it themselves */

function scheduleAuto(delay) {
  clearTimeout(demo.autoTimer);
  demo.autoTimer = setTimeout(runAuto, delay);
}

function runAuto() {
  if (!demo.auto || !deskVisible || demo.state !== "idle") return scheduleAuto(1500);
  startDictation({ auto: true });
  const tokens = demo.tokens.length;
  setTimeout(() => demo.auto && finishDictation(), tokens * 185 + 500);
}

function stopAuto() {
  if (!demo.auto) return;
  demo.auto = false;
  clearTimeout(demo.autoTimer);
  if (demo.state === "listening") cancelDictation();
  updateHint();
}

let deskVisible = true;
new IntersectionObserver(([entry]) => { deskVisible = entry.isIntersecting; }, { threshold: 0.25 }).observe(desk);

/* shortcuts: the keys are defaults, every one can be rebound */

const MODIFIER_CODES = {
  ControlLeft: "ctrl", ControlRight: "ctrl", AltLeft: "alt", AltRight: "alt",
  ShiftLeft: "shift", ShiftRight: "shift", MetaLeft: "meta", MetaRight: "meta",
};
const MOD_LABELS = { ctrl: "control", alt: "option", shift: "shift", meta: "cmd" };
const NAMED_KEYS = {
  Space: "space", Escape: "esc", Enter: "return", Backspace: "delete", Tab: "tab",
  ArrowUp: "↑", ArrowDown: "↓", ArrowLeft: "←", ArrowRight: "→",
  ControlLeft: "control", ControlRight: "right control", AltLeft: "option", AltRight: "right option",
  ShiftLeft: "shift", ShiftRight: "right shift", MetaLeft: "cmd", MetaRight: "right cmd",
  Backquote: "`", Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]", Backslash: "\\",
  Semicolon: ";", Quote: "'", Comma: ",", Period: ".", Slash: "/",
};

function keyLabel(code) {
  if (NAMED_KEYS[code]) return NAMED_KEYS[code];
  if (/^Key[A-Z]$/.test(code)) return code.slice(3).toLowerCase();
  if (/^Digit\d$/.test(code)) return code.slice(5);
  return code.replace(/^Numpad/, "num ").toLowerCase().replace(/^f(\d+)$/, "F$1");
}

const comboLabels = (binding) => [...binding.mods.map((mod) => MOD_LABELS[mod]), keyLabel(binding.code)];
const heldMods = (event) => ["ctrl", "alt", "shift", "meta"].filter((mod) => event[`${mod}Key`] && mod !== MODIFIER_CODES[event.code]);
const matches = (binding, event) => event.code === binding.code && binding.mods.every((mod) => event[`${mod}Key`]);
// keys that would otherwise type something into the text field
const typesText = (binding) =>
  !MODIFIER_CODES[binding.code] && !/^F\d+$/.test(binding.code) && binding.code !== "Escape" &&
  binding.mods.every((mod) => mod === "shift");

// browsers can't see fn, so the page starts on space until you pick something else
const PAGE_DEFAULTS = { hold: { code: "Space", mods: [] }, cancel: { code: "Escape", mods: [] } };
const bindings = { ...PAGE_DEFAULTS };

function renderCaps(container, labels) {
  container.replaceChildren();
  labels.forEach((label, i) => {
    if (i) container.append(Object.assign(document.createElement("span"), { className: "plus", textContent: "+" }));
    const cap = document.createElement("kbd");
    cap.className = "cap";
    if (label === "space") cap.classList.add("cap-space");
    else if (label.length > 3) cap.classList.add("cap-wide");
    cap.textContent = label;
    container.append(cap);
  });
}

function updateHint() {
  const hold = comboLabels(bindings.hold).join(" + ");
  const cancel = comboLabels(bindings.cancel).join(" + ");
  hint.innerHTML = demo.auto
    ? `or hold <kbd>${hold}</kbd> to try it here`
    : `hold <kbd>${hold}</kbd> to talk. <kbd>${cancel}</kbd> cancels.`;
}

const bindButtons = $$("[data-bind]");
function renderBind(button) {
  renderCaps(button, button.binding ? comboLabels(button.binding) : button.dataset.default.split("+"));
  button.toggleAttribute("data-custom", Boolean(button.binding));
  button.setAttribute("aria-label", `${button.closest(".key-row").querySelector("strong").textContent}: ${button.textContent}. click to rebind`);
}

function setBinding(button, binding) {
  const name = button.dataset.bind;
  button.binding = binding;
  if (name in bindings) bindings[name] = binding ?? PAGE_DEFAULTS[name];
  renderBind(button);
  updateHint();
}

for (const button of bindButtons) {
  renderBind(button);
  const reset = Object.assign(document.createElement("button"), { type: "button", className: "bind-reset", textContent: "reset" });
  reset.addEventListener("click", () => setBinding(button, null));
  button.after(reset);
  button.addEventListener("click", () => startRecording(button));
}

let recording = null;

function startRecording(button) {
  if (recording) stopRecording();
  recording = { button, mods: new Set() };
  button.toggleAttribute("data-recording", true);
  button.replaceChildren(Object.assign(document.createElement("span"), { className: "bind-prompt", textContent: "press keys…" }));
}

function stopRecording(binding) {
  const { button } = recording;
  recording = null;
  button.removeAttribute("data-recording");
  if (binding) setBinding(button, binding);
  else renderBind(button);
}

// capture phase so recording wins over the demo's own shortcuts
addEventListener("keydown", (event) => {
  if (!recording) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  if (event.repeat) return;
  if (MODIFIER_CODES[event.code]) {
    recording.mods.add(event.code);
    renderCaps(recording.button, [...[...recording.mods].map(keyLabel), "…"]);
    return;
  }
  const escapeAborts = event.code === "Escape" && !recording.mods.size && recording.button.dataset.bind !== "cancel";
  stopRecording(escapeAborts ? null : { code: event.code, mods: heldMods(event) });
}, true);

addEventListener("keyup", (event) => {
  if (!recording) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  // a modifier on its own, like right option, is a fine hold key
  if (recording.mods.has(event.code)) stopRecording({ code: event.code, mods: heldMods(event) });
}, true);

addEventListener("pointerdown", (event) => {
  if (recording && !recording.button.contains(event.target)) stopRecording();
}, true);

/* demo input: the hold binding, or press and hold the pill */

const isTyping = () => {
  const el = document.activeElement;
  return el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName));
};

let heldKey = null;
addEventListener("keydown", (event) => {
  if (demo.state === "listening" && matches(bindings.cancel, event)) {
    event.preventDefault();
    stopAuto();
    cancelDictation();
    heldKey = null;
    return;
  }
  if (!deskVisible || !matches(bindings.hold, event)) return;
  if (isTyping() && typesText(bindings.hold)) return;
  event.preventDefault();
  if (event.repeat || heldKey) return;
  heldKey = event.code;
  startDictation();
});

addEventListener("keyup", (event) => {
  if (event.code !== heldKey) return;
  event.preventDefault();
  heldKey = null;
  finishDictation();
});

addEventListener("blur", () => {
  if (recording) stopRecording();
  if (heldKey) { heldKey = null; finishDictation(); }
});

pill.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  pill.setPointerCapture(event.pointerId);
  startDictation();
});
for (const type of ["pointerup", "pointercancel"]) {
  pill.addEventListener(type, () => finishDictation());
}
pill.addEventListener("keydown", (event) => {
  if (event.key === "Enter") event.preventDefault();
});

field.addEventListener("focus", stopAuto);

if (reduceMotion) demo.auto = false;
else scheduleAuto(1400);

/* wordmark fills the desk edge to edge */

const wordmark = $(".wordmark");
function fitWordmark() {
  wordmark.style.fontSize = "";
  const size = parseFloat(getComputedStyle(wordmark).fontSize);
  const width = wordmark.firstElementChild.getBoundingClientRect().width;
  const pad = parseFloat(getComputedStyle(desk).paddingLeft);
  wordmark.style.fontSize = `${size * (desk.clientWidth - pad * 2) / width}px`;
}
// section headlines: one line, edge to edge, on wide screens only
function fitHeadlines() {
  for (const el of $$("h2[data-fit]")) {
    el.style.fontSize = "";
    if (innerWidth <= 980) continue;
    const range = document.createRange();
    range.selectNodeContents(el);
    const width = range.getBoundingClientRect().width;
    el.style.fontSize = `${parseFloat(getComputedStyle(el).fontSize) * el.clientWidth / width}px`;
  }
}
const fitAll = () => { fitWordmark(); fitHeadlines(); };
document.fonts.ready.then(fitAll);
addEventListener("resize", fitAll);

/* copy button */

const copyButton = $("[data-copy]");
copyButton.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("[data-copy-src]").textContent);
    copyButton.textContent = "copied";
  } catch {
    copyButton.textContent = "select it";
  }
  setTimeout(() => { copyButton.textContent = "copy"; }, 1600);
});

/* pill waveform */

const wave = $("[data-wave]");
const waveCtx = wave.getContext("2d");
const bars = new Array(30).fill(0);
let lastBar = 0;
function drawWave(t) {
  if (t - lastBar > 55) {
    lastBar = t;
    bars.shift();
    const talking = demo.state === "listening";
    bars.push(talking ? Math.min(1, 0.15 + Math.random() * 0.85 * (0.6 + 0.4 * Math.sin(t / 180))) : 0);
  }
  const ratio = devicePixelRatio || 1;
  const cw = wave.clientWidth * ratio;
  const ch = wave.clientHeight * ratio;
  if (wave.width !== cw) { wave.width = cw; wave.height = ch; }
  waveCtx.clearRect(0, 0, cw, ch);
  const step = cw / bars.length;
  const live = demo.state === "listening";
  waveCtx.fillStyle = live ? "#d5f66b" : "rgba(237,241,232,0.28)";
  bars.forEach((b, i) => {
    const h = Math.max(2 * ratio, b * ch);
    const bw = Math.max(2 * ratio, step * 0.45);
    waveCtx.beginPath();
    waveCtx.roundRect(i * step + (step - bw) / 2, (ch - h) / 2, bw, h, bw / 2);
    waveCtx.fill();
  });
  const elapsed = live ? Math.max(0, t - demo.startedAt) / 1000 : 0;
  timer.textContent = `${Math.floor(elapsed / 60)}:${String(Math.floor(elapsed % 60)).padStart(2, "0")}`;
}

function frame(t) {
  if (deskVisible) drawWave(t);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

/* signal chain: one spoken sentence through each pass */

const chain = $("[data-chain]");
const output = $("[data-output]");
const outputTarget = $("[data-output-target]");
const passes = { cleanup: false, dictionary: false, style: false, shorter: false };
let appStyle = "slack";

// {sb} and {nx} are the words the dictionary fixes
const SAID = "[um] [so] the bug is in the {sb} client [uh] can you make the {nx} route return early instead of nesting everything";
const CLEAN = {
  plain: "The bug is in the {sb} client. Can you make the {nx} route return early instead of nesting everything?",
  notes: "The bug is in the {sb} client. Make the {nx} route return early instead of nesting everything.",
  slack: "bug's in the {sb} client, can you make the {nx} route return early instead of nesting everything?",
  mail: "Hi, the bug is in the {sb} client. Could you update the {nx} route to return early rather than nesting everything? Thanks.",
};
const SHORT = {
  plain: "Bug's in the {sb} client. Make the {nx} route return early.",
  notes: "Bug in the {sb} client. {nx} route should return early.",
  slack: "bug's in the {sb} client, make the {nx} route return early?",
  mail: "Hi, the bug is in the {sb} client. Could the {nx} route return early? Thanks.",
};

function chainText() {
  const words = passes.dictionary ? { sb: "Supabase", nx: "Next.js" } : { sb: "super base", nx: "next js" };
  const style = passes.style && passes.cleanup ? appStyle : "plain";
  let text;
  if (!passes.cleanup) text = passes.shorter ? SHORT.plain.toLowerCase().replace(/[.?]/g, "") : SAID;
  else text = (passes.shorter ? SHORT : CLEAN)[style];
  return text.replace(/\{(\w+)\}/g, (_, key) => words[key]);
}

// word-level diff against the previous render so changes flash lime
let previousWords = [];
function renderChain() {
  const words = chainText().split(" ");
  const old = new Set(previousWords.map((w) => w.replace(/[[\]]/g, "")));
  output.replaceChildren();
  words.forEach((word, i) => {
    const filler = /^\[.*\]$/.test(word);
    const text = word.replace(/[[\]]/g, "");
    const span = document.createElement("span");
    span.textContent = text;
    if (filler) span.className = "filler";
    else if (previousWords.length && !old.has(text)) span.className = "changed";
    output.append(span, i < words.length - 1 ? " " : "");
  });
  previousWords = words;
  requestAnimationFrame(() => requestAnimationFrame(() => {
    for (const el of $$(".changed", output)) el.classList.add("settled");
  }));

  const anyOn = Object.values(passes).some(Boolean);
  chain.classList.toggle("is-on", anyOn);
  outputTarget.textContent = !anyOn ? "as said" : passes.style && passes.cleanup ? `in ${appStyle}` : "cleaned up";
}

for (const stomp of $$(".stomp", chain)) {
  stomp.addEventListener("click", () => {
    const name = stomp.dataset.pass;
    passes[name] = !passes[name];
    stomp.setAttribute("aria-pressed", passes[name]);
    stomp.closest(".pedal").toggleAttribute("data-on", passes[name]);
    autoChain.cancel();
    renderChain();
  });
}

const styleButtons = $$("[data-style]", chain);
function setStyle(name) {
  appStyle = name;
  for (const b of styleButtons) b.setAttribute("aria-checked", b.dataset.style === name);
}
for (const b of styleButtons) {
  b.addEventListener("click", () => {
    setStyle(b.dataset.style);
    if (!passes.style) $('[data-pass="style"]', chain).click();
    else renderChain();
  });
}
setStyle(appStyle);

// the first time the board scrolls into view, stomp the pedals on one by one
const autoChain = {
  timers: [],
  cancel() { this.timers.forEach(clearTimeout); this.timers = []; },
};
function stompAll(delay) {
  ["cleanup", "dictionary", "style", "shorter"].forEach((name, i) => {
    autoChain.timers.push(setTimeout(() => {
      const stomp = $(`[data-pass="${name}"]`, chain);
      if (!passes[name]) {
        passes[name] = true;
        stomp.setAttribute("aria-pressed", "true");
        stomp.closest(".pedal").toggleAttribute("data-on", true);
        renderChain();
      }
    }, delay * (i + 1)));
  });
}

renderChain();
if (reduceMotion) {
  stompAll(0);
} else {
  const once = new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) return;
    once.disconnect();
    stompAll(900);
  }, { threshold: 0.6 });
  once.observe($(".board", chain));
}

/* on a phone a dmg is useless: hand the page to the share sheet (AirDrop to your mac) */

if (matchMedia("(hover: none)").matches && navigator.share) {
  for (const link of $$("[data-download]")) {
    link.textContent = "send it to your mac";
    link.addEventListener("click", (event) => {
      event.preventDefault();
      navigator.share({ title: "computer, listen", text: "on-device dictation for macOS", url: location.origin + location.pathname }).catch(() => {});
    });
  }
}
