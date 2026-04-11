const STORAGE_KEY = "manifold.remote.connection.v1";
const SURFACE_KEY_PREFIX = "manifold.remote.surface.v1:";
const FX_PARAM_NAMES = {
  0: ["Rate", "Depth", "Feedback", "Spread", "Voices"],
  1: ["Rate", "Depth", "Feedback", "Spread", "Stages"],
  2: ["Drive", "Curve", "Output", "Bias"],
  3: ["Threshold", "Ratio", "Attack", "Release", "Knee"],
  4: ["Width", "MonoLow"],
  5: ["Cutoff", "Reso"],
  6: ["Cutoff", "Reso", "Drive"],
  7: ["Room", "Damp"],
  8: ["Time", "Feedback"],
  9: ["Taps", "Feedback"],
  10: ["Pitch", "Window", "Feedback"],
  11: ["Grain", "Density", "Position", "Spray"],
  12: ["Freq", "Depth", "Spread"],
  13: ["Vowel", "Shift", "Reso", "Drive"],
  14: ["Low", "High", "Mid"],
  15: ["Threshold", "Drive", "Release", "SoftClip"],
  16: ["Attack", "Sustain", "Sensitivity"],
  17: ["Bits", "Rate", "Output"],
  18: ["Size", "Pitch", "Feedback", "Filter"],
  19: ["Time", "Window", "Feedback"],
  20: ["Length", "Gate", "Prob", "Filter"],
};

const state = {
  lastHost: "127.0.0.1",
  lastPort: 9011,
  targets: new Map(),
  activeTargetId: null,
};

const dom = {
  connectForm: document.querySelector("#connectForm"),
  hostInput: document.querySelector("#hostInput"),
  portInput: document.querySelector("#portInput"),
  targetNav: document.querySelector("#targetNav"),
  statusText: document.querySelector("#statusText"),
  connectionMeta: document.querySelector("#connectionMeta"),
  endpointList: document.querySelector("#endpointList"),
  genericGroups: document.querySelector("#genericGroups"),
  layoutRoot: document.querySelector("#layoutRoot"),
  customSurface: document.querySelector("#customSurface"),
  searchInput: document.querySelector("#searchInput"),
  reloadLayoutButton: document.querySelector("#reloadLayoutButton"),
  saveSurfaceButton: document.querySelector("#saveSurfaceButton"),
  clearSurfaceButton: document.querySelector("#clearSurfaceButton"),
  tabButtons: Array.from(document.querySelectorAll(".tab-button")),
  tabPanels: {
    generic: document.querySelector("#genericTab"),
    layout: document.querySelector("#layoutTab"),
    custom: document.querySelector("#customTab"),
  },
};

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function prettyLabel(text) {
  return String(text || "")
    .replace(/^\/+/, "")
    .split("/")
    .pop()
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatValue(value) {
  if (typeof value === "number") {
    if (Number.isInteger(value)) return String(value);
    return value.toFixed(Math.abs(value) >= 100 ? 1 : 3).replace(/\.0+$/, "").replace(/(\.\d*?)0+$/, "$1");
  }
  if (typeof value === "boolean") return value ? "On" : "Off";
  if (value == null) return "—";
  if (Array.isArray(value)) return value.map(formatValue).join(", ");
  return String(value);
}

function fxParamIndexForPath(path) {
  const match = String(path || "").match(/^\/plugin\/params\/p\/(\d+)$/);
  return match ? Number(match[1]) : null;
}

function targetId(host, port) {
  return `${host}:${port}`;
}

function activeTarget() {
  return state.activeTargetId ? state.targets.get(state.activeTargetId) || null : null;
}

function makeElement(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function loadSavedConnection() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
    if (saved && saved.host && saved.port) {
      state.lastHost = saved.host;
      state.lastPort = saved.port;
    }
  } catch (error) {
    console.warn("failed to load connection prefs", error);
  }
}

function saveConnection(host, port) {
  state.lastHost = host;
  state.lastPort = port;
  localStorage.setItem(STORAGE_KEY, JSON.stringify({ host, port }));
}

function getSurfaceStorageKey(target) {
  return `${SURFACE_KEY_PREFIX}${target.id}`;
}

function loadSurface(target) {
  try {
    const raw = localStorage.getItem(getSurfaceStorageKey(target));
    target.currentSurface = raw ? JSON.parse(raw) : [];
  } catch (error) {
    console.warn("failed to load custom surface", error);
    target.currentSurface = [];
  }
}

function saveSurface(target) {
  localStorage.setItem(getSurfaceStorageKey(target), JSON.stringify(target.currentSurface));
  setTargetStatus(target, `Saved custom surface for ${target.id}`, "ok");
}

function setStatus(text, kind = "") {
  dom.statusText.textContent = text;
  dom.statusText.className = kind === "error" ? "state-error" : kind === "ok" ? "state-ok" : "";
}

function setTargetStatus(target, text, kind = "") {
  target.statusText = text;
  target.statusKind = kind;
  if (activeTarget() === target) {
    setStatus(text, kind);
  }
}

function updateConnectionMeta() {
  const target = activeTarget();
  if (!target) {
    dom.connectionMeta.textContent = "";
    setStatus("Disconnected");
    return;
  }
  const meta = [];
  if (target.layout?.name) meta.push(target.layout.name);
  else if (target.uiMeta?.name) meta.push(target.uiMeta.name);
  else if (target.hostInfo?.NAME) meta.push(target.hostInfo.NAME);
  if (target.hostInfo?.OSC_PORT) meta.push(`OSC ${target.hostInfo.OSC_PORT}`);
  if (target.hostInfo?.WS_PORT) meta.push(`WS ${target.hostInfo.WS_PORT}`);
  meta.push(`${target.endpoints.length} endpoints`);
  dom.connectionMeta.textContent = meta.join(" • ");
  setStatus(target.statusText || `Connected to ${target.id}`, target.statusKind || "ok");
}

function buildParamMetaMap(uiMeta) {
  const map = new Map();
  const params = uiMeta?.plugin?.params;
  if (!Array.isArray(params)) return map;
  params.forEach((param) => {
    if (param && typeof param.path === "string" && param.path) {
      map.set(param.path, param);
    }
  });
  return map;
}

function mergeMetadataIntoEndpoints(target, endpoints) {
  return endpoints.map((endpoint) => {
    const meta = target.paramMeta.get(endpoint.path);
    if (!meta) return endpoint;
    const merged = { ...endpoint };
    merged.meta = meta;
    merged.label = meta.hostParamName || meta.label || endpoint.label;
    merged.description = meta.description || endpoint.description;
    merged.kind = meta.hostParamKind || meta.kind || endpoint.kind;
    merged.choices = Array.isArray(meta.choices) ? meta.choices : endpoint.choices;
    merged.defaultValue = meta.default;
    merged.skew = meta.skew;
    merged.unit = meta.unit || meta.suffix || endpoint.unit;
    return merged;
  });
}

function groupKeyForPath(path) {
  const parts = String(path || "").split("/").filter(Boolean);
  if (parts.length <= 2) return `/${parts.join("/")}`;
  if (parts[0] === "plugin" && parts[1] === "params") {
    return parts.length > 3 ? `/plugin/params/${parts[2]}` : "/plugin/params";
  }
  return `/${parts.slice(0, Math.min(parts.length - 1, 3)).join("/")}`;
}

function hasRange(endpoint) {
  return Array.isArray(endpoint.range) && endpoint.range.length > 0;
}

function getRange(endpoint) {
  const item = hasRange(endpoint) ? endpoint.range[0] : null;
  return {
    min: item && Number.isFinite(Number(item.MIN)) ? Number(item.MIN) : 0,
    max: item && Number.isFinite(Number(item.MAX)) ? Number(item.MAX) : 1,
  };
}

function isWritable(endpoint) {
  return endpoint.access === 2 || endpoint.access === 3;
}

function isReadable(endpoint) {
  return endpoint.access === 1 || endpoint.access === 3;
}

function isBooleanish(endpoint) {
  const { min, max } = getRange(endpoint);
  const haystack = `${endpoint.label || ""} ${endpoint.description || ""} ${endpoint.path || ""}`.toLowerCase();
  const kind = String(endpoint.kind || endpoint.meta?.hostParamKind || "").toLowerCase();
  return endpoint.type === "T"
    || endpoint.type === "F"
    || kind === "bool"
    || (min === 0 && max === 1 && /\b(enable|enabled|bypass|toggle|on|off|mute|solo|link)\b/.test(haystack));
}

function inferWidgetType(target, endpoint) {
  const originalPath = String(endpoint.path || "");
  const path = originalPath.toLowerCase();
  const yCandidate = originalPath.endsWith("/x")
    ? originalPath.replace(/\/x$/, "/y")
    : originalPath.endsWith("/mix_x")
      ? originalPath.replace(/\/mix_x$/, "/mix_y")
      : "";
  if (yCandidate && target.endpointMap.has(yCandidate)) return "xy-x";
  if (path.endsWith("/y") || path.endsWith("/mix_y")) return "xy-y";
  if (Array.isArray(endpoint.choices) && endpoint.choices.length > 0) return "choice";
  if (isBooleanish(endpoint)) return "toggle";
  if (endpoint.type === "i") return "slider-int";
  if (endpoint.type === "f") return "slider";
  return hasRange(endpoint) ? "slider" : "readout";
}

function flattenOscTree(node, bucket = []) {
  if (!node || typeof node !== "object") return bucket;
  if (node.TYPE) {
    bucket.push({
      path: node.FULL_PATH,
      type: node.TYPE,
      access: Number(node.ACCESS || 0),
      description: node.DESCRIPTION || "",
      range: Array.isArray(node.RANGE) ? node.RANGE : [],
      fullPath: node.FULL_PATH,
      label: prettyLabel(node.FULL_PATH),
      group: groupKeyForPath(node.FULL_PATH),
    });
  }
  if (node.CONTENTS && typeof node.CONTENTS === "object") {
    Object.values(node.CONTENTS).forEach((child) => flattenOscTree(child, bucket));
  }
  return bucket;
}

function decodeOscString(bytes, offset) {
  let end = offset;
  while (end < bytes.length && bytes[end] !== 0) end += 1;
  const value = new TextDecoder().decode(bytes.slice(offset, end));
  const next = (end + 4) & ~3;
  return { value, next };
}

function readInt32(bytes, offset) {
  return new DataView(bytes.buffer, bytes.byteOffset + offset, 4).getInt32(0, false);
}

function readFloat32(bytes, offset) {
  return new DataView(bytes.buffer, bytes.byteOffset + offset, 4).getFloat32(0, false);
}

function decodeOscPacket(buffer) {
  const bytes = new Uint8Array(buffer);
  if (!bytes.length) return null;

  const pathPart = decodeOscString(bytes, 0);
  const typePart = decodeOscString(bytes, pathPart.next);
  const path = pathPart.value;
  const tags = typePart.value.startsWith(",") ? typePart.value.slice(1) : typePart.value;
  let offset = typePart.next;
  const args = [];

  for (const tag of tags) {
    if (tag === "f") {
      args.push(readFloat32(bytes, offset));
      offset += 4;
    } else if (tag === "i") {
      args.push(readInt32(bytes, offset));
      offset += 4;
    } else if (tag === "s") {
      const strPart = decodeOscString(bytes, offset);
      args.push(strPart.value);
      offset = strPart.next;
    } else if (tag === "T") {
      args.push(true);
    } else if (tag === "F") {
      args.push(false);
    } else if (tag === "N") {
      args.push(null);
    } else {
      console.warn("unsupported OSC type tag", tag, path);
      return null;
    }
  }

  return { path, args };
}

async function fetchJson(url, options = undefined) {
  const response = await fetch(url, options);
  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (error) {
    throw new Error(`Invalid JSON from ${url}: ${text.slice(0, 200)}`);
  }
  if (!response.ok) {
    const message = data?.error || data?.result || response.statusText;
    throw new Error(message);
  }
  return data;
}

async function queryValue(target, path) {
  const data = await fetchJson(`${target.baseUrl}/osc${path}`);
  return data?.VALUE;
}

async function sendCommand(target, command) {
  const data = await fetchJson(`${target.baseUrl}/api/command`, {
    method: "POST",
    headers: { "Content-Type": "text/plain" },
    body: command,
  });
  if (!data?.ok) throw new Error(data?.result || "command failed");
  return data;
}

async function writeValue(target, path, value, endpoint) {
  const widgetType = inferWidgetType(target, endpoint);
  const normalized = widgetType === "toggle" ? (value ? 1 : 0) : value;
  await sendCommand(target, `SET ${path} ${normalized}`);
  setLiveValue(target, path, widgetType === "toggle" ? Boolean(value) : value);
}

async function triggerPath(target, path) {
  await sendCommand(target, `TRIGGER ${path}`);
}

async function hydrateCurrentValues(target) {
  const readable = target.endpoints.filter((endpoint) => isReadable(endpoint));
  const concurrency = 12;
  let index = 0;

  async function worker() {
    while (index < readable.length) {
      const current = readable[index++];
      try {
        const value = await queryValue(target, current.path);
        if (value !== undefined) setLiveValue(target, current.path, value);
      } catch (error) {
        console.warn("value query failed", current.path, error);
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => worker()));
}

function closeSocket(target) {
  if (!target?.ws) return;
  try {
    target.ws.close();
  } catch (error) {
    console.warn("ws close failed", error);
  }
  target.ws = null;
}

function renderIfActive(target) {
  if (activeTarget() === target) renderActiveViews();
}

function beginInteraction(target, paths) {
  paths.forEach((path) => {
    if (path) target.interactingPaths.add(path);
  });
}

function endInteraction(target, paths) {
  paths.forEach((path) => {
    if (path) target.interactingPaths.delete(path);
  });
  scheduleRender(target);
}

function scheduleRender(target) {
  if (activeTarget() !== target) return;
  if (target.renderFrame) return;
  target.renderFrame = requestAnimationFrame(() => {
    target.renderFrame = 0;
    renderActiveViews();
  });
}

function connectWebSocket(target) {
  closeSocket(target);
  const socket = new WebSocket(target.wsUrl);
  socket.binaryType = "arraybuffer";

  socket.addEventListener("open", () => {
    setTargetStatus(target, `Connected to ${target.id}`, "ok");
    target.endpoints.forEach((endpoint) => {
      if (isReadable(endpoint)) {
        socket.send(JSON.stringify({ COMMAND: "LISTEN", DATA: endpoint.path }));
      }
    });
  });

  socket.addEventListener("message", (event) => {
    if (typeof event.data === "string") {
      console.debug("text ws message", event.data);
      return;
    }
    const decoded = decodeOscPacket(event.data);
    if (!decoded) return;
    setLiveValue(target, decoded.path, decoded.args.length <= 1 ? decoded.args[0] : decoded.args);
    if (decoded.path === "/plugin/params/type") {
      scheduleRender(target);
    } else if (!target.interactingPaths.has(decoded.path)) {
      scheduleRender(target);
    }
  });

  socket.addEventListener("close", () => {
    if (target.ws === socket) {
      target.ws = null;
      setTargetStatus(target, `Socket closed for ${target.id}`);
    }
  });

  socket.addEventListener("error", () => {
    setTargetStatus(target, `Socket error on ${target.wsUrl}`, "error");
  });

  target.ws = socket;
}

function usesLogScale(endpoint) {
  const { min, max } = getRange(endpoint);
  const key = `${endpoint.path || ""} ${endpoint.label || ""} ${endpoint.description || ""}`.toLowerCase();
  if (endpoint.meta?.display === "log") return true;
  if (typeof endpoint.skew === "number" && endpoint.skew > 0 && endpoint.skew < 0.9 && min > 0) return true;
  return min > 0 && max / Math.max(min, 1e-9) >= 50 && /(freq|frequency|cutoff|hz)/.test(key);
}

function formatEndpointValue(endpoint, value) {
  if (value == null) return "—";
  const choices = Array.isArray(endpoint.choices) ? endpoint.choices : null;
  if (choices && choices.length > 0) {
    const { min } = getRange(endpoint);
    const idx = Math.max(0, Math.min(choices.length - 1, Math.round(Number(value) - min)));
    return choices[idx] ?? formatValue(value);
  }
  const base = formatValue(value);
  const unit = endpoint.unit;
  if (!unit) return base;
  return `${base}${String(unit).startsWith(" ") ? unit : ` ${unit}`}`;
}

function sliderPositionFromValue(endpoint, value) {
  const { min, max } = getRange(endpoint);
  if (max === min) return 0;
  const numeric = clamp(toNumber(value, endpoint.defaultValue ?? min), min, max);
  if (usesLogScale(endpoint)) {
    const safeMin = Math.max(min, 1e-6);
    const safeMax = Math.max(max, safeMin * 1.0001);
    const safeValue = clamp(numeric, safeMin, safeMax);
    return clamp((Math.log(safeValue) - Math.log(safeMin)) / (Math.log(safeMax) - Math.log(safeMin)), 0, 1);
  }
  return clamp((numeric - min) / (max - min), 0, 1);
}

function sliderValueFromPosition(target, endpoint, position) {
  const { min, max } = getRange(endpoint);
  const t = clamp(position, 0, 1);
  let value;
  if (usesLogScale(endpoint)) {
    const safeMin = Math.max(min, 1e-6);
    const safeMax = Math.max(max, safeMin * 1.0001);
    value = Math.exp(Math.log(safeMin) + t * (Math.log(safeMax) - Math.log(safeMin)));
  } else {
    value = min + t * (max - min);
  }
  const kind = inferWidgetType(target, endpoint);
  if (kind === "slider-int" || endpoint.kind === "choice") {
    return Math.round(value);
  }
  return value;
}

function brightenHex(hex, amount) {
  const match = String(hex || "").trim().match(/^#?([0-9a-f]{6})$/i);
  if (!match) return hex;
  const value = match[1];
  const r = clamp(parseInt(value.slice(0, 2), 16) + amount, 0, 255);
  const g = clamp(parseInt(value.slice(2, 4), 16) + amount, 0, 255);
  const b = clamp(parseInt(value.slice(4, 6), 16) + amount, 0, 255);
  return `#${r.toString(16).padStart(2, "0")}${g.toString(16).padStart(2, "0")}${b.toString(16).padStart(2, "0")}`;
}

function createTarget(host, port) {
  return {
    id: targetId(host, port),
    host,
    port,
    baseUrl: `http://${host}:${port}`,
    wsUrl: "",
    hostInfo: null,
    uiMeta: null,
    paramMeta: new Map(),
    tree: null,
    endpoints: [],
    filteredEndpoints: [],
    endpointMap: new Map(),
    values: new Map(),
    ws: null,
    activeTab: "generic",
    search: "",
    currentSurface: [],
    layout: null,
    layoutState: {},
    statusText: `Connecting to ${host}:${port}...`,
    statusKind: "",
    name: `${host}:${port}`,
    accent: "#38bdf8",
    renderFrame: 0,
    layoutResizeObserver: null,
    interactingPaths: new Set(),
    liveBindings: new Map(),
  };
}

function deriveLayoutAccent(layout) {
  const queue = [layout?.root || layout];
  while (queue.length) {
    const node = queue.shift();
    if (!node || typeof node !== "object") continue;
    if (String(node.id || "").toLowerCase().includes("accent") && node.style?.bg) {
      return node.style.bg;
    }
    if (Array.isArray(node.children)) queue.push(...node.children);
  }
  return "#38bdf8";
}

function deriveTargetName(target) {
  return target.layout?.name || target.uiMeta?.name || target.hostInfo?.NAME || target.id;
}

function isFxTarget(target) {
  const name = String(target.layout?.name || target.uiMeta?.name || "").toLowerCase();
  return name.includes("effect") || name.includes("fx");
}

function getFxTypeIndex(target) {
  return Math.max(0, Math.floor(toNumber(target.values.get("/plugin/params/type"), 0)));
}

function getFxParamNames(target) {
  return FX_PARAM_NAMES[getFxTypeIndex(target)] || ["Param 1", "Param 2"];
}

function getFxAssignState(target) {
  const names = getFxParamNames(target);
  let xIdx = Math.max(1, Math.floor(toNumber(getLayoutStateValue(target, "fxXYXParam", 1), 1)));
  let yIdx = Math.max(1, Math.floor(toNumber(getLayoutStateValue(target, "fxXYYParam", Math.min(2, names.length)), Math.min(2, names.length))));
  if (xIdx > names.length) xIdx = 1;
  if (yIdx > names.length) yIdx = Math.min(2, names.length);
  if (yIdx < 1) yIdx = 1;
  target.layoutState.fxXYXParam = xIdx;
  target.layoutState.fxXYYParam = yIdx;
  return {
    xIdx,
    yIdx,
    names,
    xPath: `/plugin/params/p/${xIdx - 1}`,
    yPath: `/plugin/params/p/${yIdx - 1}`,
    xName: names[xIdx - 1] || `Param ${xIdx}`,
    yName: names[yIdx - 1] || `Param ${yIdx}`,
  };
}

function resolveDisplayLabel(target, endpoint, fallback = null) {
  const path = endpoint?.path || "";
  const fxParamIndex = fxParamIndexForPath(path);
  if (isFxTarget(target) && fxParamIndex != null) {
    const names = getFxParamNames(target);
    return names[fxParamIndex] || fallback || endpoint?.label || prettyLabel(path);
  }
  return fallback || endpoint?.label || prettyLabel(path);
}

function registerLiveBinding(target, path, updater) {
  if (!target || !path || typeof updater !== "function") return;
  let bindings = target.liveBindings.get(path);
  if (!bindings) {
    bindings = new Set();
    target.liveBindings.set(path, bindings);
  }
  bindings.add(updater);
}

function notifyLiveBindings(target, path) {
  const bindings = target?.liveBindings?.get(path);
  if (!bindings) return;
  bindings.forEach((updater) => {
    try {
      updater();
    } catch (error) {
      console.warn("live binding update failed", path, error);
    }
  });
}

function setLiveValue(target, path, value, options = {}) {
  target.values.set(path, value);
  notifyLiveBindings(target, path);
  if (options.scheduleRender) scheduleRender(target);
}

function applySearchFilter(target) {
  const q = target.search.trim().toLowerCase();
  if (!q) {
    target.filteredEndpoints = [...target.endpoints];
  } else {
    target.filteredEndpoints = target.endpoints.filter((endpoint) => {
      return endpoint.path.toLowerCase().includes(q)
        || endpoint.label.toLowerCase().includes(q)
        || String(endpoint.description || "").toLowerCase().includes(q);
    });
  }
  renderIfActive(target);
}

async function loadLayout(target, forceResetState = false) {
  try {
    const layout = await fetchJson(`${target.baseUrl}/ui/layout`);
    if (!layout || layout.error) throw new Error(layout?.error || "layout unavailable");
    target.layout = layout;
    if (forceResetState) target.layoutState = {};
    target.name = deriveTargetName(target);
    target.accent = deriveLayoutAccent(layout);
    renderIfActive(target);
  } catch (error) {
    target.layout = null;
    if (forceResetState) target.layoutState = {};
    renderIfActive(target);
  }
}

async function connectTarget(host, port) {
  const id = targetId(host, port);
  if (state.targets.has(id)) {
    switchActiveTarget(id);
    return;
  }

  const target = createTarget(host, port);
  loadSurface(target);
  state.targets.set(id, target);
  state.activeTargetId = id;
  saveConnection(host, port);
  renderTargetNav();
  renderActiveViews();

  try {
    const [hostInfo, tree, uiMeta] = await Promise.all([
      fetchJson(`${target.baseUrl}/?HOST_INFO`),
      fetchJson(`${target.baseUrl}/`),
      fetchJson(`${target.baseUrl}/ui/meta`).catch(() => null),
    ]);

    target.hostInfo = hostInfo;
    target.uiMeta = uiMeta;
    target.paramMeta = buildParamMetaMap(uiMeta);
    target.tree = tree;
    target.wsUrl = `ws://${target.host}:${Number(hostInfo?.WS_PORT || target.port)}`;
    target.endpoints = mergeMetadataIntoEndpoints(target, flattenOscTree(tree)).sort((a, b) => a.path.localeCompare(b.path));
    target.endpointMap = new Map(target.endpoints.map((endpoint) => [endpoint.path, endpoint]));
    target.values = new Map();
    target.name = deriveTargetName(target);
    applySearchFilter(target);
    renderTargetNav();
    renderIfActive(target);

    await Promise.all([
      hydrateCurrentValues(target),
      loadLayout(target, true),
    ]);

    connectWebSocket(target);
    setTargetStatus(target, `Connected to ${target.id}`, "ok");
    renderTargetNav();
    renderIfActive(target);
  } catch (error) {
    closeSocket(target);
    state.targets.delete(id);
    if (state.activeTargetId === id) {
      state.activeTargetId = state.targets.size ? Array.from(state.targets.keys())[0] : null;
    }
    setStatus(`Connection failed: ${error.message}`, "error");
    renderTargetNav();
    renderActiveViews();
    console.error(error);
  }
}

function disconnectTarget(id) {
  const target = state.targets.get(id);
  if (!target) return;
  closeSocket(target);
  if (target.layoutResizeObserver) {
    target.layoutResizeObserver.disconnect();
    target.layoutResizeObserver = null;
  }
  if (target.renderFrame) {
    cancelAnimationFrame(target.renderFrame);
    target.renderFrame = 0;
  }
  state.targets.delete(id);
  if (state.activeTargetId === id) {
    state.activeTargetId = state.targets.size ? Array.from(state.targets.keys())[0] : null;
  }
  renderTargetNav();
  renderActiveViews();
}

function switchActiveTarget(id) {
  if (!state.targets.has(id)) return;
  state.activeTargetId = id;
  const target = activeTarget();
  if (target) {
    dom.hostInput.value = target.host;
    dom.portInput.value = String(target.port);
    dom.searchInput.value = target.search || "";
  }
  renderTargetNav();
  renderActiveViews();
}

function renderTargetNav() {
  dom.targetNav.innerHTML = "";
  Array.from(state.targets.values()).forEach((target) => {
    const pill = makeElement("div", `target-pill ${target.id === state.activeTargetId ? "active" : ""}`);
    const dot = makeElement("span", "dot");
    dot.style.background = target.accent || "#38bdf8";
    const label = makeElement("span", "", target.name || target.id);
    const disconnect = makeElement("button", "disconnect", "×");
    disconnect.type = "button";
    disconnect.addEventListener("click", (event) => {
      event.stopPropagation();
      disconnectTarget(target.id);
    });
    pill.addEventListener("click", () => switchActiveTarget(target.id));
    pill.append(dot, label, disconnect);
    dom.targetNav.append(pill);
  });
}

function buildCompactSliderControl(target, endpoint, options = {}) {
  const path = endpoint.path;
  const value = target.values.get(path);
  const readableValue = value !== undefined ? value : (endpoint.defaultValue ?? getRange(endpoint).min);
  const position = sliderPositionFromValue(endpoint, readableValue);

  const wrap = makeElement("div", "slider-wrap");
  const shell = makeElement("label", "compact-slider-shell");
  const fill = makeElement("div", "compact-slider-fill");
  const input = document.createElement("input");
  input.type = "range";
  input.min = "0";
  input.max = "1000";
  input.step = "1";
  input.className = "compact-slider-input";
  input.value = String(Math.round(position * 1000));
  input.disabled = !isWritable(endpoint) || options.disabled === true;

  const overlay = makeElement("div", "compact-slider-overlay");
  const label = makeElement("span", "compact-slider-label", options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(path));
  const readout = makeElement("span", "compact-slider-value", formatEndpointValue(endpoint, readableValue));
  overlay.append(label, readout);

  const refreshFromState = () => {
    const liveValue = target.values.get(path);
    const actual = liveValue !== undefined ? liveValue : (endpoint.defaultValue ?? getRange(endpoint).min);
    const pos = sliderPositionFromValue(endpoint, actual);
    shell.style.setProperty("--fill", `${clamp(pos, 0, 1) * 100}%`);
    readout.textContent = formatEndpointValue(endpoint, actual);
    label.textContent = options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(path);
    if (!target.interactingPaths.has(path)) {
      input.value = String(Math.round(pos * 1000));
    }
  };

  const updatePreview = () => {
    const pos = Number(input.value) / 1000;
    const actual = sliderValueFromPosition(target, endpoint, pos);
    shell.style.setProperty("--fill", `${clamp(pos, 0, 1) * 100}%`);
    readout.textContent = formatEndpointValue(endpoint, actual);
  };

  let queuedValue = null;
  let sending = false;
  const flushLiveWrite = async () => {
    if (sending || queuedValue == null) return;
    sending = true;
    while (queuedValue != null) {
      const nextValue = queuedValue;
      queuedValue = null;
      try {
        await writeValue(target, path, nextValue, endpoint);
      } catch (error) {
        setTargetStatus(target, `Write failed: ${error.message}`, "error");
      }
    }
    sending = false;
  };

  input.addEventListener("pointerdown", () => beginInteraction(target, [path]));
  input.addEventListener("input", () => {
    updatePreview();
    const nextValue = sliderValueFromPosition(target, endpoint, Number(input.value) / 1000);
    setLiveValue(target, path, nextValue);
    queuedValue = nextValue;
    void flushLiveWrite();
  });
  const finishSliderInteraction = () => endInteraction(target, [path]);
  input.addEventListener("change", finishSliderInteraction);
  input.addEventListener("pointerup", finishSliderInteraction);
  input.addEventListener("pointercancel", finishSliderInteraction);

  shell.style.setProperty("--fill", `${position * 100}%`);
  registerLiveBinding(target, path, refreshFromState);
  shell.append(fill, input, overlay);
  wrap.append(shell);
  return wrap;
}

function buildChoiceControl(target, endpoint, options = null, disabled = false) {
  const wrap = makeElement("div", "choice-wrap");
  const select = document.createElement("select");
  select.className = "compact-select";
  const choices = Array.isArray(options) && options.length > 0 ? options : (Array.isArray(endpoint.choices) ? endpoint.choices : []);
  const { min } = getRange(endpoint);

  const refreshChoices = () => {
    const value = target.values.get(endpoint.path);
    const currentIndex = Math.max(0, Math.min(Math.max(choices.length - 1, 0), Math.round(toNumber(value, endpoint.defaultValue ?? min) - min)));
    Array.from(select.options).forEach((option, index) => {
      option.selected = index === currentIndex;
    });
  };

  choices.forEach((choice, index) => {
    const option = document.createElement("option");
    option.value = String(min + index);
    option.textContent = String(choice);
    select.append(option);
  });

  refreshChoices();
  registerLiveBinding(target, endpoint.path, refreshChoices);
  select.disabled = disabled || !isWritable(endpoint);
  select.addEventListener("change", async () => {
    setLiveValue(target, endpoint.path, Number(select.value), { scheduleRender: true });
    try {
      await writeValue(target, endpoint.path, Number(select.value), endpoint);
    } catch (error) {
      setTargetStatus(target, `Write failed: ${error.message}`, "error");
    }
  });

  wrap.append(select);
  return wrap;
}

function buildFilterGraphControl(target, bindConfig, style = {}, bounds = {}) {
  const panel = makeElement("div", "filter-graph-shell");
  const canvas = document.createElement("canvas");
  const width = Math.max(64, Math.floor(bounds.width || 452));
  const height = Math.max(48, Math.floor(bounds.height || 188));
  canvas.width = width;
  canvas.height = height;
  panel.append(canvas);

  const accent = style.accent || "#a78bfa";
  const minFreq = 80;
  const maxFreq = 16000;
  const minReso = 0.1;
  const maxReso = 2.0;
  const logMin = Math.log(minFreq);
  const logMax = Math.log(maxFreq);
  const dbRange = 14;
  const ctx2d = canvas.getContext("2d");

  const typeEndpoint = target.endpointMap.get(bindConfig.typePath) || { path: bindConfig.typePath, type: "i", access: 3, range: [{ MIN: 0, MAX: 3 }] };
  const cutoffEndpoint = target.endpointMap.get(bindConfig.cutoffPath) || { path: bindConfig.cutoffPath, type: "f", access: 3, range: [{ MIN: minFreq, MAX: maxFreq }] };
  const resonanceEndpoint = target.endpointMap.get(bindConfig.resonancePath) || { path: bindConfig.resonancePath, type: "f", access: 3, range: [{ MIN: minReso, MAX: maxReso }] };

  const xToFreq = (x) => {
    const t = clamp(x / Math.max(1, width), 0, 1);
    return Math.exp(logMin + t * (logMax - logMin));
  };
  const yToReso = (y) => {
    const t = 1 - clamp(y / Math.max(1, height), 0, 1);
    return minReso + t * (maxReso - minReso);
  };

  const svfMagnitude = (freq, cutoffHz, resonanceValue, filterType) => {
    const safeCutoff = Math.max(minFreq, cutoffHz);
    const w = freq / safeCutoff;
    if (w < 0.1) {
      if (filterType === 0 || filterType === 3) return 1.0;
      return 0.0;
    }
    if (w > 10) {
      if (filterType === 2 || filterType === 3) return 1.0;
      return 0.0;
    }
    const w2 = w * w;
    const q = Math.max(0.5, resonanceValue * 2);
    const denom = Math.max(1e-10, (1 - w2) * (1 - w2) + (w / q) * (w / q));
    if (filterType === 0) return 1.0 / Math.sqrt(denom);
    if (filterType === 1) return (w / q) / Math.sqrt(denom);
    if (filterType === 2) return w2 / Math.sqrt(denom);
    if (filterType === 3) return Math.sqrt(((1 - w2) * (1 - w2)) / denom);
    return 1.0;
  };

  const draw = () => {
    const typeValue = toNumber(target.values.get(bindConfig.typePath), 0);
    const cutoff = toNumber(target.values.get(bindConfig.cutoffPath), 3200);
    const resonance = toNumber(target.values.get(bindConfig.resonancePath), 0.75);

    ctx2d.clearRect(0, 0, width, height);
    ctx2d.fillStyle = style.bg || "#0d1420";
    ctx2d.fillRect(0, 0, width, height);
    ctx2d.strokeStyle = "#1a1a3a";
    ctx2d.lineWidth = 1;

    [100, 500, 1000, 5000, 10000].forEach((f) => {
      const x = (Math.log(f) - logMin) / (logMax - logMin) * width;
      ctx2d.beginPath();
      ctx2d.moveTo(x, 0);
      ctx2d.lineTo(x, height);
      ctx2d.stroke();
    });

    [-24, -12, 0, 12, 24].forEach((db) => {
      const y = height * 0.5 - (db / dbRange) * height * 0.45;
      ctx2d.strokeStyle = db === 0 ? "#1f2b4d" : "#1a1a3a";
      ctx2d.beginPath();
      ctx2d.moveTo(0, y);
      ctx2d.lineTo(width, y);
      ctx2d.stroke();
    });

    const cutoffX = (Math.log(Math.max(minFreq, Math.min(maxFreq, cutoff))) - logMin) / (logMax - logMin) * width;
    ctx2d.strokeStyle = accent;
    ctx2d.globalAlpha = 0.35;
    ctx2d.beginPath();
    ctx2d.moveTo(cutoffX, 0);
    ctx2d.lineTo(cutoffX, height);
    ctx2d.stroke();
    ctx2d.globalAlpha = 1;

    ctx2d.strokeStyle = accent;
    ctx2d.lineWidth = 2;
    ctx2d.beginPath();
    for (let i = 0; i <= 180; i += 1) {
      const t = i / 180;
      const freq = Math.exp(logMin + t * (logMax - logMin));
      const mag = svfMagnitude(freq, cutoff, clamp(resonance, minReso, maxReso), Math.round(typeValue));
      const db = clamp((20 * Math.log10(mag + 1e-10)), -dbRange, dbRange);
      const x = t * width;
      const y = height * 0.5 - (db / dbRange) * height * 0.45;
      if (i === 0) ctx2d.moveTo(x, y);
      else ctx2d.lineTo(x, y);
    }
    ctx2d.stroke();
  };

  let dragging = false;
  let queued = null;
  let sending = false;
  const flush = async () => {
    if (sending || !queued) return;
    sending = true;
    while (queued) {
      const next = queued;
      queued = null;
      try {
        await Promise.all([
          writeValue(target, bindConfig.cutoffPath, next.cutoff, cutoffEndpoint),
          writeValue(target, bindConfig.resonancePath, next.resonance, resonanceEndpoint),
        ]);
      } catch (error) {
        setTargetStatus(target, `Graph write failed: ${error.message}`, "error");
      }
    }
    sending = false;
  };

  const applyPoint = (event) => {
    const rect = canvas.getBoundingClientRect();
    const mx = (event.clientX - rect.left) / rect.width * width;
    const my = (event.clientY - rect.top) / rect.height * height;
    const cutoff = clamp(xToFreq(mx), minFreq, maxFreq);
    const resonance = clamp(yToReso(my), minReso, maxReso);
    setLiveValue(target, bindConfig.cutoffPath, cutoff);
    setLiveValue(target, bindConfig.resonancePath, resonance);
    queued = { cutoff, resonance };
    draw();
    void flush();
  };

  canvas.addEventListener("pointerdown", (event) => {
    dragging = true;
    beginInteraction(target, [bindConfig.cutoffPath, bindConfig.resonancePath]);
    canvas.setPointerCapture(event.pointerId);
    applyPoint(event);
  });
  canvas.addEventListener("pointermove", (event) => {
    if (dragging) applyPoint(event);
  });
  const endDrag = () => {
    dragging = false;
    endInteraction(target, [bindConfig.cutoffPath, bindConfig.resonancePath]);
  };
  canvas.addEventListener("pointerup", endDrag);
  canvas.addEventListener("pointercancel", endDrag);

  draw();
  return panel;
}

function getLayoutStateValue(target, key, fallback) {
  if (!key) return fallback;
  return target.layoutState[key] ?? fallback;
}

function setLayoutStateValue(target, key, value) {
  if (!key) return;
  target.layoutState[key] = value;
}

function buildEqGraphControl(target, bindConfig, style = {}, bounds = {}) {
  const panel = makeElement("div", "filter-graph-shell");
  const canvas = document.createElement("canvas");
  const width = Math.max(120, Math.floor(bounds.width || 452));
  const height = Math.max(72, Math.floor(bounds.height || 108));
  canvas.width = width;
  canvas.height = height;
  panel.append(canvas);

  const ctx2d = canvas.getContext("2d");
  const minFreq = 20;
  const maxFreq = 20000;
  const logMin = Math.log(minFreq);
  const logMax = Math.log(maxFreq);
  const minGain = -24;
  const maxGain = 24;
  const minQ = 0.1;
  const maxQ = 24;
  const sampleRate = 48000;
  const bandBase = bindConfig.bandBasePath || "/plugin/params/band";
  const selectedBandStateKey = bindConfig.selectedBandStateKey || "selectedBand";
  const bandColors = ["#f87171", "#fb923c", "#fbbf24", "#4ade80", "#2dd4bf", "#38bdf8", "#a78bfa", "#f472b6"];
  const defaultFreqs = [60, 120, 250, 500, 1000, 2500, 6000, 12000];
  const defaultQs = [0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8];
  const defaultTypes = [1, 0, 0, 0, 0, 0, 0, 2];
  const hitRadius = 12;

  const BAND_TYPE = {
    Peak: 0,
    LowShelf: 1,
    HighShelf: 2,
    LowPass: 3,
    HighPass: 4,
    Notch: 5,
    BandPass: 6,
  };

  const freqToX = (freq) => ((Math.log(clamp(freq, minFreq, maxFreq)) - logMin) / (logMax - logMin)) * width;
  const xToFreq = (x) => Math.exp(logMin + clamp(x / Math.max(1, width), 0, 1) * (logMax - logMin));
  const gainToY = (gain) => (1 - ((clamp(gain, minGain, maxGain) - minGain) / (maxGain - minGain))) * height;
  const yToGain = (y) => minGain + (1 - clamp(y / Math.max(1, height), 0, 1)) * (maxGain - minGain);
  const qToY = (q) => {
    const lmin = Math.log(minQ);
    const lmax = Math.log(maxQ);
    const norm = (Math.log(clamp(q, minQ, maxQ)) - lmin) / (lmax - lmin);
    return (1 - norm) * height;
  };
  const yToQ = (y) => {
    const lmin = Math.log(minQ);
    const lmax = Math.log(maxQ);
    const norm = 1 - clamp(y / Math.max(1, height), 0, 1);
    return Math.exp(lmin + norm * (lmax - lmin));
  };
  const bandUsesGain = (type) => type === BAND_TYPE.Peak || type === BAND_TYPE.LowShelf || type === BAND_TYPE.HighShelf;
  const bandUsesQ = (type) => type === BAND_TYPE.LowPass || type === BAND_TYPE.HighPass || type === BAND_TYPE.Notch || type === BAND_TYPE.BandPass;

  const makePeak = (freq, q, gainDb) => {
    const A = 10 ** (gainDb / 40);
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const alpha = Math.sin(w0) / (2 * q);
    const b0 = 1 + alpha * A;
    const b1 = -2 * cosw0;
    const b2 = 1 - alpha * A;
    const a0 = 1 + alpha / A;
    const a1 = -2 * cosw0;
    const a2 = 1 - alpha / A;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeLowShelf = (freq, gainDb) => {
    const A = 10 ** (gainDb / 40);
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const sinw0 = Math.sin(w0);
    const alpha = sinw0 / 2 * Math.sqrt(A);
    const b0 = A * ((A + 1) - (A - 1) * cosw0 + 2 * alpha);
    const b1 = 2 * A * ((A - 1) - (A + 1) * cosw0);
    const b2 = A * ((A + 1) - (A - 1) * cosw0 - 2 * alpha);
    const a0 = (A + 1) + (A - 1) * cosw0 + 2 * alpha;
    const a1 = -2 * ((A - 1) + (A + 1) * cosw0);
    const a2 = (A + 1) + (A - 1) * cosw0 - 2 * alpha;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeHighShelf = (freq, gainDb) => {
    const A = 10 ** (gainDb / 40);
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const sinw0 = Math.sin(w0);
    const alpha = sinw0 / 2 * Math.sqrt(A);
    const b0 = A * ((A + 1) + (A - 1) * cosw0 + 2 * alpha);
    const b1 = -2 * A * ((A - 1) + (A + 1) * cosw0);
    const b2 = A * ((A + 1) + (A - 1) * cosw0 - 2 * alpha);
    const a0 = (A + 1) - (A - 1) * cosw0 + 2 * alpha;
    const a1 = 2 * ((A - 1) - (A + 1) * cosw0);
    const a2 = (A + 1) - (A - 1) * cosw0 - 2 * alpha;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeLowPass = (freq, q) => {
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const alpha = Math.sin(w0) / (2 * q);
    const b0 = (1 - cosw0) * 0.5;
    const b1 = 1 - cosw0;
    const b2 = (1 - cosw0) * 0.5;
    const a0 = 1 + alpha;
    const a1 = -2 * cosw0;
    const a2 = 1 - alpha;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeHighPass = (freq, q) => {
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const alpha = Math.sin(w0) / (2 * q);
    const b0 = (1 + cosw0) * 0.5;
    const b1 = -(1 + cosw0);
    const b2 = (1 + cosw0) * 0.5;
    const a0 = 1 + alpha;
    const a1 = -2 * cosw0;
    const a2 = 1 - alpha;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeNotch = (freq, q) => {
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const alpha = Math.sin(w0) / (2 * q);
    const b0 = 1;
    const b1 = -2 * cosw0;
    const b2 = 1;
    const a0 = 1 + alpha;
    const a1 = -2 * cosw0;
    const a2 = 1 - alpha;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeBandPass = (freq, q) => {
    const w0 = 2 * Math.PI * freq / sampleRate;
    const cosw0 = Math.cos(w0);
    const alpha = Math.sin(w0) / (2 * q);
    const b0 = alpha;
    const b1 = 0;
    const b2 = -alpha;
    const a0 = 1 + alpha;
    const a1 = -2 * cosw0;
    const a2 = 1 - alpha;
    return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
  };
  const makeCoeffs = (band) => {
    if (band.type === BAND_TYPE.LowShelf) return makeLowShelf(band.freq, band.gain);
    if (band.type === BAND_TYPE.HighShelf) return makeHighShelf(band.freq, band.gain);
    if (band.type === BAND_TYPE.LowPass) return makeLowPass(band.freq, band.q);
    if (band.type === BAND_TYPE.HighPass) return makeHighPass(band.freq, band.q);
    if (band.type === BAND_TYPE.Notch) return makeNotch(band.freq, band.q);
    if (band.type === BAND_TYPE.BandPass) return makeBandPass(band.freq, band.q);
    return makePeak(band.freq, band.q, band.gain);
  };
  const magnitudeForCoeffs = (coeffs, freq) => {
    const w = 2 * Math.PI * freq / sampleRate;
    const cos1 = Math.cos(w);
    const sin1 = Math.sin(w);
    const cos2 = Math.cos(2 * w);
    const sin2 = Math.sin(2 * w);
    const nr = coeffs.b0 + coeffs.b1 * cos1 + coeffs.b2 * cos2;
    const ni = -(coeffs.b1 * sin1 + coeffs.b2 * sin2);
    const dr = 1 + coeffs.a1 * cos1 + coeffs.a2 * cos2;
    const di = -(coeffs.a1 * sin1 + coeffs.a2 * sin2);
    const num = Math.sqrt(nr * nr + ni * ni);
    const den = Math.sqrt(dr * dr + di * di);
    return den <= 1e-9 ? 1 : num / den;
  };

  const endpointFor = (path, type = "f", range = [{ MIN: 0, MAX: 1 }]) => {
    return target.endpointMap.get(path) || { path, label: prettyLabel(path), type, access: 3, range };
  };
  const getBands = () => {
    const bands = [];
    for (let i = 1; i <= 8; i += 1) {
      bands.push({
        enabled: Boolean(toNumber(target.values.get(`${bandBase}/${i}/enabled`), i === 1 || i === 8 ? 1 : 0)),
        type: Math.round(toNumber(target.values.get(`${bandBase}/${i}/type`), defaultTypes[i - 1])),
        freq: toNumber(target.values.get(`${bandBase}/${i}/freq`), defaultFreqs[i - 1]),
        gain: toNumber(target.values.get(`${bandBase}/${i}/gain`), 0),
        q: toNumber(target.values.get(`${bandBase}/${i}/q`), defaultQs[i - 1]),
      });
    }
    return bands;
  };
  const pointForBand = (band) => {
    const y = bandUsesGain(band.type) ? gainToY(band.gain) : qToY(band.q);
    return { x: freqToX(band.freq), y };
  };
  const firstFreeBand = (bands) => bands.findIndex((band) => !band.enabled) + 1 || null;
  const hitTestBand = (bands, mx, my) => {
    let bestIdx = null;
    let bestDist = hitRadius * hitRadius;
    bands.forEach((band, idx) => {
      if (!band.enabled) return;
      const point = pointForBand(band);
      const dx = mx - point.x;
      const dy = my - point.y;
      const d2 = dx * dx + dy * dy;
      if (d2 <= bestDist) {
        bestDist = d2;
        bestIdx = idx + 1;
      }
    });
    return bestIdx;
  };

  const draw = () => {
    const selectedBand = Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    const bands = getBands();

    ctx2d.clearRect(0, 0, width, height);
    ctx2d.fillStyle = style.bg || "#0a0a1a";
    ctx2d.fillRect(0, 0, width, height);
    [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000].forEach((f) => {
      const x = freqToX(f);
      ctx2d.strokeStyle = "#1a1a3a";
      ctx2d.beginPath();
      ctx2d.moveTo(x, 0);
      ctx2d.lineTo(x, height);
      ctx2d.stroke();
    });
    [-18, -12, -6, 0, 6, 12, 18].forEach((db) => {
      const y = gainToY(db);
      ctx2d.strokeStyle = db === 0 ? "#334155" : "#1a1a3a";
      ctx2d.beginPath();
      ctx2d.moveTo(0, y);
      ctx2d.lineTo(width, y);
      ctx2d.stroke();
    });

    ctx2d.strokeStyle = style.accent || "#22d3ee";
    ctx2d.lineWidth = 2;
    ctx2d.beginPath();
    for (let x = 0; x < width; x += 1) {
      const freq = Math.exp(logMin + (x / width) * (logMax - logMin));
      let mag = 1;
      bands.forEach((band) => {
        if (band.enabled) mag *= magnitudeForCoeffs(makeCoeffs(band), freq);
      });
      const db = clamp(20 * Math.log10(Math.max(mag, 1e-9)), -18, 18);
      const y = gainToY(db);
      if (x === 0) ctx2d.moveTo(x, y);
      else ctx2d.lineTo(x, y);
    }
    ctx2d.stroke();

    bands.forEach((band, idx) => {
      if (!band.enabled) return;
      const point = pointForBand(band);
      const selected = idx + 1 === selectedBand;
      ctx2d.fillStyle = bandColors[idx];
      ctx2d.beginPath();
      ctx2d.arc(point.x, point.y, selected ? 7 : 5, 0, Math.PI * 2);
      ctx2d.fill();
      ctx2d.strokeStyle = selected ? "#ffffff" : "#0f172a";
      ctx2d.lineWidth = selected ? 2 : 1;
      ctx2d.stroke();
    });
  };

  let queuedBand = null;
  let sending = false;
  let dragging = false;
  const flushBand = async () => {
    if (sending || queuedBand == null) return;
    sending = true;
    while (queuedBand != null) {
      const index = queuedBand;
      queuedBand = null;
      const band = getBands()[index - 1];
      try {
        await Promise.all([
          writeValue(target, `${bandBase}/${index}/enabled`, band.enabled ? 1 : 0, endpointFor(`${bandBase}/${index}/enabled`, "i", [{ MIN: 0, MAX: 1 }])),
          writeValue(target, `${bandBase}/${index}/type`, band.type, endpointFor(`${bandBase}/${index}/type`, "i", [{ MIN: 0, MAX: 6 }])),
          writeValue(target, `${bandBase}/${index}/freq`, band.freq, endpointFor(`${bandBase}/${index}/freq`, "f", [{ MIN: minFreq, MAX: maxFreq }])),
          writeValue(target, `${bandBase}/${index}/gain`, band.gain, endpointFor(`${bandBase}/${index}/gain`, "f", [{ MIN: minGain, MAX: maxGain }])),
          writeValue(target, `${bandBase}/${index}/q`, band.q, endpointFor(`${bandBase}/${index}/q`, "f", [{ MIN: minQ, MAX: maxQ }])),
        ]);
      } catch (error) {
        setTargetStatus(target, `EQ graph write failed: ${error.message}`, "error");
      }
    }
    sending = false;
  };

  const updateBandFromPosition = (index, mx, my) => {
    const bands = getBands();
    const band = bands[index - 1];
    if (!band) return;
    const freq = clamp(xToFreq(mx), minFreq, maxFreq);
    setLiveValue(target, `${bandBase}/${index}/freq`, freq);
    if (bandUsesGain(band.type)) {
      setLiveValue(target, `${bandBase}/${index}/gain`, clamp(yToGain(my), minGain, maxGain));
    } else if (bandUsesQ(band.type)) {
      setLiveValue(target, `${bandBase}/${index}/q`, clamp(yToQ(my), minQ, maxQ));
    }
    queuedBand = index;
    draw();
    void flushBand();
  };

  const eventPoint = (event) => {
    const rect = canvas.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left) / rect.width * width,
      y: (event.clientY - rect.top) / rect.height * height,
    };
  };

  canvas.addEventListener("pointerdown", (event) => {
    const point = eventPoint(event);
    const bands = getBands();
    let hit = hitTestBand(bands, point.x, point.y);
    if (!hit) {
      hit = firstFreeBand(bands);
      if (hit) {
        setLiveValue(target, `${bandBase}/${hit}/enabled`, 1);
        setLiveValue(target, `${bandBase}/${hit}/type`, 0, { scheduleRender: true });
        setLiveValue(target, `${bandBase}/${hit}/q`, 1.0);
      }
    }
    if (!hit) return;
    beginInteraction(target, [
      `${bandBase}/${hit}/enabled`,
      `${bandBase}/${hit}/type`,
      `${bandBase}/${hit}/freq`,
      `${bandBase}/${hit}/gain`,
      `${bandBase}/${hit}/q`,
    ]);
    setLayoutStateValue(target, selectedBandStateKey, hit);
    dragging = true;
    canvas.setPointerCapture(event.pointerId);
    updateBandFromPosition(hit, point.x, point.y);
  });

  canvas.addEventListener("pointermove", (event) => {
    if (!dragging) return;
    const selectedBand = Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    if (!selectedBand) return;
    const point = eventPoint(event);
    updateBandFromPosition(selectedBand, point.x, point.y);
  });

  const endDrag = () => {
    const selectedBand = Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    dragging = false;
    endInteraction(target, [
      `${bandBase}/${selectedBand}/enabled`,
      `${bandBase}/${selectedBand}/type`,
      `${bandBase}/${selectedBand}/freq`,
      `${bandBase}/${selectedBand}/gain`,
      `${bandBase}/${selectedBand}/q`,
    ]);
  };
  canvas.addEventListener("pointerup", endDrag);
  canvas.addEventListener("pointercancel", endDrag);

  canvas.addEventListener("wheel", (event) => {
    event.preventDefault();
    const point = eventPoint(event);
    const bands = getBands();
    const hit = hitTestBand(bands, point.x, point.y) || Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    if (!hit) return;
    const band = bands[hit - 1];
    if (!band || !band.enabled) return;
    setLayoutStateValue(target, selectedBandStateKey, hit);
    const nextQ = clamp(band.q + (event.deltaY > 0 ? 0.1 : -0.1), minQ, maxQ);
    setLiveValue(target, `${bandBase}/${hit}/q`, nextQ);
    queuedBand = hit;
    draw();
    void flushBand();
  }, { passive: false });

  canvas.addEventListener("dblclick", async () => {
    const selectedBand = Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    if (!selectedBand) return;
    setLiveValue(target, `${bandBase}/${selectedBand}/enabled`, 0, { scheduleRender: true });
    queuedBand = selectedBand;
    draw();
    void flushBand();
  });

  draw();
  return panel;
}

function buildLayoutXyControl(target, bind, style = {}, bounds = {}) {
  const root = makeElement("div", "layout-xy");
  const handle = makeElement("div", "layout-xy-handle");
  const info = makeElement("div", "layout-xy-info");
  const xRow = makeElement("div", "layout-xy-row");
  const yRow = makeElement("div", "layout-xy-row");
  root.append(handle, info);
  info.append(xRow, yRow);

  const resolveBinding = () => {
    if (isFxTarget(target) && String(bind.xPath || "").startsWith("/plugin/params/p/") && String(bind.yPath || "").startsWith("/plugin/params/p/")) {
      return getFxAssignState(target);
    }
    return {
      xPath: bind.xPath,
      yPath: bind.yPath,
      xName: prettyLabel(bind.xPath),
      yName: prettyLabel(bind.yPath),
    };
  };

  const binding = resolveBinding();
  const xEndpoint = target.endpointMap.get(binding.xPath) || { path: binding.xPath, type: "f", access: 3, range: [{ MIN: 0, MAX: 1 }] };
  const yEndpoint = target.endpointMap.get(binding.yPath) || { path: binding.yPath, type: "f", access: 3, range: [{ MIN: 0, MAX: 1 }] };
  const xRange = getRange(xEndpoint);
  const yRange = getRange(yEndpoint);
  const accent = style.accent || "#22d3ee";
  root.style.setProperty("--xy-accent", accent);
  if (style.bg) root.style.background = style.bg;
  if (style.border) root.style.borderColor = style.border;
  if (style.radius != null) root.style.borderRadius = `${style.radius}px`;
  if (bounds.width > 0) root.style.width = `${bounds.width}px`;
  if (bounds.height > 0) root.style.height = `${bounds.height}px`;

  const updateHandle = () => {
    const resolved = resolveBinding();
    const xValue = toNumber(target.values.get(resolved.xPath), xRange.min);
    const yValue = toNumber(target.values.get(resolved.yPath), yRange.min);
    const xNorm = xRange.max === xRange.min ? 0 : (xValue - xRange.min) / (xRange.max - xRange.min);
    const yNorm = yRange.max === yRange.min ? 0 : (yValue - yRange.min) / (yRange.max - yRange.min);
    handle.style.left = `${clamp(xNorm, 0, 1) * 100}%`;
    handle.style.top = `${(1 - clamp(yNorm, 0, 1)) * 100}%`;
    xRow.textContent = `X · ${resolved.xName} · ${formatEndpointValue(target.endpointMap.get(resolved.xPath) || xEndpoint, xValue)}`;
    yRow.textContent = `Y · ${resolved.yName} · ${formatEndpointValue(target.endpointMap.get(resolved.yPath) || yEndpoint, yValue)}`;
  };

  registerLiveBinding(target, binding.xPath, updateHandle);
  registerLiveBinding(target, binding.yPath, updateHandle);

  if (isFxTarget(target)) {
    registerLiveBinding(target, "/plugin/params/type", updateHandle);
  }

  const currentBindingPaths = () => {
    const resolved = resolveBinding();
    return [resolved.xPath, resolved.yPath];
  };

  let activeInteractionPaths = [];

  const beginCurrentInteraction = () => {
    activeInteractionPaths = currentBindingPaths();
    beginInteraction(target, activeInteractionPaths);
  };

  const endCurrentInteraction = () => {
    endInteraction(target, activeInteractionPaths);
    activeInteractionPaths = [];
  };

  let dragging = false;
  let queued = null;
  let sending = false;
  const flush = async () => {
    if (sending || !queued) return;
    sending = true;
    while (queued) {
      const next = queued;
      queued = null;
      try {
        await Promise.all([
          writeValue(target, next.xPath, next.x, next.xEndpoint),
          writeValue(target, next.yPath, next.y, next.yEndpoint),
        ]);
      } catch (error) {
        setTargetStatus(target, `XY write failed: ${error.message}`, "error");
      }
    }
    sending = false;
  };

  const applyPointer = (event) => {
    const resolved = resolveBinding();
    const liveXEndpoint = target.endpointMap.get(resolved.xPath) || xEndpoint;
    const liveYEndpoint = target.endpointMap.get(resolved.yPath) || yEndpoint;
    const liveXRange = getRange(liveXEndpoint);
    const liveYRange = getRange(liveYEndpoint);
    const rect = root.getBoundingClientRect();
    const px = clamp((event.clientX - rect.left) / rect.width, 0, 1);
    const py = clamp((event.clientY - rect.top) / rect.height, 0, 1);
    const nextX = liveXRange.min + px * (liveXRange.max - liveXRange.min);
    const nextY = liveYRange.min + (1 - py) * (liveYRange.max - liveYRange.min);
    setLiveValue(target, resolved.xPath, nextX);
    setLiveValue(target, resolved.yPath, nextY);
    queued = { xPath: resolved.xPath, yPath: resolved.yPath, x: nextX, y: nextY, xEndpoint: liveXEndpoint, yEndpoint: liveYEndpoint };
    updateHandle();
    void flush();
  };

  root.addEventListener("pointerdown", (event) => {
    dragging = true;
    beginCurrentInteraction();
    root.setPointerCapture(event.pointerId);
    applyPointer(event);
  });
  root.addEventListener("pointermove", (event) => {
    if (dragging) applyPointer(event);
  });
  const endDragXy = () => {
    dragging = false;
    endCurrentInteraction();
  };
  root.addEventListener("pointerup", endDragXy);
  root.addEventListener("pointercancel", endDragXy);

  updateHandle();
  return root;
}

function buildLuaSliderControl(target, endpoint, options = {}) {
  const path = endpoint.path;
  const value = target.values.get(path);
  const readableValue = value !== undefined ? value : (endpoint.defaultValue ?? getRange(endpoint).min);
  const position = sliderPositionFromValue(endpoint, readableValue);
  const shell = makeElement("div", "lua-slider");
  const fill = makeElement("div", "lua-slider-fill");
  const scrim = makeElement("div", "lua-slider-scrim");
  const label = makeElement("span", "lua-slider-label", options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(path));
  const readout = makeElement("span", "lua-slider-value", formatEndpointValue(endpoint, readableValue));
  const input = document.createElement("input");
  input.type = "range";
  input.min = "0";
  input.max = "1000";
  input.step = "1";
  input.value = String(Math.round(position * 1000));
  input.className = "lua-slider-input";
  input.disabled = !isWritable(endpoint) || options.disabled === true;

  const baseBg = options.style?.bg || "#1e293b";
  const baseColour = options.style?.colour || options.style?.accent || "#38bdf8";
  const fontSize = options.fontSize || `${Math.min(10, Math.max(7, (options.height || 20) - 4))}px`;

  shell.style.setProperty("--lua-bg", baseBg);
  shell.style.setProperty("--lua-colour", baseColour);
  shell.style.fontSize = fontSize;

  const refreshFromState = () => {
    const liveValue = target.values.get(path);
    const actual = liveValue !== undefined ? liveValue : (endpoint.defaultValue ?? getRange(endpoint).min);
    const pos = sliderPositionFromValue(endpoint, actual);
    fill.style.width = `${clamp(pos, 0, 1) * 100}%`;
    readout.textContent = formatEndpointValue(endpoint, actual);
    label.textContent = options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(path);
    if (!target.interactingPaths.has(path)) {
      input.value = String(Math.round(pos * 1000));
    }
  };

  const updatePreview = () => {
    const pos = Number(input.value) / 1000;
    const actual = sliderValueFromPosition(target, endpoint, pos);
    fill.style.width = `${clamp(pos, 0, 1) * 100}%`;
    readout.textContent = formatEndpointValue(endpoint, actual);
  };

  let queuedValue = null;
  let sending = false;
  const flushLiveWrite = async () => {
    if (sending || queuedValue == null) return;
    sending = true;
    while (queuedValue != null) {
      const nextValue = queuedValue;
      queuedValue = null;
      try {
        await writeValue(target, path, nextValue, endpoint);
      } catch (error) {
        setTargetStatus(target, `Write failed: ${error.message}`, "error");
      }
    }
    sending = false;
  };

  input.addEventListener("pointerdown", () => beginInteraction(target, [path]));
  input.addEventListener("input", () => {
    const pos = Number(input.value) / 1000;
    const nextValue = sliderValueFromPosition(target, endpoint, pos);
    setLiveValue(target, path, nextValue);
    queuedValue = nextValue;
    updatePreview();
    void flushLiveWrite();
  });
  const finishLuaSliderInteraction = () => endInteraction(target, [path]);
  input.addEventListener("change", finishLuaSliderInteraction);
  input.addEventListener("pointerup", finishLuaSliderInteraction);
  input.addEventListener("pointercancel", finishLuaSliderInteraction);

  fill.style.width = `${position * 100}%`;
  registerLiveBinding(target, path, refreshFromState);
  shell.append(fill, scrim, label, readout, input);
  return shell;
}

function buildLuaToggleControl(target, endpoint, options = {}) {
  const current = Boolean(toNumber(target.values.get(endpoint.path), endpoint.defaultValue ?? getRange(endpoint).min));
  const button = makeElement("button", `lua-toggle ${current ? "on" : ""}`);
  button.type = "button";
  button.disabled = !isWritable(endpoint) || options.disabled === true;

  const onColour = options.style?.onColour || "#0ea5e9";
  const offColour = options.style?.offColour || "#475569";
  button.style.setProperty("--lua-on-colour", onColour);
  button.style.setProperty("--lua-on-border", brightenHex(onColour, 40));
  button.style.setProperty("--lua-bg", offColour);
  button.style.setProperty("--lua-border", brightenHex(offColour, 40));
  button.style.setProperty("--lua-radius", `${options.style?.radius ?? 4}px`);
  if (options.fontSize) button.style.fontSize = options.fontSize;

  const text = makeElement("span", "lua-toggle-text", options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(endpoint.path));
  const refreshToggle = () => {
    const live = Boolean(toNumber(target.values.get(endpoint.path), endpoint.defaultValue ?? getRange(endpoint).min));
    button.classList.toggle("on", live);
    text.textContent = options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(endpoint.path);
  };
  registerLiveBinding(target, endpoint.path, refreshToggle);
  button.append(text);

  button.addEventListener("click", async () => {
    const next = !Boolean(toNumber(target.values.get(endpoint.path), endpoint.defaultValue ?? 0));
    setLiveValue(target, endpoint.path, next ? 1 : 0, { scheduleRender: true });
    try {
      await writeValue(target, endpoint.path, next, endpoint);
    } catch (error) {
      setTargetStatus(target, `Write failed: ${error.message}`, "error");
    }
  });

  return button;
}

function attachPopupCloser(root, onClose) {
  const handler = (event) => {
    if (!root.contains(event.target)) {
      document.removeEventListener("pointerdown", handler, true);
      onClose();
    }
  };
  setTimeout(() => document.addEventListener("pointerdown", handler, true), 0);
}

function buildLuaDropdown(target, config) {
  const root = makeElement("div", "lua-dropdown");
  const text = makeElement("div", "lua-dropdown-text", config.getText());
  const arrow = makeElement("div", "lua-dropdown-arrow", "▼");
  root.append(text, arrow);

  const bg = config.style?.bg || "#1e293b";
  const border = config.style?.border || brightenHex(bg, 30);
  root.style.setProperty("--lua-bg", bg);
  root.style.setProperty("--lua-border", border);
  root.style.setProperty("--lua-radius", `${config.style?.radius ?? 6}px`);
  if (config.fontSize) root.style.fontSize = config.fontSize;
  if (config.disabled) root.style.opacity = "0.6";

  let popup = null;
  const closePopup = () => {
    if (!popup) return;
    popup.remove();
    popup = null;
    arrow.textContent = "▼";
    root.parentElement?.parentElement?.classList.remove("open-popup");
  };

  root.addEventListener("click", async (event) => {
    event.stopPropagation();
    if (config.disabled) return;
    if (popup) {
      closePopup();
      return;
    }
    arrow.textContent = "▲";
    root.parentElement?.parentElement?.classList.add("open-popup");
    popup = makeElement("div", "lua-dropdown-popup");
    const options = config.getOptions();
    options.forEach((option) => {
      const row = makeElement("div", `lua-dropdown-option ${option.selected ? "selected" : ""}`, option.label);
      row.addEventListener("click", async (e) => {
        e.stopPropagation();
        try {
          await config.onSelect(option.value);
          text.textContent = config.getText();
        } finally {
          closePopup();
        }
      });
      popup.append(row);
    });
    root.append(popup);
    attachPopupCloser(root, closePopup);
  });

  return root;
}

function buildLuaEndpointDropdown(target, endpoint, node = {}, style = {}) {
  const choices = Array.isArray(node.options) && node.options.length > 0
    ? node.options
    : (Array.isArray(endpoint.choices) ? endpoint.choices : []);
  const { min } = getRange(endpoint);
  return buildLuaDropdown(target, {
    style,
    fontSize: `${Math.min(10, Math.max(7, (node.h || 20) - 8))}px`,
    disabled: node.disabled === true || !isWritable(endpoint),
    getText: () => {
      const liveValue = toNumber(target.values.get(endpoint.path), endpoint.defaultValue ?? min);
      const idx = clamp(Math.round(liveValue - min), 0, Math.max(choices.length - 1, 0));
      return String(choices[idx] ?? formatEndpointValue(endpoint, liveValue));
    },
    getOptions: () => {
      const liveValue = toNumber(target.values.get(endpoint.path), endpoint.defaultValue ?? min);
      return choices.map((choice, index) => ({
        label: String(choice),
        value: min + index,
        selected: Math.round(liveValue) === Math.round(min + index),
      }));
    },
    onSelect: async (value) => {
      setLiveValue(target, endpoint.path, Number(value), { scheduleRender: true });
      await writeValue(target, endpoint.path, Number(value), endpoint);
    },
  });
}

function buildLuaLocalDropdown(target, node, style = {}) {
  const options = Array.isArray(node.options) ? node.options : [];
  const stateKey = node.stateKey || node.bind?.stateKey || node.id;
  return buildLuaDropdown(target, {
    style,
    fontSize: `${Math.min(10, Math.max(7, (node.h || 20) - 8))}px`,
    disabled: node.disabled === true,
    getText: () => {
      const currentValue = Number(getLayoutStateValue(target, stateKey, node.defaultValue ?? 1));
      return String(options[Math.max(0, Math.min(options.length - 1, currentValue - 1))] ?? node.label ?? "Select");
    },
    getOptions: () => {
      const currentValue = Number(getLayoutStateValue(target, stateKey, node.defaultValue ?? 1));
      return options.map((choice, index) => ({
        label: String(choice),
        value: index + 1,
        selected: currentValue === index + 1,
      }));
    },
    onSelect: async (value) => {
      setLayoutStateValue(target, stateKey, Number(value));
      scheduleRender(target);
    },
  });
}

function buildFxAssignDropdown(target, axis, node, style = {}) {
  const stateKey = axis === "x" ? "fxXYXParam" : "fxXYYParam";
  return buildLuaDropdown(target, {
    style,
    fontSize: `${Math.min(10, Math.max(7, (node.h || 20) - 8))}px`,
    disabled: false,
    getText: () => {
      const assign = getFxAssignState(target);
      return axis === "x" ? assign.xName : assign.yName;
    },
    getOptions: () => {
      const assign = getFxAssignState(target);
      const currentValue = axis === "x" ? assign.xIdx : assign.yIdx;
      return assign.names.map((choice, index) => ({
        label: String(choice),
        value: index + 1,
        selected: currentValue === index + 1,
      }));
    },
    onSelect: async (value) => {
      setLayoutStateValue(target, stateKey, Number(value));
      scheduleRender(target);
    },
  });
}

function buildControl(target, endpoint, overrideWidgetType = null, options = {}) {
  const path = endpoint.path;
  const showPath = options.showPath !== false;
  let widgetType = overrideWidgetType || inferWidgetType(target, endpoint);
  if (widgetType === "xy-y") return null;
  if (widgetType === "dropdown") widgetType = "choice";
  if (widgetType === "knob" || widgetType === "vslider") widgetType = "slider";

  const controlCard = makeElement("div", "control-card");
  if (showPath) controlCard.append(makeElement("div", "control-path", path));

  if (widgetType === "toggle") {
    const current = Boolean(target.values.get(path));
    const row = makeElement("button", "toggle-pill", `${options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(path)} • ${formatEndpointValue(endpoint, current)}`);
    row.disabled = !isWritable(endpoint) || options.disabled === true;
    row.addEventListener("click", async () => {
      try {
        await writeValue(target, path, !Boolean(target.values.get(path)), endpoint);
      } catch (error) {
        setTargetStatus(target, `Write failed: ${error.message}`, "error");
      }
    });
    controlCard.append(row);
    return controlCard;
  }

  if (widgetType === "choice") {
    controlCard.append(buildChoiceControl(target, endpoint, options.choices, options.disabled));
    return controlCard;
  }

  if (widgetType === "xy-x") {
    const yPath = path.endsWith("/x") ? path.replace(/\/x$/, "/y") : path.replace(/\/mix_x$/, "/mix_y");
    const yEndpoint = target.endpointMap.get(yPath);
    const yValue = toNumber(target.values.get(yPath), hasRange(yEndpoint) ? getRange(yEndpoint).min : 0);
    const xValue = toNumber(target.values.get(path), endpoint.defaultValue ?? getRange(endpoint).min);
    const xRange = getRange(endpoint);
    const yRange = getRange(yEndpoint || { range: [{ MIN: 0, MAX: 1 }] });

    const wrap = makeElement("div", "xy-wrap");
    const pad = makeElement("div", "xy-pad");
    const handle = makeElement("div", "xy-handle");
    const xNorm = xRange.max === xRange.min ? 0 : (xValue - xRange.min) / (xRange.max - xRange.min);
    const yNorm = yRange.max === yRange.min ? 0 : (yValue - yRange.min) / (yRange.max - yRange.min);
    handle.style.left = `${clamp(xNorm, 0, 1) * 100}%`;
    handle.style.top = `${(1 - clamp(yNorm, 0, 1)) * 100}%`;
    pad.append(handle);

    const commitPointer = async (event) => {
      if (!yEndpoint) return;
      const rect = pad.getBoundingClientRect();
      const px = clamp((event.clientX - rect.left) / rect.width, 0, 1);
      const py = clamp((event.clientY - rect.top) / rect.height, 0, 1);
      const nextX = xRange.min + px * (xRange.max - xRange.min);
      const nextY = yRange.min + (1 - py) * (yRange.max - yRange.min);
      handle.style.left = `${px * 100}%`;
      handle.style.top = `${py * 100}%`;
      setLiveValue(target, path, nextX);
      setLiveValue(target, yPath, nextY);
      try {
        await Promise.all([
          writeValue(target, path, nextX, endpoint),
          writeValue(target, yPath, nextY, yEndpoint),
        ]);
      } catch (error) {
        setTargetStatus(target, `XY write failed: ${error.message}`, "error");
      }
    };

    let dragging = false;
    pad.addEventListener("pointerdown", (event) => {
      dragging = true;
      pad.setPointerCapture(event.pointerId);
      commitPointer(event);
    });
    pad.addEventListener("pointermove", (event) => {
      if (dragging) commitPointer(event);
    });
    pad.addEventListener("pointerup", () => { dragging = false; });
    pad.addEventListener("pointercancel", () => { dragging = false; });

    const values = makeElement("div", "xy-values");
    values.append(
      makeElement("span", "", `${options.label || resolveDisplayLabel(target, endpoint, "X") || "X"}: ${formatEndpointValue(endpoint, xValue)}`),
      makeElement("span", "", `${yEndpoint?.label || "Y"}: ${formatEndpointValue(yEndpoint || {}, yValue)}`),
    );
    wrap.append(pad, values);
    controlCard.append(wrap);
    return controlCard;
  }

  if (widgetType === "readout") {
    controlCard.append(makeElement("div", "value-readout big", formatEndpointValue(endpoint, target.values.get(path))));
    if (isWritable(endpoint)) {
      const trigger = makeElement("button", "secondary", "Trigger");
      trigger.addEventListener("click", async () => {
        try {
          await triggerPath(target, path);
        } catch (error) {
          setTargetStatus(target, `Trigger failed: ${error.message}`, "error");
        }
      });
      controlCard.append(trigger);
    }
    return controlCard;
  }

  controlCard.append(buildCompactSliderControl(target, endpoint, options));
  return controlCard;
}

function renderEndpointBrowser() {
  const container = dom.endpointList;
  const target = activeTarget();
  container.innerHTML = "";
  if (!target) {
    container.className = "endpoint-list empty-state";
    container.textContent = "Connect to an OSCQuery target.";
    return;
  }

  const endpoints = target.filteredEndpoints;
  if (!endpoints.length) {
    container.className = "endpoint-list empty-state";
    container.textContent = target.endpoints.length ? "No parameters match the current search." : "Connect to an OSCQuery target.";
    return;
  }

  container.className = "endpoint-list";
  endpoints.forEach((endpoint) => {
    const row = makeElement("div", "endpoint-row");
    const titleRow = makeElement("div", "title-row");
    const titleBlock = makeElement("div");
    titleBlock.append(makeElement("strong", "", resolveDisplayLabel(target, endpoint)), makeElement("div", "path", endpoint.path));

    const addButton = makeElement("button", "secondary", "Add");
    addButton.addEventListener("click", () => addSurfaceWidget(target, endpoint));
    titleRow.append(titleBlock, addButton);

    const meta = makeElement("div", "meta");
    meta.append(
      makeElement("span", "badge", endpoint.type || "?"),
      makeElement("span", "badge", endpoint.group),
      makeElement("span", "badge", isWritable(endpoint) ? "write" : "read"),
    );
    if (hasRange(endpoint)) {
      const { min, max } = getRange(endpoint);
      meta.append(makeElement("span", "badge", `${formatValue(min)} → ${formatValue(max)}`));
    }

    const desc = makeElement("div", "muted", endpoint.description || "No description");
    row.append(titleRow, meta, desc);
    container.append(row);
  });
}

function renderGenericGroups() {
  const container = dom.genericGroups;
  const target = activeTarget();
  container.innerHTML = "";
  if (!target) {
    container.className = "groups-grid empty-state";
    container.textContent = "No endpoint data yet.";
    return;
  }

  if (!target.filteredEndpoints.length) {
    container.className = "groups-grid empty-state";
    container.textContent = target.endpoints.length ? "No generic controls match the current search." : "No endpoint data yet.";
    return;
  }

  const groups = new Map();
  target.filteredEndpoints.forEach((endpoint) => {
    const type = inferWidgetType(target, endpoint);
    if (type === "xy-y") return;
    const key = endpoint.group || "/";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(endpoint);
  });

  container.className = "groups-grid";
  Array.from(groups.entries())
    .sort((a, b) => a[0].localeCompare(b[0]))
    .forEach(([groupName, endpoints]) => {
      const card = makeElement("article", "group-card");
      const header = makeElement("div", "group-header");
      header.append(makeElement("strong", "", groupName), makeElement("span", "badge", `${endpoints.length}`));
      card.append(header);

      const grid = makeElement("div", "controls-grid");
      endpoints.sort((a, b) => a.path.localeCompare(b.path)).forEach((endpoint) => {
        const control = buildControl(target, endpoint);
        if (control) grid.append(control);
      });
      card.append(grid);
      container.append(card);
    });
}

function resolveLayoutBindPath(target, bind) {
  if (!bind || typeof bind !== "object") return null;
  if (typeof bind.path === "string" && bind.path) return bind.path;
  if (typeof bind.pathTemplate === "string" && bind.pathTemplate) {
    const stateKey = bind.stateKey || "selectedBand";
    const tokenValue = String(getLayoutStateValue(target, stateKey, bind.defaultValue ?? 1));
    return bind.pathTemplate.replace(/__band__/g, tokenValue);
  }
  return null;
}

function renderLayoutNode(target, node, parent, inheritedStyle = {}) {
  const type = String(node.type || node.TYPE || "panel").toLowerCase();
  const style = { ...inheritedStyle, ...(node.style || {}) };
  const element = makeElement("div", `layout-node ${type}`);
  const x = toNumber(node.x, 0);
  const y = toNumber(node.y, 0);
  const w = toNumber(node.w, 0);
  const h = toNumber(node.h, 0);

  element.style.left = `${x}px`;
  element.style.top = `${y}px`;
  if (w > 0) element.style.width = `${w}px`;
  if (h > 0) element.style.height = `${h}px`;
  if (style.bg || style.background) element.style.background = style.bg || style.background;
  if (style.border) element.style.borderColor = style.border;
  if (style.borderWidth != null) element.style.borderWidth = `${style.borderWidth}px`;
  if (style.borderWidth === 0) element.style.border = "none";
  if (style.radius != null) element.style.borderRadius = `${style.radius}px`;
  if (style.colour || style.color) element.style.color = style.colour || style.color;
  if (style.fontSize != null) element.style.fontSize = `${style.fontSize}px`;
  if (style.opacity != null) element.style.opacity = `${style.opacity}`;
  if (type === "dropdown") element.style.overflow = "visible";

  if (type === "label") {
    element.textContent = node.props?.text || node.text || node.label || node.id || "";
    element.style.display = "flex";
    element.style.alignItems = "center";
    element.style.justifyContent = style.align === "center" ? "center" : style.align === "right" ? "flex-end" : "flex-start";
    if (!style.fontSize) element.style.fontSize = "13px";
  } else {
    const content = makeElement("div", "layout-content");
    if (["filter-graph", "eq-graph", "xy", "slider", "toggle", "dropdown"].includes(type)) {
      content.style.padding = "0";
    }
    const bindPath = resolveLayoutBindPath(target, node.bind) || node.path || node.props?.path || null;
    const bindEndpoint = bindPath ? target.endpointMap.get(bindPath) || {
      path: bindPath,
      label: node.label || prettyLabel(bindPath),
      type: "f",
      access: 3,
      description: node.description || "",
      range: [{ MIN: 0, MAX: 1 }],
    } : null;

    if (isFxTarget(target) && bindEndpoint) {
      const fxParamIndex = fxParamIndexForPath(bindEndpoint.path);
      if (fxParamIndex != null && fxParamIndex >= getFxParamNames(target).length) {
        element.style.display = "none";
      }
    }

    if (type === "filter-graph" && node.bind) {
      content.append(buildFilterGraphControl(target, node.bind, style, { width: w, height: h }));
    } else if (type === "eq-graph" && node.bind) {
      content.append(buildEqGraphControl(target, node.bind, style, { width: w, height: h }));
    } else if (type === "xy" && node.bind?.xPath && node.bind?.yPath) {
      content.append(buildLayoutXyControl(target, node.bind, style, { width: w, height: h }));
    } else if (type === "dropdown" && isFxTarget(target) && node.id === "xy_x_assign") {
      content.append(buildFxAssignDropdown(target, "x", node, style));
    } else if (type === "dropdown" && isFxTarget(target) && node.id === "xy_y_assign") {
      content.append(buildFxAssignDropdown(target, "y", node, style));
    } else if (type === "dropdown" && node.stateKey && Array.isArray(node.options)) {
      content.append(buildLuaLocalDropdown(target, node, style));
    } else if (type === "dropdown" && bindEndpoint) {
      content.append(buildLuaEndpointDropdown(target, bindEndpoint, node, style));
    } else if (type === "toggle" && bindEndpoint) {
      content.append(buildLuaToggleControl(target, bindEndpoint, {
        label: resolveDisplayLabel(target, bindEndpoint, node.label),
        style,
        fontSize: `${style.fontSize ?? Math.min(10, Math.max(7, h - 8))}px`,
      }));
    } else if ((type === "slider" || type === "knob" || type === "vslider") && bindEndpoint) {
      content.append(buildLuaSliderControl(target, bindEndpoint, {
        label: resolveDisplayLabel(target, bindEndpoint, node.label),
        style,
        height: h,
        fontSize: `${style.fontSize ?? Math.min(10, Math.max(7, h - 4))}px`,
      }));
    } else if (bindEndpoint) {
      const control = buildControl(target, bindEndpoint, type === "button" ? "readout" : type, {
        showPath: false,
        choices: node.options,
        disabled: node.disabled === true,
        label: resolveDisplayLabel(target, bindEndpoint, node.label),
      });
      if (control) content.append(control);
    } else if ((node.label || node.id) && !Array.isArray(node.children)) {
      content.append(makeElement("div", "muted", node.label || node.id));
    }

    element.append(content);
  }

  parent.append(element);
  if (Array.isArray(node.children)) {
    node.children.forEach((child) => renderLayoutNode(target, child, element, style));
  }
}

function renderLoadedLayout() {
  const target = activeTarget();
  if (!target) {
    dom.layoutRoot.className = "layout-root empty-state";
    dom.layoutRoot.textContent = "Connect to an OSCQuery target.";
    return;
  }

  if (target.layoutResizeObserver) {
    target.layoutResizeObserver.disconnect();
    target.layoutResizeObserver = null;
  }

  if (!target.layout) {
    dom.layoutRoot.className = "layout-root empty-state";
    dom.layoutRoot.innerHTML = "This target does not expose <code>/ui/layout</code> yet.";
    return;
  }

  dom.layoutRoot.innerHTML = "";
  dom.layoutRoot.className = "layout-root";
  const root = target.layout.root || target.layout;
  if (target.layout.defaultState && typeof target.layout.defaultState === "object") {
    Object.entries(target.layout.defaultState).forEach(([key, value]) => {
      if (target.layoutState[key] == null) target.layoutState[key] = value;
    });
  }

  const rootW = toNumber(root.w, 920);
  const rootH = toNumber(root.h, 360);
  const shell = makeElement("div", "layout-stage-shell");
  const scaler = makeElement("div", "layout-stage-scaler");
  const stage = makeElement("div", "layout-stage");
  stage.style.width = `${rootW}px`;
  stage.style.height = `${rootH}px`;
  scaler.append(stage);
  shell.append(scaler);
  dom.layoutRoot.append(shell);
  renderLayoutNode(target, root, stage);

  const updateScale = () => {
    const scale = Math.min(
      shell.clientWidth / Math.max(1, rootW),
      shell.clientHeight / Math.max(1, rootH),
    ) || 1;
    scaler.style.width = `${rootW * scale}px`;
    scaler.style.height = `${rootH * scale}px`;
    stage.style.transform = `scale(${scale})`;
    stage.style.transformOrigin = "top left";
  };

  updateScale();
  if (typeof ResizeObserver !== "undefined") {
    target.layoutResizeObserver = new ResizeObserver(() => updateScale());
    target.layoutResizeObserver.observe(shell);
  }
}

function addSurfaceWidget(target, endpoint) {
  const existing = target.currentSurface.find((item) => item.path === endpoint.path);
  if (existing) {
    setTargetStatus(target, `${endpoint.label} is already on the custom surface`);
    return;
  }
  const type = inferWidgetType(target, endpoint);
  if (type === "xy-y") {
    setTargetStatus(target, "Add the X endpoint for XY pairs, not the Y half", "error");
    return;
  }
  target.currentSurface.push({
    id: crypto.randomUUID(),
    path: endpoint.path,
    widgetType: type === "xy-x" ? "xy-x" : type,
    title: resolveDisplayLabel(target, endpoint),
  });
  renderIfActive(target);
}

function removeSurfaceWidget(target, id) {
  target.currentSurface = target.currentSurface.filter((item) => item.id !== id);
  renderIfActive(target);
}

function renderCustomSurface() {
  const container = dom.customSurface;
  const target = activeTarget();
  container.innerHTML = "";
  if (!target) {
    container.className = "custom-surface empty-state";
    container.textContent = "Connect to an OSCQuery target.";
    return;
  }
  if (!target.currentSurface.length) {
    container.className = "custom-surface empty-state";
    container.textContent = "Add parameters from the left browser to build a custom control page.";
    return;
  }

  container.className = "custom-surface";
  target.currentSurface.forEach((widget) => {
    const endpoint = target.endpointMap.get(widget.path);
    if (!endpoint) return;

    const article = makeElement("article", "surface-widget");
    const header = makeElement("div", "header");
    const titleRow = makeElement("div", "title-row");
    const titleBlock = makeElement("div");
    titleBlock.append(makeElement("strong", "", widget.title || resolveDisplayLabel(target, endpoint)), makeElement("div", "path", endpoint.path));
    const removeButton = makeElement("button", "danger", "Remove");
    removeButton.addEventListener("click", () => removeSurfaceWidget(target, widget.id));
    titleRow.append(titleBlock, removeButton);
    header.append(titleRow);

    const body = makeElement("div", "body");
    const options = makeElement("div", "widget-options");
    const typeSelect = document.createElement("select");
    ["slider", "slider-int", "choice", "toggle", "readout", "xy-x"].forEach((type) => {
      const option = document.createElement("option");
      option.value = type;
      option.textContent = type === "xy-x" ? "xy" : type === "choice" ? "dropdown" : type;
      if (widget.widgetType === type) option.selected = true;
      typeSelect.append(option);
    });
    typeSelect.addEventListener("change", () => {
      widget.widgetType = typeSelect.value;
      renderIfActive(target);
    });

    const titleInput = document.createElement("input");
    titleInput.type = "text";
    titleInput.value = widget.title || resolveDisplayLabel(target, endpoint);
    titleInput.placeholder = resolveDisplayLabel(target, endpoint);
    titleInput.addEventListener("change", () => {
      widget.title = titleInput.value.trim() || resolveDisplayLabel(target, endpoint);
      renderIfActive(target);
    });

    options.append(typeSelect, titleInput);
    body.append(options);

    const control = buildControl(target, { ...endpoint, label: widget.title || resolveDisplayLabel(target, endpoint) }, widget.widgetType);
    if (control) body.append(control);
    article.append(header, body);
    container.append(article);
  });
}

function syncTabUi(target) {
  dom.tabButtons.forEach((button) => button.classList.toggle("active", button.dataset.tab === target?.activeTab));
  Object.entries(dom.tabPanels).forEach(([id, panel]) => panel.classList.toggle("active", id === target?.activeTab));
}

function renderActiveViews() {
  const target = activeTarget();
  if (target) {
    target.liveBindings = new Map();
    dom.hostInput.value = target.host;
    dom.portInput.value = String(target.port);
    dom.searchInput.value = target.search || "";
    syncTabUi(target);
  } else {
    dom.searchInput.value = "";
    syncTabUi({ activeTab: "generic" });
  }
  updateConnectionMeta();
  renderEndpointBrowser();
  renderGenericGroups();
  renderCustomSurface();
  if (target?.activeTab === "layout") renderLoadedLayout();
  else if (!target) renderLoadedLayout();
}

function setActiveTab(tabId) {
  const target = activeTarget();
  if (!target) return;
  target.activeTab = tabId;
  syncTabUi(target);
  if (tabId === "layout") renderLoadedLayout();
  if (tabId === "custom") renderCustomSurface();
  if (tabId === "generic") renderGenericGroups();
}

function bindEvents() {
  dom.connectForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const host = dom.hostInput.value.trim() || "127.0.0.1";
    const rawPorts = dom.portInput.value.trim() || "9011";
    const ports = Array.from(new Set(rawPorts
      .split(/[\s,]+/)
      .map((value) => clamp(toNumber(value, NaN), 1, 65535))
      .filter((value) => Number.isFinite(value))));
    ports.forEach((port) => {
      void connectTarget(host, port);
    });
  });

  dom.searchInput.addEventListener("input", () => {
    const target = activeTarget();
    if (!target) return;
    target.search = dom.searchInput.value;
    applySearchFilter(target);
  });

  dom.reloadLayoutButton.addEventListener("click", () => {
    const target = activeTarget();
    if (!target) return;
    void loadLayout(target, false);
  });

  dom.saveSurfaceButton.addEventListener("click", () => {
    const target = activeTarget();
    if (!target) return;
    saveSurface(target);
  });

  dom.clearSurfaceButton.addEventListener("click", () => {
    const target = activeTarget();
    if (!target) return;
    target.currentSurface = [];
    renderCustomSurface();
  });

  dom.tabButtons.forEach((button) => {
    button.addEventListener("click", () => setActiveTab(button.dataset.tab));
  });

  window.addEventListener("beforeunload", () => {
    Array.from(state.targets.values()).forEach((target) => closeSocket(target));
  });
}

function init() {
  loadSavedConnection();
  dom.hostInput.value = state.lastHost;
  dom.portInput.value = String(state.lastPort);
  bindEvents();
  renderTargetNav();
  renderActiveViews();
}

init();
