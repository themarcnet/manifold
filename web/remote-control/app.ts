type AnyRecord = Record<string, any>;
type LiveValueOptions = { scheduleRender?: boolean };

const STORAGE_KEY = "manifold.remote.connection.v1";
const GLOBAL_SURFACE_KEY = "manifold.remote.surface.global.v2";
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

const DISCOVERY_ENDPOINT = "/__oscq/targets";
const DISCOVERY_POLL_MS = 750;

const state = {
  lastHost: "127.0.0.1",
  lastPort: 9011,
  targets: new Map<string, AnyRecord>(),
  activeTargetId: null as string | null,
  discoveryPollTimer: 0 as number | ReturnType<typeof setInterval>,
  selectedWidgetId: null as string | null,
  dragState: null as AnyRecord | null,
  editMode: true,
  showDebugTree: false,
  treePanelCollapsed: false,
  inspectorPanelCollapsed: false,
  canvasPanX: 0,
  canvasPanY: 0,
  globalSurface: [] as AnyRecord[],
};

const dom = {
  connectForm: document.querySelector("#connectForm") as HTMLFormElement,
  hostInput: document.querySelector("#hostInput") as HTMLInputElement,
  portInput: document.querySelector("#portInput") as HTMLInputElement,
  targetNav: document.querySelector("#targetNav") as HTMLElement,
  statusText: document.querySelector("#statusText") as HTMLElement,
  connectionMeta: document.querySelector("#connectionMeta") as HTMLElement,
  endpointList: document.querySelector("#endpointList") as HTMLElement,
  genericGroups: document.querySelector("#genericGroups") as HTMLElement,
  layoutRoot: document.querySelector("#layoutRoot") as HTMLElement,
  customSurface: document.querySelector("#customSurface") as HTMLElement,
  searchInput: document.querySelector("#searchInput") as HTMLInputElement,
  reloadLayoutButton: document.querySelector("#reloadLayoutButton") as HTMLButtonElement,
  saveSurfaceButton: document.querySelector("#saveSurfaceButton") as HTMLButtonElement,
  clearSurfaceButton: document.querySelector("#clearSurfaceButton") as HTMLButtonElement,
  tabButtons: Array.from(document.querySelectorAll<HTMLButtonElement>(".tab-button")),
  tabPanels: {
    generic: document.querySelector("#genericTab") as HTMLElement,
    layout: document.querySelector("#layoutTab") as HTMLElement,
    custom: document.querySelector("#customTab") as HTMLElement,
  },
  deviceTree: document.querySelector("#deviceTree") as HTMLElement,
  deviceTreeSearch: document.querySelector("#deviceTreeSearch") as HTMLInputElement,
  parameterSidebar: document.querySelector("#parameterSidebar") as HTMLElement,
  deviceTreeSidebar: document.querySelector("#deviceTreeSidebar") as HTMLElement,
  inspectorPanel: document.querySelector("#inspectorPanel") as HTMLElement,
  inspectorContent: document.querySelector("#inspectorContent") as HTMLElement,
  treePanelToggle: document.querySelector("#treePanelToggle") as HTMLButtonElement,
  inspectorPanelToggle: document.querySelector("#inspectorPanelToggle") as HTMLButtonElement,
  editModeToggle: document.querySelector("#editModeToggle") as HTMLButtonElement,
  workspace: document.querySelector("#workspace") as HTMLElement,
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

function activeTarget(): AnyRecord | null {
  return state.activeTargetId ? state.targets.get(state.activeTargetId) || null : null;
}

function makeElement<K extends keyof HTMLElementTagNameMap>(tag: K, className?: string, text?: string) {
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

function loadGlobalSurface() {
  try {
    const raw = localStorage.getItem(GLOBAL_SURFACE_KEY);
    state.globalSurface = raw ? JSON.parse(raw) : [];
  } catch (error) {
    console.warn("failed to load global custom surface", error);
    state.globalSurface = [];
  }
}

function saveGlobalSurface() {
  localStorage.setItem(GLOBAL_SURFACE_KEY, JSON.stringify(state.globalSurface));
  setStatus("Saved global custom surface", "ok");
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

function buildProxyHttpUrl(target, path) {
  const url = new URL("/__oscq/http", window.location.origin);
  url.searchParams.set("host", target.host);
  url.searchParams.set("port", String(target.port));
  url.searchParams.set("path", path);
  return url.toString();
}

function buildProxyCommandUrl(target) {
  const url = new URL("/__oscq/command", window.location.origin);
  url.searchParams.set("host", target.host);
  url.searchParams.set("port", String(target.port));
  return url.toString();
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
  const data = await fetchJson(buildProxyHttpUrl(target, `/osc${path}`));
  return data?.VALUE;
}

async function sendCommand(target, command) {
  const data = await fetchJson(buildProxyCommandUrl(target), {
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
        if (target.interactingPaths.has(current.path)) continue;
        const value = await queryValue(target, current.path);
        if (value !== undefined && !target.interactingPaths.has(current.path)) {
          setLiveValue(target, current.path, value);
        }
      } catch (error) {
        console.warn("value query failed", current.path, error);
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => worker()));
}

function closeSocket(target) {
  if (target?.pollTimer) {
    clearInterval(target.pollTimer);
    target.pollTimer = 0;
  }
  target.pollInFlight = false;
  if (!target?.ws) return;
  try {
    target.ws.close();
  } catch (error) {
    console.warn("ws close failed", error);
  }
  target.ws = null;
}

function renderIfActive(target) {
  const active = activeTarget();
  if (active === target || active?.activeTab === "custom") scheduleRender(active || target);
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
  if ((target.interactingPaths.size === 0 && (target.uiHoldCount || 0) === 0) || target.pendingRender) {
    scheduleRender(target);
  }
}

function beginUiHold(target) {
  if (!target) return;
  target.uiHoldCount = (target.uiHoldCount || 0) + 1;
}

function endUiHold(target) {
  if (!target) return;
  target.uiHoldCount = Math.max(0, (target.uiHoldCount || 0) - 1);
  if (target.uiHoldCount === 0 && target.pendingRender) {
    scheduleRender(target);
  }
}

function scheduleRender(target) {
  if (target?.interactingPaths?.size > 0 || (target?.uiHoldCount || 0) > 0) {
    target.pendingRender = true;
    return;
  }
  const active = activeTarget();
  if (active !== target && active?.activeTab !== "custom") {
    target.pendingRender = true;
    return;
  }
  if (target.renderFrame) return;
  target.pendingRender = false;
  target.renderFrame = requestAnimationFrame(() => {
    target.renderFrame = 0;
    target.pendingRender = false;
    renderActiveViews();
  });
}

function connectWebSocket(target) {
  closeSocket(target);
  console.log("[remote] opening ws", {
    id: target.id,
    wsUrl: target.wsUrl,
    pageOrigin: window.location.origin,
    pageProtocol: window.location.protocol,
  });
  const socket = new WebSocket(target.wsUrl);
  socket.binaryType = "arraybuffer";

  socket.addEventListener("open", () => {
    console.log("[remote] ws open", { id: target.id, wsUrl: target.wsUrl });
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
    if (target.interactingPaths.has(decoded.path)) return;
    setLiveValue(target, decoded.path, decoded.args.length <= 1 ? decoded.args[0] : decoded.args);
    if (decoded.path === "/plugin/params/type") {
      scheduleRender(target);
    }
  });

  socket.addEventListener("close", (event) => {
    console.warn("[remote] ws close", {
      id: target.id,
      wsUrl: target.wsUrl,
      code: event.code,
      reason: event.reason,
      wasClean: event.wasClean,
    });
    if (target.ws === socket) {
      target.ws = null;
      const details = event.reason ? `${event.code} ${event.reason}` : `${event.code}`;
      setTargetStatus(target, `Socket closed for ${target.id} (${details})`, event.code === 1000 || event.code === 1005 ? "" : "error");
    }
  });

  socket.addEventListener("error", (event) => {
    console.error("[remote] ws error", {
      id: target.id,
      wsUrl: target.wsUrl,
      pageOrigin: window.location.origin,
      pageProtocol: window.location.protocol,
      event,
    });
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

function hexToRgba(hex, alpha = 1) {
  const match = String(hex || "").trim().match(/^#?([0-9a-f]{6})$/i);
  if (!match) return String(hex || "rgba(255,255,255,1)");
  const value = match[1];
  const r = parseInt(value.slice(0, 2), 16);
  const g = parseInt(value.slice(2, 4), 16);
  const b = parseInt(value.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${clamp(alpha, 0, 1)})`;
}

function configureDirectManipulation(element) {
  if (!element) return;
  element.style.touchAction = "none";
  element.style.userSelect = "none";
  element.style.webkitUserSelect = "none";
  element.style.webkitTouchCallout = "none";
  element.style.webkitTapHighlightColor = "transparent";
  const preventDefault = (event) => event.preventDefault();
  element.addEventListener("dragstart", preventDefault);
  element.addEventListener("selectstart", preventDefault);
  element.addEventListener("contextmenu", preventDefault);
}

function createTarget(host, port) {
  return {
    id: targetId(host, port),
    host,
    port,
    discovered: false,
    lastSeenMs: 0,
    baseUrl: `http://${host}:${port}`,
    wsUrl: "",
    pollTimer: 0,
    pollInFlight: false,
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
    pendingRender: false,
    uiHoldCount: 0,
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

function getTargetInstanceName(target) {
  const baseName = String(deriveTargetName(target) || target.id).trim() || target.id;
  const siblings = Array.from(state.targets.values())
    .filter((candidate) => String(deriveTargetName(candidate) || candidate.id).trim() === baseName)
    .sort((a, b) => {
      const hostCompare = String(a.host).localeCompare(String(b.host));
      if (hostCompare !== 0) return hostCompare;
      const portCompare = Number(a.port || 0) - Number(b.port || 0);
      if (portCompare !== 0) return portCompare;
      return String(a.id).localeCompare(String(b.id));
    });
  const index = Math.max(1, siblings.findIndex((candidate) => candidate.id === target.id) + 1);
  return `${baseName}_${index}`;
}

function refreshTargetInstanceNames() {
  Array.from(state.targets.values()).forEach((target) => {
    target.name = getTargetInstanceName(target);
  });
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
  const xEndpointPath = "/plugin/ui/xyXParam";
  const yEndpointPath = "/plugin/ui/xyYParam";
  const xDefault = 1;
  const yDefault = Math.min(2, names.length);
  const xSource = target.endpointMap.has(xEndpointPath)
    ? target.values.get(xEndpointPath)
    : getLayoutStateValue(target, "fxXYXParam", xDefault);
  const ySource = target.endpointMap.has(yEndpointPath)
    ? target.values.get(yEndpointPath)
    : getLayoutStateValue(target, "fxXYYParam", yDefault);
  let xIdx = Math.max(1, Math.floor(toNumber(xSource, xDefault)));
  let yIdx = Math.max(1, Math.floor(toNumber(ySource, yDefault)));
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

function setLiveValue(target, path, value, options: LiveValueOptions = {}) {
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
    const layout = await fetchJson(buildProxyHttpUrl(target, `/ui/layout`));
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

function startPolling(target) {
  if (target.pollTimer) clearInterval(target.pollTimer);
  const tick = async () => {
    if (target.pollInFlight) return;
    if (target.interactingPaths.size > 0 || (target.uiHoldCount || 0) > 0) return;
    target.pollInFlight = true;
    try {
      await hydrateCurrentValues(target);
    } catch (error) {
      console.warn("poll failed", target.id, error);
    } finally {
      target.pollInFlight = false;
    }
  };
  void tick();
  target.pollTimer = setInterval(() => {
    void tick();
  }, 1500);
}

async function connectTarget(host, port, options: AnyRecord = {}) {
  const id = targetId(host, port);
  const activate = options.activate !== false;
  const remember = options.remember !== false;
  const discovered = options.discovered === true;
  if (state.targets.has(id)) {
    const existing = state.targets.get(id);
    if (existing) {
      if (discovered) existing.discovered = true;
      if (Number.isFinite(Number(options.lastSeenMs))) {
        existing.lastSeenMs = Number(options.lastSeenMs);
      }
    }
    if (activate) {
      switchActiveTarget(id);
    }
    return;
  }

  console.log("[remote] connectTarget:start", {
    host,
    port,
    pageOrigin: window.location.origin,
    pageProtocol: window.location.protocol,
  });

  const target = createTarget(host, port);
  target.discovered = discovered;
  if (Number.isFinite(Number(options.lastSeenMs))) {
    target.lastSeenMs = Number(options.lastSeenMs);
  }
  state.targets.set(id, target);
  refreshTargetInstanceNames();
  if (activate || !state.activeTargetId) {
    state.activeTargetId = id;
  }
  if (remember) {
    saveConnection(host, port);
  }
  renderTargetNav();
  renderActiveViews();

  try {
    const [hostInfo, tree, uiMeta] = await Promise.all([
      fetchJson(buildProxyHttpUrl(target, `/?HOST_INFO`)),
      fetchJson(buildProxyHttpUrl(target, `/`)),
      fetchJson(buildProxyHttpUrl(target, `/ui/meta`)).catch(() => null),
    ]);

    target.hostInfo = hostInfo;
    target.uiMeta = uiMeta;
    target.paramMeta = buildParamMetaMap(uiMeta);
    target.tree = tree;
    target.wsUrl = `ws://${target.host}:${Number(hostInfo?.WS_PORT || target.port)}`;
    console.log("[remote] connectTarget:resolved", {
      id: target.id,
      baseUrl: target.baseUrl,
      wsUrl: target.wsUrl,
      hostInfo,
    });
    target.endpoints = mergeMetadataIntoEndpoints(target, flattenOscTree(tree)).sort((a, b) => a.path.localeCompare(b.path));
    target.endpointMap = new Map(target.endpoints.map((endpoint) => [endpoint.path, endpoint]));
    target.values = new Map();
    refreshTargetInstanceNames();
    applySearchFilter(target);
    renderTargetNav();
    renderIfActive(target);

    await Promise.all([
      hydrateCurrentValues(target),
      loadLayout(target, true),
    ]);

    startPolling(target);
    refreshTargetInstanceNames();
    setTargetStatus(target, `Connected to ${target.id} via Vite proxy`, "ok");
    renderTargetNav();
    renderIfActive(target);
  } catch (error) {
    closeSocket(target);
    state.targets.delete(id);
    refreshTargetInstanceNames();
    if (state.activeTargetId === id) {
      state.activeTargetId = state.targets.size ? Array.from(state.targets.keys())[0] : null;
    }
    setStatus(`Connection failed: ${error.message}`, "error");
    renderTargetNav();
    renderActiveViews();
    console.error("[remote] connectTarget:failed", {
      id,
      baseUrl: target.baseUrl,
      pageOrigin: window.location.origin,
      pageProtocol: window.location.protocol,
      error,
    });
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
  refreshTargetInstanceNames();
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

function buildCompactSliderControl(target, endpoint, options: AnyRecord = {}) {
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

function buildFilterGraphControl(target, bindConfig, style: AnyRecord = {}, bounds: AnyRecord = {}) {
  const panel = makeElement("div", "filter-graph-shell");
  const canvas = document.createElement("canvas");
  const width = Math.max(64, Math.floor(bounds.width || 452));
  const height = Math.max(48, Math.floor(bounds.height || 188));
  canvas.width = width;
  canvas.height = height;
  panel.append(canvas);
  configureDirectManipulation(canvas);

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
    const typeValue = Math.round(toNumber(target.values.get(bindConfig.typePath), 0));
    const cutoff = clamp(toNumber(target.values.get(bindConfig.cutoffPath), 3200), minFreq, maxFreq);
    const resonance = clamp(toNumber(target.values.get(bindConfig.resonancePath), 0.75), minReso, maxReso);

    ctx2d.clearRect(0, 0, width, height);
    ctx2d.fillStyle = style.bg || "#0d1420";
    ctx2d.fillRect(0, 0, width, height);

    const colDim = `rgba(167, 139, 250, 0.125)`;
    const colMid = `rgba(167, 139, 250, 0.38)`;
    const freqToCanvasX = (freq) => (Math.log(freq) - logMin) / (logMax - logMin) * width;
    const zeroY = Math.floor(height * 0.5);

    [100, 500, 1000, 5000, 10000].forEach((f) => {
      const x = freqToCanvasX(f);
      ctx2d.strokeStyle = "#1a1a3a";
      ctx2d.lineWidth = 1;
      ctx2d.beginPath();
      ctx2d.moveTo(x, 0);
      ctx2d.lineTo(x, height);
      ctx2d.stroke();
    });

    [-24, -12, 0, 12, 24].forEach((db) => {
      const y = Math.floor(height * 0.5 - (db / dbRange) * height * 0.45);
      if (y >= 0 && y <= height) {
        ctx2d.strokeStyle = db === 0 ? "#1f2b4d" : "#1a1a3a";
        ctx2d.lineWidth = 1;
        ctx2d.beginPath();
        ctx2d.moveTo(0, y);
        ctx2d.lineTo(width, y);
        ctx2d.stroke();
      }
    });

    const cutoffX = freqToCanvasX(cutoff);
    ctx2d.strokeStyle = colMid;
    ctx2d.lineWidth = 1;
    ctx2d.beginPath();
    ctx2d.moveTo(cutoffX, 0);
    ctx2d.lineTo(cutoffX, height);
    ctx2d.stroke();

    const numPoints = Math.max(60, Math.min(width, 200));
    let prevX = null;
    let prevY = null;

    for (let i = 0; i <= numPoints; i += 1) {
      const t = i / numPoints;
      let freq = Math.exp(logMin + t * (logMax - logMin));
      freq = Math.max(cutoff * 0.25, Math.min(cutoff * 4, freq));
      const mag = svfMagnitude(freq, cutoff, resonance, typeValue);
      let db = 20 * Math.log10(mag + 1e-10);
      db = clamp(db, -dbRange, dbRange);

      const x = Math.floor(t * width);
      let y = Math.floor(height * 0.5 - (db / dbRange) * height * 0.45);
      y = clamp(y, 1, height - 1);

      if (i > 0) {
        ctx2d.strokeStyle = colDim;
        ctx2d.lineWidth = Math.max(1, Math.ceil(width / numPoints));
        ctx2d.beginPath();
        ctx2d.moveTo(x, y);
        ctx2d.lineTo(x, zeroY);
        ctx2d.stroke();
      }

      if (prevX != null) {
        ctx2d.strokeStyle = accent;
        ctx2d.lineWidth = 2;
        ctx2d.beginPath();
        ctx2d.moveTo(prevX, prevY);
        ctx2d.lineTo(x, y);
        ctx2d.stroke();
      }

      prevX = x;
      prevY = y;
    }

    const peakMag = svfMagnitude(cutoff, cutoff, resonance, typeValue);
    const peakDb = clamp(20 * Math.log10(peakMag + 1e-10), -dbRange, dbRange);
    const peakY = Math.floor(height * 0.5 - (peakDb / dbRange) * height * 0.45);
    const ptR = dragging ? 7 : 5;

    if (dragging) {
      ctx2d.fillStyle = `rgba(167, 139, 250, 0.27)`;
      ctx2d.beginPath();
      ctx2d.arc(cutoffX, peakY, ptR + 3, 0, Math.PI * 2);
      ctx2d.fill();
    }

    ctx2d.fillStyle = dragging ? accent : "#ffffff";
    ctx2d.beginPath();
    ctx2d.arc(cutoffX, peakY, ptR, 0, Math.PI * 2);
    ctx2d.fill();
  };

  let dragging = false;
  let activePointerId = null;
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

  registerLiveBinding(target, bindConfig.typePath, draw);
  registerLiveBinding(target, bindConfig.cutoffPath, draw);
  registerLiveBinding(target, bindConfig.resonancePath, draw);

  const applyPoint = (event) => {
    event.preventDefault();
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
    event.preventDefault();
    if (activePointerId != null) return;
    activePointerId = event.pointerId;
    dragging = true;
    beginInteraction(target, [bindConfig.cutoffPath, bindConfig.resonancePath]);
    canvas.setPointerCapture(event.pointerId);
    applyPoint(event);
  });
  canvas.addEventListener("pointermove", (event) => {
    if (!dragging || event.pointerId !== activePointerId) return;
    applyPoint(event);
  });
  const endDrag = (event) => {
    if (event?.pointerId != null && event.pointerId !== activePointerId) return;
    event?.preventDefault?.();
    dragging = false;
    activePointerId = null;
    endInteraction(target, [bindConfig.cutoffPath, bindConfig.resonancePath]);
  };
  canvas.addEventListener("pointerup", endDrag);
  canvas.addEventListener("pointercancel", endDrag);
  canvas.addEventListener("lostpointercapture", endDrag);

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

function buildEqGraphControl(target, bindConfig, style: AnyRecord = {}, bounds: AnyRecord = {}) {
  const panel = makeElement("div", "filter-graph-shell");
  const canvas = document.createElement("canvas");
  const width = Math.max(120, Math.floor(bounds.width || 452));
  const height = Math.max(72, Math.floor(bounds.height || 108));
  canvas.width = width;
  canvas.height = height;
  panel.append(canvas);
  configureDirectManipulation(canvas);

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

    const glowColor = (0x24 << 24) | (parseInt(style.accent || "#22d3ee", 16) & 0x00ffffff);
    ctx2d.strokeStyle = style.accent || "#22d3ee";
    ctx2d.lineWidth = 4;
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
      const r = selected ? 7 : 5;
      const rg = selected ? 9 : 7;
      const rw = selected ? 6 : 4;
      const pointGlowColor = hexToRgba(bandColors[idx], 64 / 255);
      ctx2d.fillStyle = pointGlowColor;
      ctx2d.beginPath();
      ctx2d.arc(point.x, point.y, rg, 0, Math.PI * 2);
      ctx2d.fill();
      ctx2d.fillStyle = bandColors[idx];
      ctx2d.beginPath();
      ctx2d.arc(point.x, point.y, r, 0, Math.PI * 2);
      ctx2d.fill();
      ctx2d.strokeStyle = selected ? "#ffffff" : "#0f172a";
      ctx2d.lineWidth = selected ? 2 : 1;
      ctx2d.beginPath();
      ctx2d.arc(point.x, point.y, rw, 0, Math.PI * 2);
      ctx2d.stroke();
    });
  };

  for (let i = 1; i <= 8; i += 1) {
    registerLiveBinding(target, `${bandBase}/${i}/enabled`, draw);
    registerLiveBinding(target, `${bandBase}/${i}/type`, draw);
    registerLiveBinding(target, `${bandBase}/${i}/freq`, draw);
    registerLiveBinding(target, `${bandBase}/${i}/gain`, draw);
    registerLiveBinding(target, `${bandBase}/${i}/q`, draw);
  }

  let queuedBand = null;
  let sending = false;
  let dragging = false;
  let activePointerId = null;
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
    event.preventDefault();
    if (activePointerId != null) return;
    activePointerId = event.pointerId;
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
    if (!dragging || event.pointerId !== activePointerId) return;
    event.preventDefault();
    const selectedBand = Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    if (!selectedBand) return;
    const point = eventPoint(event);
    updateBandFromPosition(selectedBand, point.x, point.y);
  });

  const endDrag = (event) => {
    if (event?.pointerId != null && event.pointerId !== activePointerId) return;
    event?.preventDefault?.();
    const selectedBand = Number(getLayoutStateValue(target, selectedBandStateKey, 1));
    dragging = false;
    activePointerId = null;
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
  canvas.addEventListener("lostpointercapture", endDrag);

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

function buildLayoutXyControl(target, bind, style: AnyRecord = {}, bounds: AnyRecord = {}) {
  const root = makeElement("div", "layout-xy");
  const canvas = document.createElement("canvas");
  const width = Math.max(128, Math.floor(bounds.width || 256));
  const height = Math.max(128, Math.floor(bounds.height || 256));
  canvas.width = width;
  canvas.height = height;
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  root.append(canvas);
  configureDirectManipulation(root);
  configureDirectManipulation(canvas);

  const ctx2d = canvas.getContext("2d");
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
  const bgColour = style.bg || "#0d1420";
  const gridColour = style.gridColour || "#1a1a3a";
  root.style.setProperty("--xy-accent", accent);
  if (style.bg) root.style.background = style.bg;
  if (style.border) root.style.borderColor = style.border;
  if (style.radius != null) root.style.borderRadius = `${style.radius}px`;
  if (bounds.width > 0) root.style.width = `${bounds.width}px`;
  if (bounds.height > 0) root.style.height = `${bounds.height}px`;

  const drawPad = () => {
    const resolved = resolveBinding();
    const xValue = toNumber(target.values.get(resolved.xPath), xRange.min);
    const yValue = toNumber(target.values.get(resolved.yPath), yRange.min);
    const xNorm = xRange.max === xRange.min ? 0 : (xValue - xRange.min) / (xRange.max - xRange.min);
    const yNorm = yRange.max === yRange.min ? 0 : (yValue - yRange.min) / (yRange.max - yRange.min);
    const px = clamp(xNorm, 0, 1) * width;
    const py = height - clamp(yNorm, 0, 1) * height;

    ctx2d.clearRect(0, 0, width, height);

    // Background with grid
    ctx2d.fillStyle = bgColour;
    ctx2d.fillRect(0, 0, width, height);

    // Grid lines
    ctx2d.strokeStyle = gridColour;
    ctx2d.lineWidth = 1;
    for (let i = 1; i <= 3; i++) {
      const gx = (width / 4) * i;
      ctx2d.beginPath();
      ctx2d.moveTo(gx, 0);
      ctx2d.lineTo(gx, height);
      ctx2d.stroke();
    }
    for (let i = 1; i <= 3; i++) {
      const gy = (height / 4) * i;
      ctx2d.beginPath();
      ctx2d.moveTo(0, gy);
      ctx2d.lineTo(width, gy);
      ctx2d.stroke();
    }

    // Crosshair at center
    const cx = width / 2;
    const cy = height / 2;
    ctx2d.strokeStyle = accent;
    ctx2d.globalAlpha = 0.35;
    ctx2d.beginPath();
    ctx2d.moveTo(cx, 0);
    ctx2d.lineTo(cx, height);
    ctx2d.stroke();
    ctx2d.beginPath();
    ctx2d.moveTo(0, cy);
    ctx2d.lineTo(width, cy);
    ctx2d.stroke();
    ctx2d.globalAlpha = 1;

    // Crosshair at position
    const posColour = accent;
    ctx2d.strokeStyle = posColour;
    ctx2d.globalAlpha = 0.35;
    ctx2d.beginPath();
    ctx2d.moveTo(px, 0);
    ctx2d.lineTo(px, height);
    ctx2d.stroke();
    ctx2d.beginPath();
    ctx2d.moveTo(0, py);
    ctx2d.lineTo(width, py);
    ctx2d.stroke();
    ctx2d.globalAlpha = 1;

    // Filled quadrant
    const dimColour = hexToRgba(accent, 24 / 255);
    ctx2d.fillStyle = dimColour;
    ctx2d.fillRect(0, py, px, height - py);

    // Glow effect (3-layer)
    for (let i = 3; i >= 1; i--) {
      const glowSize = 8 + i * 6;
      const alpha = 60 - i * 18;
      ctx2d.fillStyle = hexToRgba(accent, alpha / 255);
      ctx2d.beginPath();
      ctx2d.arc(px, py, glowSize / 2, 0, Math.PI * 2);
      ctx2d.fill();
    }

    // Outer ring
    ctx2d.fillStyle = "#33ffffff";
    ctx2d.beginPath();
    ctx2d.arc(px, py, 7, 0, Math.PI * 2);
    ctx2d.fill();

    // Main handle
    ctx2d.fillStyle = "#ffffff";
    ctx2d.beginPath();
    ctx2d.arc(px, py, 5, 0, Math.PI * 2);
    ctx2d.fill();

    // Inner dot
    ctx2d.fillStyle = accent;
    ctx2d.beginPath();
    ctx2d.arc(px, py, 2, 0, Math.PI * 2);
    ctx2d.fill();

    // Value labels
    ctx2d.fillStyle = "#cbd5e1";
    ctx2d.font = "9px Inter, sans-serif";
    ctx2d.textAlign = "left";
    ctx2d.fillText(`X: ${Math.round(xNorm * 100)}%`, 4, height - 4);
    ctx2d.textAlign = "right";
    ctx2d.fillText(`Y: ${Math.round(yNorm * 100)}%`, width - 4, 12);
  };

  drawPad();

  registerLiveBinding(target, binding.xPath, drawPad);
  registerLiveBinding(target, binding.yPath, drawPad);

  if (isFxTarget(target)) {
    registerLiveBinding(target, "/plugin/params/type", drawPad);
  }

  let dragging = false;
  let activePointerId = null;
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
    event.preventDefault();
    const rect = root.getBoundingClientRect();
    const px = clamp((event.clientX - rect.left) / rect.width, 0, 1);
    const py = clamp((event.clientY - rect.top) / rect.height, 0, 1);
    const xValue = xRange.min + px * (xRange.max - xRange.min);
    const yValue = yRange.min + (1 - py) * (yRange.max - yRange.min);
    setLiveValue(target, binding.xPath, xValue);
    setLiveValue(target, binding.yPath, yValue);
    queued = { xPath: binding.xPath, yPath: binding.yPath, x: xValue, y: yValue, xEndpoint, yEndpoint };
    drawPad();
    void flush();
  };

  root.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    if (activePointerId != null) return;
    activePointerId = event.pointerId;
    dragging = true;
    beginInteraction(target, [binding.xPath, binding.yPath]);
    root.setPointerCapture(event.pointerId);
    applyPointer(event);
  });
  root.addEventListener("pointermove", (event) => {
    if (!dragging || event.pointerId !== activePointerId) return;
    applyPointer(event);
  });
  root.addEventListener("pointerup", (event) => { if (event.pointerId !== activePointerId) return; event.preventDefault(); dragging = false; activePointerId = null; endInteraction(target, [binding.xPath, binding.yPath]); });
  root.addEventListener("pointercancel", (event) => { if (event.pointerId !== activePointerId) return; event.preventDefault(); dragging = false; activePointerId = null; endInteraction(target, [binding.xPath, binding.yPath]); });
  root.addEventListener("lostpointercapture", () => { dragging = false; activePointerId = null; endInteraction(target, [binding.xPath, binding.yPath]); });

  return root;
}

function buildLuaSliderControl(target, endpoint, options: AnyRecord = {}) {
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

function buildLuaToggleControl(target, endpoint, options: AnyRecord = {}) {
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

function buildLuaDropdown(target, config: AnyRecord) {
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
  let popupHeld = false;
  const closePopup = () => {
    if (!popup) return;
    popup.remove();
    popup = null;
    arrow.textContent = "▼";
    root.parentElement?.parentElement?.classList.remove("open-popup");
    if (popupHeld) {
      popupHeld = false;
      endUiHold(target);
    }
  };

  root.addEventListener("click", async (event) => {
    event.stopPropagation();
    if (config.disabled) return;
    if (popup && popup.contains(event.target)) {
      return;
    }
    if (popup) {
      closePopup();
      return;
    }
    arrow.textContent = "▲";
    root.parentElement?.parentElement?.classList.add("open-popup");
    if (!popupHeld) {
      popupHeld = true;
      beginUiHold(target);
    }
    popup = makeElement("div", "lua-dropdown-popup");
    const options = config.getOptions();
    options.forEach((option) => {
      const row = makeElement("div", `lua-dropdown-option ${option.selected ? "selected" : ""}`, option.label);
      row.addEventListener("pointerdown", (e) => {
        e.stopPropagation();
      });
      row.addEventListener("click", async (e) => {
        e.preventDefault();
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

function buildLuaEndpointDropdown(target, endpoint, node: AnyRecord = {}, style: AnyRecord = {}) {
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

function buildLuaLocalDropdown(target, node: AnyRecord, style: AnyRecord = {}) {
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

function buildFxAssignDropdown(target, axis, node: AnyRecord, style: AnyRecord = {}) {
  const stateKey = axis === "x" ? "fxXYXParam" : "fxXYYParam";
  const endpointPath = axis === "x" ? "/plugin/ui/xyXParam" : "/plugin/ui/xyYParam";
  const endpoint = target.endpointMap.get(endpointPath) || null;
  return buildLuaDropdown(target, {
    style,
    fontSize: `${Math.min(10, Math.max(7, (node.h || 20) - 8))}px`,
    disabled: endpoint ? !isWritable(endpoint) : node.disabled === true,
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
      const nextValue = Number(value);
      if (endpoint) {
        setLiveValue(target, endpoint.path, nextValue, { scheduleRender: true });
        await writeValue(target, endpoint.path, nextValue, endpoint);
      } else {
        setLayoutStateValue(target, stateKey, nextValue);
        scheduleRender(target);
      }
    },
  });
}

function buildControl(target, endpoint, overrideWidgetType = null, options: AnyRecord = {}) {
  const path = endpoint.path;
  const showPath = options.showPath !== false;
  let widgetType = overrideWidgetType || inferWidgetType(target, endpoint);
  if (widgetType === "xy-y") return null;
  if (widgetType === "dropdown") widgetType = "choice";
  if (widgetType === "knob" || widgetType === "vslider") widgetType = "slider";

  const controlCard = makeElement("div", "control-card");
  if (showPath) controlCard.append(makeElement("div", "control-path", path));

  if (widgetType === "toggle") {
    const row = makeElement("button", "toggle-pill");
    const refreshToggle = () => {
      const current = Boolean(target.values.get(path));
      row.textContent = `${options.label || resolveDisplayLabel(target, endpoint) || prettyLabel(path)} • ${formatEndpointValue(endpoint, current)}`;
      row.classList.toggle("active", current);
    };
    refreshToggle();
    registerLiveBinding(target, path, refreshToggle);
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
    const derivedYPath = path.endsWith("/x") ? path.replace(/\/x$/, "/y") : path.replace(/\/mix_x$/, "/mix_y");
    const yTarget = options.xyYTargetId ? state.targets.get(options.xyYTargetId) || target : target;
    const yPath = options.xyYPath || derivedYPath;
    const yEndpoint = yTarget?.endpointMap?.get(yPath);
    const yValue = toNumber(yTarget?.values?.get(yPath), hasRange(yEndpoint) ? getRange(yEndpoint).min : 0);
    const xValue = toNumber(target.values.get(path), endpoint.defaultValue ?? getRange(endpoint).min);
    const xRange = getRange(endpoint);
    const yRange = getRange(yEndpoint || { range: [{ MIN: 0, MAX: 1 }] });

    const wrap = makeElement("div", "xy-wrap");
    const pad = makeElement("div", "xy-pad");
    configureDirectManipulation(pad);
    const handle = makeElement("div", "xy-handle");
    const xNorm = xRange.max === xRange.min ? 0 : (xValue - xRange.min) / (xRange.max - xRange.min);
    const yNorm = yRange.max === yRange.min ? 0 : (yValue - yRange.min) / (yRange.max - yRange.min);
    handle.style.left = `${clamp(xNorm, 0, 1) * 100}%`;
    handle.style.top = `${(1 - clamp(yNorm, 0, 1)) * 100}%`;
    pad.append(handle);

    const commitPointer = async (event) => {
      event.preventDefault();
      if (!yEndpoint || !yTarget) return;
      const rect = pad.getBoundingClientRect();
      const px = clamp((event.clientX - rect.left) / rect.width, 0, 1);
      const py = clamp((event.clientY - rect.top) / rect.height, 0, 1);
      const nextX = xRange.min + px * (xRange.max - xRange.min);
      const nextY = yRange.min + (1 - py) * (yRange.max - yRange.min);
      handle.style.left = `${px * 100}%`;
      handle.style.top = `${py * 100}%`;
      setLiveValue(target, path, nextX);
      setLiveValue(yTarget, yPath, nextY);
      try {
        await Promise.all([
          writeValue(target, path, nextX, endpoint),
          writeValue(yTarget, yPath, nextY, yEndpoint),
        ]);
      } catch (error) {
        setTargetStatus(target, `XY write failed: ${error.message}`, "error");
      }
    };

    let dragging = false;
    let activePointerId = null;
    pad.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      if (activePointerId != null) return;
      activePointerId = event.pointerId;
      dragging = true;
      beginInteraction(target, [path]);
      if (yTarget) beginInteraction(yTarget, [yPath]);
      pad.setPointerCapture(event.pointerId);
      commitPointer(event);
    });
    pad.addEventListener("pointermove", (event) => {
      if (!dragging || event.pointerId !== activePointerId) return;
      commitPointer(event);
    });
    pad.addEventListener("pointerup", (event) => {
      if (event.pointerId !== activePointerId) return;
      event.preventDefault();
      dragging = false;
      activePointerId = null;
      endInteraction(target, [path]);
      if (yTarget) endInteraction(yTarget, [yPath]);
    });
    pad.addEventListener("pointercancel", (event) => {
      if (event.pointerId !== activePointerId) return;
      event.preventDefault();
      dragging = false;
      activePointerId = null;
      endInteraction(target, [path]);
      if (yTarget) endInteraction(yTarget, [yPath]);
    });
    pad.addEventListener("lostpointercapture", () => {
      dragging = false;
      activePointerId = null;
      endInteraction(target, [path]);
      if (yTarget) endInteraction(yTarget, [yPath]);
    });

    const values = makeElement("div", "xy-values");
    const yLabel = yEndpoint
      ? `${options.xyYTargetId && yTarget && yTarget !== target ? `${getTargetInstanceName(yTarget)} • ` : ""}${resolveDisplayLabel(yTarget || target, yEndpoint, "Y") || "Y"}`
      : "Y (unbound)";
    values.append(
      makeElement("span", "", `${options.label || resolveDisplayLabel(target, endpoint, "X") || "X"}: ${formatEndpointValue(endpoint, xValue)}`),
      makeElement("span", "", `${yLabel}: ${formatEndpointValue(yEndpoint || {}, yValue)}`),
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

function isTreeVisibleEndpoint(endpoint) {
  const path = String(endpoint?.path || "").toLowerCase();
  if (!state.showDebugTree) {
    if (!isWritable(endpoint)) return false;
    if (path.startsWith("/ui") || path.includes("/ui/")) return false;
    if (path.startsWith("/debug") || path.includes("/debug/")) return false;
    if (path.startsWith("/stats") || path.includes("/stats/")) return false;
    if (path.includes("meter") || path.includes("telemetry")) return false;
  }
  return true;
}

function getTreeEndpoints(target) {
  return (target?.endpoints || []).filter(isTreeVisibleEndpoint);
}

function renderDeviceTree() {
  const container = dom.deviceTree;
  container.innerHTML = "";
  const targets = Array.from(state.targets.values()).sort((a, b) => getTargetInstanceName(a).localeCompare(getTargetInstanceName(b)));
  if (!targets.length) {
    container.className = "device-tree empty-state";
    container.textContent = "Connect to an OSCQuery target.";
    return;
  }
  container.className = "device-tree";

  const filter = (dom.deviceTreeSearch?.value || "").trim().toLowerCase();
  let renderedAny = false;

  targets.forEach((target) => {
    const endpoints = getTreeEndpoints(target)
      .filter((endpoint) => {
        if (!filter) return true;
        const label = resolveDisplayLabel(target, endpoint).toLowerCase();
        const path = String(endpoint.path || "").toLowerCase();
        const targetName = getTargetInstanceName(target).toLowerCase();
        return label.includes(filter) || path.includes(filter) || targetName.includes(filter);
      })
      .sort((a, b) => {
        const aLabel = resolveDisplayLabel(target, a);
        const bLabel = resolveDisplayLabel(target, b);
        return aLabel.localeCompare(bLabel) || a.path.localeCompare(b.path);
      });

    if (!endpoints.length && filter) return;
    renderedAny = true;

    const deviceItem = makeElement("div", "device-tree-item device target-root");
    const toggle = makeElement("span", "device-tree-toggle", "▼");
    const icon = makeElement("span", "device-tree-icon", "📦");
    const label = makeElement("span", "device-tree-label", getTargetInstanceName(target));
    deviceItem.append(toggle, icon, label);
    deviceItem.draggable = true;
    deviceItem.addEventListener("dragstart", (event) => {
      event.dataTransfer?.setData("application/x-manifold-device", JSON.stringify({ targetId: target.id }));
      event.dataTransfer.effectAllowed = "copy";
    });

    const childContainer = makeElement("div", "device-tree-children");
    endpoints.forEach((endpoint) => {
      const item = makeElement("div", "device-tree-item param");
      item.draggable = true;
      item.title = endpoint.path;
      item.append(
        makeElement("span", "device-tree-toggle", ""),
        makeElement("span", "device-tree-icon", "🎛️"),
        makeElement("span", "device-tree-label", resolveDisplayLabel(target, endpoint)),
      );
      item.addEventListener("dragstart", (event) => {
        event.dataTransfer?.setData("application/x-manifold-param", JSON.stringify({ targetId: target.id, path: endpoint.path }));
        event.dataTransfer.effectAllowed = "copy";
      });
      childContainer.append(item);
    });

    deviceItem.addEventListener("click", () => {
      const collapsed = childContainer.classList.toggle("collapsed");
      toggle.classList.toggle("collapsed", collapsed);
    });

    container.append(deviceItem, childContainer);
  });

  if (!renderedAny) {
    container.className = "device-tree empty-state";
    container.textContent = filter ? "No matching parameters." : "No parameters available.";
  }
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

function renderLayoutNode(target, node: AnyRecord, parent, inheritedStyle: AnyRecord = {}) {
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

function addSurfaceWidget(target, endpoint, x = 20, y = 20) {
  const type = inferWidgetType(target, endpoint);
  if (type === "xy-y") {
    setTargetStatus(target, "Add the X endpoint for XY pairs, not the Y half", "error");
    return;
  }
  const existing = state.globalSurface.length;
  const isXy = type === "xy-x";
  const defaultYPath = endpoint.path.endsWith("/x")
    ? endpoint.path.replace(/\/x$/, "/y")
    : endpoint.path.endsWith("/mix_x")
      ? endpoint.path.replace(/\/mix_x$/, "/mix_y")
      : null;
  state.globalSurface.push({
    id: crypto.randomUUID(),
    targetId: target.id,
    path: endpoint.path,
    yTargetId: isXy && defaultYPath ? target.id : null,
    yPath: isXy ? defaultYPath : null,
    widgetType: isXy ? "xy-x" : type,
    title: resolveDisplayLabel(target, endpoint),
    x: x + (existing % 10) * 10,
    y: y + Math.floor(existing / 10) * 10,
    w: 220,
    h: 60,
  });
  renderActiveViews();
}

function getSurfaceWidgetTarget(widget) {
  return state.targets.get(widget?.targetId) || activeTarget() || null;
}

function removeSurfaceWidget(_target, id) {
  state.globalSurface = state.globalSurface.filter((item) => item.id !== id);
  if (state.selectedWidgetId === id) state.selectedWidgetId = null;
  renderActiveViews();
}

function attachCanvasResizeHandle(el, widget, options: AnyRecord = {}) {
  const handle = makeElement("div", "canvas-resize-handle");
  handle.setAttribute("aria-label", "Resize widget");
  const minW = options.minW ?? 80;
  const minH = options.minH ?? 40;
  const maxW = options.maxW ?? 2000;
  const maxH = options.maxH ?? 1400;

  handle.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    event.stopPropagation();
    handle.setPointerCapture(event.pointerId);
    const startX = event.clientX;
    const startY = event.clientY;
    const startW = widget.w || el.offsetWidth || minW;
    const startH = widget.h || el.offsetHeight || minH;

    const onMove = (moveEvent) => {
      const nextW = clamp(startW + moveEvent.clientX - startX, minW, maxW);
      const nextH = clamp(startH + moveEvent.clientY - startY, minH, maxH);
      widget.w = nextW;
      widget.h = nextH;
      options.onResize?.(nextW, nextH);
    };

    const onUp = () => {
      handle.removeEventListener("pointermove", onMove);
      handle.removeEventListener("pointerup", onUp);
      handle.removeEventListener("pointercancel", onUp);
      options.onEnd?.();
    };

    handle.addEventListener("pointermove", onMove);
    handle.addEventListener("pointerup", onUp);
    handle.addEventListener("pointercancel", onUp);
  });

  el.append(handle);
}

function renderCustomSurface() {
  const container = dom.customSurface;
  container.innerHTML = "";
  container.className = state.editMode ? "custom-surface edit-mode" : "custom-surface play-mode";

  container.ondragover = (event) => {
    if (!state.editMode) return;
    if (event.dataTransfer?.types?.includes("application/x-manifold-param") || event.dataTransfer?.types?.includes("application/x-manifold-device")) {
      event.preventDefault();
      event.dataTransfer.dropEffect = "copy";
      container.classList.add("drag-over");
    }
  };
  container.ondragleave = () => container.classList.remove("drag-over");
  container.ondrop = (event) => {
    event.preventDefault();
    container.classList.remove("drag-over");
    const deviceData = (() => {
      try { return JSON.parse(event.dataTransfer?.getData("application/x-manifold-device") || "null"); } catch { return null; }
    })();
    const paramData = (() => {
      try { return JSON.parse(event.dataTransfer?.getData("application/x-manifold-param") || "null"); } catch { return null; }
    })();
    const rect = container.getBoundingClientRect();
    const x = event.clientX - rect.left - state.canvasPanX;
    const y = event.clientY - rect.top - state.canvasPanY;
    if (deviceData?.targetId) {
      const target = state.targets.get(deviceData.targetId);
      if (!target) return;
      const layoutRoot = target.layout?.root || target.layout || {};
      const rootW = toNumber(layoutRoot.w, 920);
      const rootH = toNumber(layoutRoot.h, 360);
      state.globalSurface.push({
        id: crypto.randomUUID(),
        targetId: target.id,
        path: "/ui/layout",
        widgetType: "layout",
        title: getTargetInstanceName(target),
        x: Math.max(0, x),
        y: Math.max(0, y),
        w: Math.max(320, Math.round(rootW * 0.72)),
        h: Math.max(180, Math.round(rootH * 0.72)),
      });
      renderActiveViews();
    } else if (paramData?.targetId && paramData?.path) {
      const target = state.targets.get(paramData.targetId);
      const endpoint = target?.endpointMap?.get(paramData.path);
      if (target && endpoint) addSurfaceWidget(target, endpoint, Math.max(0, x), Math.max(0, y));
    }
  };
  const clearSelection = () => {
    state.selectedWidgetId = null;
    renderInspector();
    container.querySelectorAll(".canvas-widget.selected").forEach((w) => w.classList.remove("selected"));
  };

  if (!state.targets.size) {
    container.className = "custom-surface empty-state";
    container.textContent = "Connect to an OSCQuery target.";
    return;
  }
  if (!state.globalSurface.length) {
    container.className = "custom-surface empty-state";
    container.textContent = "Drag parameters from the device tree to build a custom control surface.";
    return;
  }

  const surfaceStage = makeElement("div", "custom-surface-stage");
  surfaceStage.style.transform = `translate(${state.canvasPanX}px, ${state.canvasPanY}px)`;
  surfaceStage.addEventListener("pointerdown", (event) => {
    if (!state.editMode) return;
    if (event.target !== surfaceStage) return;
    clearSelection();
    event.preventDefault();
    surfaceStage.setPointerCapture(event.pointerId);
    const startX = event.clientX;
    const startY = event.clientY;
    const startPanX = state.canvasPanX;
    const startPanY = state.canvasPanY;
    const onMove = (moveEvent) => {
      state.canvasPanX = startPanX + (moveEvent.clientX - startX);
      state.canvasPanY = startPanY + (moveEvent.clientY - startY);
      surfaceStage.style.transform = `translate(${state.canvasPanX}px, ${state.canvasPanY}px)`;
    };
    const onUp = () => {
      surfaceStage.removeEventListener("pointermove", onMove);
      surfaceStage.removeEventListener("pointerup", onUp);
      surfaceStage.removeEventListener("pointercancel", onUp);
    };
    surfaceStage.addEventListener("pointermove", onMove);
    surfaceStage.addEventListener("pointerup", onUp);
    surfaceStage.addEventListener("pointercancel", onUp);
  });
  container.append(surfaceStage);

  state.globalSurface.forEach((widget) => {
    const target = getSurfaceWidgetTarget(widget);
    const endpoint = target?.endpointMap?.get(widget.path);
    const isSelected = state.selectedWidgetId === widget.id;
    const isEditing = state.editMode;

    if (widget.widgetType === "layout") {
      if (!target) return;
      const layoutRoot = target.layout?.root || target.layout || {};
      const rootW = toNumber(layoutRoot.w, 920);
      const rootH = toNumber(layoutRoot.h, 360);
      const widgetW = widget.w || Math.max(320, Math.round(rootW * 0.72));
      const widgetH = widget.h || Math.max(180, Math.round(rootH * 0.72));
      const scale = Math.min(widgetW / Math.max(1, rootW), widgetH / Math.max(1, rootH)) || 1;
      const scaledW = Math.max(1, Math.round(rootW * scale));
      const scaledH = Math.max(1, Math.round(rootH * scale));

      const el = makeElement("div", `canvas-widget canvas-layout${isSelected && isEditing ? " selected" : ""}${isEditing ? " editable" : ""}`);
      el.style.left = `${widget.x || 0}px`;
      el.style.top = `${widget.y || 0}px`;
      el.style.width = `${scaledW}px`;
      el.style.height = `${scaledH}px`;
      el.style.overflow = "hidden";

      const layoutShell = makeElement("div", "canvas-layout-content");
      layoutShell.style.width = `${scaledW}px`;
      layoutShell.style.height = `${scaledH}px`;
      const stage = makeElement("div", "layout-stage");
      stage.style.width = `${rootW}px`;
      stage.style.height = `${rootH}px`;
      stage.style.transform = `scale(${scale})`;
      stage.style.transformOrigin = "top left";
      layoutShell.append(stage);
      const applyLayoutSize = (nextW, nextH) => {
        const nextScale = Math.min(nextW / Math.max(1, rootW), nextH / Math.max(1, rootH)) || 1;
        const nextScaledW = Math.max(1, Math.round(rootW * nextScale));
        const nextScaledH = Math.max(1, Math.round(rootH * nextScale));
        el.style.width = `${nextScaledW}px`;
        el.style.height = `${nextScaledH}px`;
        layoutShell.style.width = `${nextScaledW}px`;
        layoutShell.style.height = `${nextScaledH}px`;
        stage.style.transform = `scale(${nextScale})`;
      };

      if (target.layout) {
        renderLayoutNode(target, layoutRoot, stage, {});
      }
      el.append(layoutShell);

      if (isEditing) {
        attachCanvasResizeHandle(el, widget, {
          minW: 180,
          minH: 100,
          onResize: applyLayoutSize,
        });
        el.addEventListener("pointerdown", (event) => {
          event.preventDefault();
          event.stopPropagation();
          state.selectedWidgetId = widget.id;
          renderInspector();
          container.querySelectorAll(".canvas-widget.selected").forEach((w) => w.classList.remove("selected"));
          el.classList.add("selected");
          el.setPointerCapture(event.pointerId);
          const startX = event.clientX;
          const startY = event.clientY;
          const origLeft = widget.x || 0;
          const origTop = widget.y || 0;
          const onMove = (moveEvent) => {
            widget.x = Math.max(0, origLeft + moveEvent.clientX - startX);
            widget.y = Math.max(0, origTop + moveEvent.clientY - startY);
            el.style.left = `${widget.x}px`;
            el.style.top = `${widget.y}px`;
          };
          const onUp = () => {
            el.removeEventListener("pointermove", onMove);
            el.removeEventListener("pointerup", onUp);
            el.removeEventListener("pointercancel", onUp);
          };
          el.addEventListener("pointermove", onMove);
          el.addEventListener("pointerup", onUp);
          el.addEventListener("pointercancel", onUp);
        });
      }

      surfaceStage.append(el);
      return;
    }

    if (!target || !endpoint) return;

    const el = makeElement("div", `canvas-widget${isSelected && isEditing ? " selected" : ""}${isEditing ? " editable" : ""}`);
    el.style.left = `${widget.x || 0}px`;
    el.style.top = `${widget.y || 0}px`;
    el.style.width = `${widget.w || 220}px`;
    el.style.height = `${widget.h || 60}px`;

    const body = makeElement("div", "canvas-widget-body");
    body.style.height = "100%";
    const control = buildControl(target, { ...endpoint, label: widget.title || resolveDisplayLabel(target, endpoint) }, widget.widgetType, {
      showPath: false,
      xyYPath: widget.yPath,
      xyYTargetId: widget.yTargetId,
    });
    if (control) body.append(control);
    el.append(body);

    if (isEditing) {
      attachCanvasResizeHandle(el, widget, {
        minW: 100,
        minH: 40,
        onResize: (nextW, nextH) => {
          el.style.width = `${nextW}px`;
          el.style.height = `${nextH}px`;
        },
      });
      el.addEventListener("pointerdown", (event) => {
        event.preventDefault();
        event.stopPropagation();
        state.selectedWidgetId = widget.id;
        renderInspector();
        container.querySelectorAll(".canvas-widget.selected").forEach((w) => w.classList.remove("selected"));
        el.classList.add("selected");
        el.setPointerCapture(event.pointerId);
        const startX = event.clientX;
        const startY = event.clientY;
        const origLeft = widget.x || 0;
        const origTop = widget.y || 0;
        const onMove = (moveEvent) => {
          widget.x = Math.max(0, origLeft + moveEvent.clientX - startX);
          widget.y = Math.max(0, origTop + moveEvent.clientY - startY);
          el.style.left = `${widget.x}px`;
          el.style.top = `${widget.y}px`;
        };
        const onUp = () => {
          el.removeEventListener("pointermove", onMove);
          el.removeEventListener("pointerup", onUp);
          el.removeEventListener("pointercancel", onUp);
        };
        el.addEventListener("pointermove", onMove);
        el.addEventListener("pointerup", onUp);
        el.addEventListener("pointercancel", onUp);
      });
    }

    surfaceStage.append(el);
  });
}

function renderInspector() {
  const container = dom.inspectorContent;
  container.innerHTML = "";
  if (!state.selectedWidgetId) {
    container.textContent = "Select a widget on the canvas.";
    return;
  }
  const widget = state.globalSurface.find((w) => w.id === state.selectedWidgetId);
  if (!widget) {
    container.textContent = "Select a widget on the canvas.";
    return;
  }
  const target = getSurfaceWidgetTarget(widget);
  const endpoint = target?.endpointMap?.get(widget.path);

  // Delete button at top
  const deleteRow = makeElement("div", "inspector-row");
  deleteRow.style.justifyContent = "flex-end";
  const deleteBtn = makeElement("button", "danger", "Delete Widget");
  deleteBtn.addEventListener("click", () => {
    removeSurfaceWidget(target, widget.id);
  });
  deleteRow.append(deleteBtn);

  const titleField = makeElement("div", "inspector-field");
  titleField.append(makeElement("label", "", "Title"));
  const titleInput = document.createElement("input");
  titleInput.type = "text";
  titleInput.value = widget.title || "";
  titleInput.addEventListener("change", () => {
    widget.title = titleInput.value.trim() || (endpoint ? resolveDisplayLabel(target, endpoint) : widget.path);
    renderCustomSurface();
  });
  titleField.append(titleInput);

  const typeField = makeElement("div", "inspector-field");
  typeField.append(makeElement("label", "", "Widget Type"));
  const typeSelect = document.createElement("select");
  for (const t of ["slider", "slider-int", "choice", "toggle", "readout", "xy-x", "layout"]) {
    const opt = document.createElement("option");
    opt.value = t;
    opt.textContent = t === "xy-x" ? "xy" : t === "choice" ? "dropdown" : t;
    if (widget.widgetType === t) opt.selected = true;
    typeSelect.append(opt);
  }
  typeSelect.addEventListener("change", () => {
    widget.widgetType = typeSelect.value;
    renderCustomSurface();
  });
  typeField.append(typeSelect);

  const widthField = makeElement("div", "inspector-field");
  widthField.append(makeElement("label", "", "Width"));
  const widthInput = document.createElement("input");
  widthInput.type = "number";
  widthInput.value = String(widget.w || 220);
  widthInput.min = "60";
  widthInput.max = "1200";
  widthInput.step = "10";
  widthInput.addEventListener("change", () => {
    widget.w = clamp(Number(widthInput.value) || 220, 60, 1200);
    renderCustomSurface();
  });
  widthField.append(widthInput);

  const heightField = makeElement("div", "inspector-field");
  heightField.append(makeElement("label", "", "Height"));
  const heightInput = document.createElement("input");
  heightInput.type = "number";
  heightInput.value = String(widget.h || 60);
  heightInput.min = "30";
  heightInput.max = "800";
  heightInput.step = "10";
  heightInput.addEventListener("change", () => {
    widget.h = clamp(Number(heightInput.value) || 60, 30, 800);
    renderCustomSurface();
  });
  heightField.append(heightInput);

  const posRow = makeElement("div", "inspector-row");
  const xField = makeElement("div", "inspector-field");
  xField.style.flex = "1";
  xField.append(makeElement("label", "", "X"));
  const xInput = document.createElement("input");
  xInput.type = "number";
  xInput.value = String(widget.x || 0);
  xInput.addEventListener("change", () => {
    widget.x = Math.max(0, Number(xInput.value) || 0);
    renderCustomSurface();
  });
  xField.append(xInput);
  const yField = makeElement("div", "inspector-field");
  yField.style.flex = "1";
  yField.append(makeElement("label", "", "Y"));
  const yInput = document.createElement("input");
  yInput.type = "number";
  yInput.value = String(widget.y || 0);
  yInput.addEventListener("change", () => {
    widget.y = Math.max(0, Number(yInput.value) || 0);
    renderCustomSurface();
  });
  yField.append(yInput);
  posRow.append(xField, yField);

  const pathField = makeElement("div", "inspector-field");
  pathField.append(makeElement("label", "", "Path"));
  const pathDisplay = makeElement("div", "");
  pathDisplay.style.fontSize = "0.78rem";
  pathDisplay.style.color = "var(--muted)";
  pathDisplay.style.wordBreak = "break-all";
  pathDisplay.textContent = widget.path;
  pathField.append(pathDisplay);

  const fields = [deleteRow, titleField, typeField, widthField, heightField, posRow];

  if (widget.widgetType === "xy-x") {
    const xyField = makeElement("div", "inspector-field");
    xyField.append(makeElement("label", "", "Y Parameter"));
    const currentYTarget = state.targets.get(widget.yTargetId) || target || null;
    const currentYEndpoint = currentYTarget?.endpointMap?.get(widget.yPath) || null;
    const dropZone = makeElement(
      "div",
      "inspector-dropzone",
      currentYEndpoint
        ? `${currentYTarget ? getTargetInstanceName(currentYTarget) : "Unknown"} • ${resolveDisplayLabel(currentYTarget || target, currentYEndpoint)}`
        : "Drop parameter here from the tree"
    );
    dropZone.title = widget.yPath || "";
    dropZone.addEventListener("dragover", (event) => {
      if (!state.editMode) return;
      if (event.dataTransfer?.types?.includes("application/x-manifold-param")) {
        event.preventDefault();
        dropZone.classList.add("drag-over");
      }
    });
    dropZone.addEventListener("dragleave", () => dropZone.classList.remove("drag-over"));
    dropZone.addEventListener("drop", (event) => {
      event.preventDefault();
      dropZone.classList.remove("drag-over");
      try {
        const data = JSON.parse(event.dataTransfer?.getData("application/x-manifold-param") || "null");
        if (!data?.targetId || !data?.path) return;
        widget.yTargetId = data.targetId;
        widget.yPath = data.path;
        renderInspector();
        renderCustomSurface();
      } catch (error) {
        console.warn("failed to bind xy y parameter", error);
      }
    });
    const xyActions = makeElement("div", "inspector-row");
    const resetBtn = makeElement("button", "secondary", "Use paired Y");
    resetBtn.addEventListener("click", () => {
      const pairedY = widget.path.endsWith("/x")
        ? widget.path.replace(/\/x$/, "/y")
        : widget.path.endsWith("/mix_x")
          ? widget.path.replace(/\/mix_x$/, "/mix_y")
          : null;
      widget.yTargetId = pairedY ? widget.targetId : null;
      widget.yPath = pairedY;
      renderInspector();
      renderCustomSurface();
    });
    const clearBtn = makeElement("button", "secondary", "Clear Y");
    clearBtn.addEventListener("click", () => {
      widget.yTargetId = null;
      widget.yPath = null;
      renderInspector();
      renderCustomSurface();
    });
    xyActions.append(resetBtn, clearBtn);
    xyField.append(dropZone, xyActions);
    fields.push(xyField);
  }

  if (target) {
    const targetField = makeElement("div", "inspector-field");
    targetField.append(makeElement("label", "", "Device"));
    targetField.append(makeElement("div", "badge", getTargetInstanceName(target)));
    fields.push(targetField);
  }

  fields.push(pathField);

  if (endpoint && hasRange(endpoint)) {
    const rangeField = makeElement("div", "inspector-field");
    rangeField.append(makeElement("label", "", "Range"));
    const { min, max } = getRange(endpoint);
    rangeField.append(makeElement("div", "badge", `${formatValue(min)} → ${formatValue(max)}`));
    fields.push(rangeField);
  }

  if (endpoint) {
    const typeInfo = makeElement("div", "inspector-field");
    typeInfo.append(makeElement("label", "", "OSC Type"));
    typeInfo.append(makeElement("div", "badge", endpoint.type || "?"));
    fields.push(typeInfo);
  }

  const currentVal = endpoint ? target.values.get(widget.path) : undefined;
  if (currentVal !== undefined) {
    const valField = makeElement("div", "inspector-field");
    valField.append(makeElement("label", "", "Current Value"));
    valField.append(makeElement("div", "", formatEndpointValue(endpoint || {}, currentVal)));
    fields.push(valField);
  }

  container.append(...fields);
}

function preserveCustomViewportDuring(updateFn) {
  const target = activeTarget();
  const isCustom = target?.activeTab === "custom";
  const before = isCustom ? dom.customSurface?.getBoundingClientRect() : null;
  updateFn();
  if (!before || !isCustom) return;
  requestAnimationFrame(() => {
    const after = dom.customSurface?.getBoundingClientRect();
    if (!after) return;
    state.canvasPanX += before.left - after.left;
    state.canvasPanY += before.top - after.top;
    renderCustomSurface();
    renderInspector();
  });
}

function syncTabUi(target) {
  const isCustom = target?.activeTab === "custom";
  const showCustomPanels = isCustom && state.editMode;
  dom.tabButtons.forEach((button) => button.classList.toggle("active", button.dataset.tab === target?.activeTab));
  Object.entries(dom.tabPanels).forEach(([id, panel]) => panel.classList.toggle("active", id === target?.activeTab));
  dom.parameterSidebar.style.display = "none";
  dom.deviceTreeSidebar.style.display = showCustomPanels && !state.treePanelCollapsed ? "" : "none";
  dom.inspectorPanel.style.display = showCustomPanels && !state.inspectorPanelCollapsed ? "" : "none";
  dom.workspace.classList.toggle("custom-mode", isCustom);
  dom.workspace.classList.toggle("custom-tree-collapsed", isCustom && (!state.editMode || state.treePanelCollapsed));
  dom.workspace.classList.toggle("custom-inspector-collapsed", isCustom && (!state.editMode || state.inspectorPanelCollapsed));
  if (dom.treePanelToggle) {
    dom.treePanelToggle.style.display = isCustom ? "" : "none";
    dom.treePanelToggle.textContent = state.treePanelCollapsed || !state.editMode ? "Show Tree" : "Hide Tree";
    dom.treePanelToggle.classList.toggle("secondary", true);
  }
  if (dom.inspectorPanelToggle) {
    dom.inspectorPanelToggle.style.display = isCustom ? "" : "none";
    dom.inspectorPanelToggle.textContent = state.inspectorPanelCollapsed || !state.editMode ? "Show Inspector" : "Hide Inspector";
    dom.inspectorPanelToggle.classList.toggle("secondary", true);
  }
  if (dom.editModeToggle) {
    dom.editModeToggle.textContent = state.editMode ? "Editing" : "Playing";
  }
  if (isCustom) renderDeviceTree();
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
  renderInspector();
  if (target?.activeTab === "custom") renderDeviceTree();
  if (target?.activeTab === "layout") renderLoadedLayout();
  else if (!target) renderLoadedLayout();
}

function setActiveTab(tabId) {
  const target = activeTarget();
  if (!target) return;
  target.activeTab = tabId;
  syncTabUi(target);
  if (tabId === "layout") renderLoadedLayout();
  if (tabId === "custom") { renderDeviceTree(); renderCustomSurface(); renderInspector(); }
  if (tabId === "generic") renderGenericGroups();
}

async function syncDiscoveredTargets() {
  try {
    const data = await fetchJson(DISCOVERY_ENDPOINT);
    const seen = new Set<string>();
    const targets = Array.isArray(data?.targets) ? data.targets : [];

    for (const item of targets) {
      const host = String(item?.host || "127.0.0.1").trim() || "127.0.0.1";
      const port = clamp(toNumber(item?.queryPort, NaN), 1, 65535);
      if (!Number.isFinite(port)) continue;
      const id = targetId(host, port);
      seen.add(id);
      await connectTarget(host, port, {
        activate: false,
        remember: false,
        discovered: true,
        lastSeenMs: toNumber(item?.lastSeenMs, 0),
      });
      const target = state.targets.get(id);
      if (target) {
        target.discovered = true;
        target.lastSeenMs = toNumber(item?.lastSeenMs, target.lastSeenMs || 0);
      }
    }

    Array.from(state.targets.values()).forEach((target) => {
      if (target.discovered && !seen.has(target.id)) {
        disconnectTarget(target.id);
      }
    });
  } catch (error) {
    console.warn("discovery sync failed", error);
  }
}

function startDiscoveryPolling() {
  if (state.discoveryPollTimer) clearInterval(state.discoveryPollTimer as number);
  void syncDiscoveredTargets();
  state.discoveryPollTimer = setInterval(() => {
    void syncDiscoveredTargets();
  }, DISCOVERY_POLL_MS);
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

  dom.deviceTreeSearch?.addEventListener("input", () => {
    renderDeviceTree();
  });

  dom.reloadLayoutButton.addEventListener("click", () => {
    const target = activeTarget();
    if (!target) return;
    void loadLayout(target, false);
  });

  dom.saveSurfaceButton.addEventListener("click", () => {
    saveGlobalSurface();
  });

  dom.clearSurfaceButton.addEventListener("click", () => {
    state.globalSurface = [];
    state.selectedWidgetId = null;
    renderCustomSurface();
    renderInspector();
  });

  if (dom.treePanelToggle) {
    dom.treePanelToggle.addEventListener("click", () => {
      preserveCustomViewportDuring(() => {
        state.treePanelCollapsed = !state.treePanelCollapsed;
        syncTabUi(activeTarget() || { activeTab: "custom" });
      });
    });
  }

  if (dom.inspectorPanelToggle) {
    dom.inspectorPanelToggle.addEventListener("click", () => {
      preserveCustomViewportDuring(() => {
        state.inspectorPanelCollapsed = !state.inspectorPanelCollapsed;
        syncTabUi(activeTarget() || { activeTab: "custom" });
      });
    });
  }

  if (dom.editModeToggle) {
    dom.editModeToggle.addEventListener("click", () => {
      preserveCustomViewportDuring(() => {
        state.editMode = !state.editMode;
        if (!state.editMode) state.selectedWidgetId = null;
        syncTabUi(activeTarget() || { activeTab: "custom" });
        renderCustomSurface();
        renderInspector();
      });
    });
  }

  dom.tabButtons.forEach((button) => {
    button.addEventListener("click", () => setActiveTab(button.dataset.tab));
  });

  window.addEventListener("beforeunload", () => {
    if (state.discoveryPollTimer) clearInterval(state.discoveryPollTimer as number);
    Array.from(state.targets.values()).forEach((target) => closeSocket(target));
  });
}

function init() {
  loadSavedConnection();
  loadGlobalSurface();
  dom.hostInput.value = state.lastHost;
  dom.portInput.value = String(state.lastPort);
  bindEvents();
  renderTargetNav();
  renderActiveViews();
  startDiscoveryPolling();
}

init();
