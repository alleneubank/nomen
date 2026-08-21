const CATEGORIES = [
  "mountains",
  "rivers",
  "deserts",
  "canyons",
  "islands",
  "passes",
  "moons",
  "raptors",
  "minerals",
  "norse",
  "volcanoes",
  "forests",
  "oceans",
  "storms",
];

const WATER = new Set(["rivers", "oceans", "islands"]);

const STRATEGIES = ["thematic", "phrase", "triple", "mnemonic", "construct"];

const PATTERNS = [
  ["adjective_noun", "adjective-noun"],
  ["noun_noun", "noun-noun"],
  ["verb_noun", "verb-noun"],
  ["alliterative", "alliterative"],
];

const TECHNIQUES = [
  "portmanteau",
  "compound",
  "clip",
  "affix",
  "backform",
  "phonosym",
  "acronym",
];

const COUNTS = ["1", "3", "5", "8"];

const DEFAULT_COLS = [
  "phrase:adjective_noun",
  "phrase:noun_noun",
  "phrase:verb_noun",
  "phrase:alliterative",
];

const SHEET_OPTIONS = [
  ...PATTERNS.map(([id, label]) => [`phrase:${id}`, label]),
  ["triple", "triple"],
  ...TECHNIQUES.map((t) => [`construct:${t}`, t]),
];

const LIST_OPTIONS = CATEGORIES.map((c) => [`thematic:${c}`, c]);

const COL_OPTIONS = [...SHEET_OPTIONS, ...LIST_OPTIONS];

const ERR = {
  [-1]: "Unknown strategy.",
  [-2]: "Unknown category.",
  [-3]: "Input does not match this strategy.",
  [-4]: "Generation failed.",
  [-5]: "Cannot make that many distinct names. Lower the count.",
  [-6]: "Construction failed. Try different seed words.",
  [-7]: "Mnemonic needs a numeric or hex input.",
  [-8]: "Count must be between 1 and 16.",
  [-9]: "Output did not fit the buffer.",
};

const sheet = document.getElementById("sheet");
const nameEl = document.getElementById("name");
const metaCat = document.getElementById("meta-cat");
const metaStrat = document.getElementById("meta-strat");
const metaSeed = document.getElementById("meta-seed");
const batchEl = document.getElementById("batch");
const ledgerHead = document.getElementById("ledger-head");
const ledgerBody = document.getElementById("ledger-body");
const ledgerTable = document.querySelector(".ledger");
const statusEl = document.getElementById("status");
const seedEl = document.getElementById("seed");
const holdEl = document.getElementById("hold");
const inputEl = document.getElementById("input");
const copyBtn = document.getElementById("copy");
const againBtn = document.getElementById("again");
const randomBtn = document.getElementById("random");
const plate = document.querySelector(".plate");

let wasm = null;
let ready = false;
let lastValue = "denali";
let debounceTimer = 0;

function radio(name, value, label, checked, extraClass) {
  return option("radio", name, value, label, checked, extraClass);
}

function checkbox(name, value, label, checked, extraClass) {
  return option("checkbox", name, value, label, checked, extraClass);
}

function option(type, name, value, label, checked, extraClass) {
  const el = document.createElement("label");
  el.className = extraClass ? `opt ${extraClass}` : "opt";
  const input = document.createElement("input");
  input.type = type;
  input.name = name;
  input.value = value;
  input.checked = checked;
  el.append(input, document.createTextNode(label));
  return el;
}

function fillControls() {
  const strategyBox = document.getElementById("strategy-opts");
  STRATEGIES.forEach((s, i) => strategyBox.append(radio("strategy", s, s, i === 0)));

  const patternBox = document.getElementById("pattern-opts");
  PATTERNS.forEach(([value, label], i) =>
    patternBox.append(radio("pattern", value, label, i === 0)),
  );

  const techBox = document.getElementById("technique-opts");
  TECHNIQUES.forEach((t, i) => techBox.append(radio("technique", t, t, i === 0)));

  const catBox = document.getElementById("category-opts");
  catBox.append(radio("category", "", "any", true));
  CATEGORIES.forEach((c) =>
    catBox.append(radio("category", c, c, false, WATER.has(c) ? "is-water" : "")),
  );

  const colBox = document.getElementById("col-opts");
  SHEET_OPTIONS.forEach(([value, label]) => {
    colBox.append(checkbox("col", value, label, DEFAULT_COLS.includes(value)));
  });

  const listBox = document.getElementById("list-opts");
  LIST_OPTIONS.forEach(([value, label]) => {
    listBox.append(
      checkbox("col", value, label, false, WATER.has(label) ? "is-water" : ""),
    );
  });

  const countBox = document.getElementById("count-opts");
  COUNTS.forEach((n) => countBox.append(radio("count", n, n, n === "5")));
}

function chosen(name) {
  const found = sheet.querySelector(`input[name="${name}"]:checked`);
  return found ? found.value : "";
}

function chosenAll(name) {
  return [...sheet.querySelectorAll(`input[name="${name}"]:checked`)].map((el) => el.value);
}

function syncSheet() {
  const strategy = chosen("strategy");
  sheet.classList.toggle("is-thematic", strategy === "thematic");
  sheet.classList.toggle("is-phrase", strategy === "phrase");
  sheet.classList.toggle("is-triple", strategy === "triple");
  sheet.classList.toggle("is-mnemonic", strategy === "mnemonic");
  sheet.classList.toggle("is-construct", strategy === "construct");
  sheet.classList.toggle("needs-input", strategy === "mnemonic" || strategy === "construct");

  if (strategy === "mnemonic") {
    inputEl.placeholder = "0xdeadbeef";
    inputEl.setAttribute("aria-label", "numeric or hex input");
  } else if (strategy === "construct") {
    const tech = chosen("technique");
    inputEl.placeholder =
      tech === "phonosym" ? "sharp, soft, or rhythmic" : "spell,master";
    inputEl.setAttribute("aria-label", "construct seed words");
  } else {
    inputEl.placeholder = "";
  }
}

function strategyTag() {
  const strategy = chosen("strategy");
  if (strategy === "phrase") return `phrase:${chosen("pattern")}`;
  if (strategy === "construct") return `construct:${chosen("technique")}`;
  return strategy;
}

function plateKey() {
  const tag = strategyTag();
  const category = chosen("category");
  if (tag === "thematic" && category) return `thematic:${category}`;
  return tag;
}

function randomSeed() {
  const bytes = new Uint32Array(2);
  crypto.getRandomValues(bytes);
  return (BigInt(bytes[1]) << 32n) | BigInt(bytes[0]);
}

function readSeed() {
  const raw = seedEl.value.trim();
  if (!raw) return randomSeed();
  try {
    return BigInt(raw);
  } catch {
    statusEl.textContent = "Seed must be an unsigned integer.";
    return null;
  }
}

function writeBytes(ptr, cap, text) {
  const encoded = new TextEncoder().encode(text);
  if (encoded.length > cap) return -1;
  const mem = new Uint8Array(wasm.memory.buffer);
  mem.set(encoded, ptr);
  return encoded.length;
}

function draw(tag, category, input, count, seed) {
  const sLen = writeBytes(wasm.nomenStrategyPtr(), wasm.nomenStrategyCap(), tag);
  const cLen = writeBytes(wasm.nomenCategoryPtr(), wasm.nomenCategoryCap(), category);
  const iLen = writeBytes(wasm.nomenInputPtr(), wasm.nomenInputCap(), input);
  if (sLen < 0 || cLen < 0 || iLen < 0) return { error: -3 };
  const lo = Number(seed & 0xffffffffn);
  const hi = Number(seed >> 32n);
  const n = wasm.nomenGenerate(sLen, cLen, iLen, count, lo, hi);
  if (n < 0) return { error: n };
  const mem = new Uint8Array(wasm.memory.buffer);
  const ptr = wasm.nomenOutPtr();
  const json = new TextDecoder().decode(mem.slice(ptr, ptr + n));
  try {
    const parsed = JSON.parse(json);
    return { names: Array.isArray(parsed) ? parsed : [parsed] };
  } catch {
    return { error: -9 };
  }
}

function columnSpec(key) {
  if (key.startsWith("thematic:")) {
    const category = key.slice("thematic:".length);
    return { key, tag: "thematic", category, label: category, input: "" };
  }
  if (key.startsWith("construct:")) {
    let input = inputEl.value.trim().toLowerCase();
    if (input.includes(" ")) input = input.replace(/\s+/g, ",");
    return { key, tag: key, category: "", label: key.slice("construct:".length), input };
  }
  const found = COL_OPTIONS.find(([value]) => value === key);
  return { key, tag: key, category: "", label: found ? found[1] : key, input: "" };
}

function generate(opts = {}) {
  statusEl.textContent = "";
  if (!wasm) {
    statusEl.textContent = "Build the playground with zig build wasm, then reload.";
    return;
  }

  if (opts.refreshSeed && !holdEl.checked) {
    seedEl.value = String(randomSeed());
  }
  const seed = readSeed();
  if (seed === null) return;

  const tag = strategyTag();
  const category = chosen("category");
  const count = Number(chosen("count"));
  let input = inputEl.value.trim().toLowerCase();
  if (tag.startsWith("construct:") && input.includes(" ")) {
    input = input.replace(/\s+/g, ",");
  }

  const plateDraw = draw(tag, category, input, count, seed);
  if (plateDraw.error) {
    statusEl.textContent = ERR[plateDraw.error] || "Generation failed.";
  } else {
    renderPlate(plateDraw.names, seed, tag);
  }
  renderLedger(seed, count);
  syncUrl();
}

function renderPlate(names, seed, tag) {
  if (names.length === 0) return;
  const first = names[0];
  lastValue = first.value;
  nameEl.classList.add("is-updating");
  const apply = () => {
    nameEl.textContent = first.value;
    nameEl.classList.remove("is-updating");
  };
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    apply();
  } else {
    window.setTimeout(apply, 80);
  }

  metaCat.textContent = first.category || "any";
  metaStrat.textContent = first.strategy;
  metaSeed.textContent = String(seed);
  plate.classList.toggle("is-water", WATER.has(first.category));

  const phraseOnPlate = tag.startsWith("phrase:");
  if (!phraseOnPlate && names.length > 1) {
    batchEl.hidden = false;
    batchEl.replaceChildren(
      ...names.slice(1).map((item) => {
        const li = document.createElement("li");
        li.textContent = item.value;
        return li;
      }),
    );
  } else {
    batchEl.hidden = true;
    batchEl.replaceChildren();
  }
}

function renderLedger(seed, count) {
  const keys = chosenAll("col");
  const current = plateKey();
  const cols = keys.map(columnSpec);
  const tr = document.createElement("tr");
  cols.forEach((col) => {
    const th = document.createElement("th");
    th.scope = "col";
    th.textContent = col.label;
    th.classList.toggle("is-current", col.key === current);
    tr.append(th);
  });
  ledgerHead.replaceChildren(tr);
  ledgerTable.style.minWidth = cols.length ? `${Math.max(40, cols.length * 10)}rem` : "0";

  if (cols.length === 0) {
    ledgerBody.replaceChildren();
    return;
  }

  const columns = cols.map((col) => {
    const result = draw(col.tag, col.category, col.input, count, seed);
    return result.names ? result.names.map((item) => item.value) : [];
  });
  const rows = Math.max(...columns.map((col) => col.length), 0);
  const body = [];
  for (let i = 0; i < rows; i += 1) {
    const row = document.createElement("tr");
    columns.forEach((col) => {
      const td = document.createElement("td");
      const value = col[i];
      if (value) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = value;
        button.addEventListener("click", () => copyValue(value, button));
        td.append(button);
      }
      row.append(td);
    });
    body.push(row);
  }
  ledgerBody.replaceChildren(...body);
}

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function randomize() {
  const strategy = pick(STRATEGIES);
  const technique = pick(TECHNIQUES);
  check("strategy", strategy);
  check("pattern", pick(PATTERNS)[0]);
  check("technique", technique);
  check("category", pick(["", ...CATEGORIES]));
  check("count", pick(COUNTS));
  if (strategy === "mnemonic") {
    const n = crypto.getRandomValues(new Uint32Array(1))[0];
    inputEl.value = `0x${n.toString(16)}`;
  } else if (strategy === "construct" && technique === "phonosym") {
    inputEl.value = pick(["sharp", "soft", "rhythmic"]);
  } else {
    inputEl.value = "";
  }
  syncSheet();
  generate({ refreshSeed: true });
}

async function copyValue(value, el) {
  try {
    await navigator.clipboard.writeText(value);
    lastValue = value;
    if (el) {
      el.classList.add("is-copied");
      window.setTimeout(() => el.classList.remove("is-copied"), 1200);
    }
    if (el === copyBtn || !el) {
      copyBtn.textContent = "Copied";
      window.setTimeout(() => {
        copyBtn.textContent = "Copy";
      }, 1200);
    }
  } catch {
    statusEl.textContent = "Copy failed.";
  }
}

function syncUrl() {
  const params = new URLSearchParams();
  params.set("s", strategyTag());
  const category = chosen("category");
  if (category) params.set("c", category);
  const count = chosen("count");
  if (count !== "5") params.set("n", count);
  if (holdEl.checked) {
    params.set("seed", seedEl.value.trim());
    params.set("hold", "1");
  }
  const input = inputEl.value.trim();
  if (input) params.set("i", input);
  const cols = chosenAll("col");
  const sameDefault =
    cols.length === DEFAULT_COLS.length && DEFAULT_COLS.every((key, i) => cols[i] === key);
  if (!sameDefault && cols.length) params.set("cols", cols.join(","));
  const qs = params.toString();
  history.replaceState(null, "", qs ? `?${qs}` : location.pathname);
}

function applyUrl() {
  const params = new URLSearchParams(location.search);
  const strategyParam = params.get("s") || "thematic";
  let strategy = strategyParam;
  let pattern = "adjective_noun";
  let technique = "portmanteau";
  if (strategyParam.startsWith("phrase:")) {
    strategy = "phrase";
    pattern = strategyParam.slice("phrase:".length);
  } else if (strategyParam.startsWith("construct:")) {
    strategy = "construct";
    technique = strategyParam.slice("construct:".length);
  }
  check("strategy", strategy);
  check("pattern", pattern);
  check("technique", technique);
  check("category", params.get("c") || "");
  check("count", params.get("n") || "5");
  if (params.has("seed")) seedEl.value = params.get("seed");
  holdEl.checked = params.get("hold") === "1";
  if (params.has("i")) inputEl.value = params.get("i");
  if (params.has("cols")) {
    const want = new Set(params.get("cols").split(",").filter(Boolean));
    sheet.querySelectorAll('input[name="col"]').forEach((input) => {
      input.checked = want.has(input.value);
    });
  }
  syncSheet();
}

function check(name, value) {
  const input = sheet.querySelector(`input[name="${name}"][value="${CSS.escape(value)}"]`);
  if (input) input.checked = true;
}

function onControlChange(event) {
  syncSheet();
  if (!ready) return;
  const id = event.target.id;
  if (id === "seed" || id === "input") return;
  generate({ refreshSeed: false });
}

function onTyped() {
  window.clearTimeout(debounceTimer);
  debounceTimer = window.setTimeout(() => {
    if (ready) generate({ refreshSeed: false });
  }, 280);
}

async function boot() {
  fillControls();
  applyUrl();
  sheet.addEventListener("change", onControlChange);
  sheet.addEventListener("submit", (event) => {
    event.preventDefault();
    generate({ refreshSeed: true });
  });
  seedEl.addEventListener("input", onTyped);
  inputEl.addEventListener("input", onTyped);
  againBtn.addEventListener("click", () => generate({ refreshSeed: true }));
  randomBtn.addEventListener("click", randomize);
  copyBtn.addEventListener("click", () => copyValue(lastValue, copyBtn));

  try {
    const response = await fetch("nomen.wasm");
    if (!response.ok) throw new Error("missing wasm");
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes);
    wasm = instance.exports;
    generate({ refreshSeed: false });
    ready = true;
  } catch {
    statusEl.textContent = "Build the playground with zig build wasm, then reload.";
  }
}

boot();
