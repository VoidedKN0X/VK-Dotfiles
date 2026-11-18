const { exec } = require("child_process");

function run(cmd, callback) {
  exec(cmd, (err, stdout) => {
    if (err) console.error(`pipewire cmd error: ${cmd}`, err.message);
    if (callback) callback(err, stdout);
  });
}

// Convert "+5%" / "-5%" to wpctl format "5%+" / "5%-"
function toWpctlVol(change) {
  const match = change.match(/^([+-])(.+)$/);
  if (match) return `${match[2]}${match[1]}`;
  return change;
}

// Get volume and mute status for a target (sink/source/node id).
// Concurrent calls for the same target are queued and share a single wpctl execution.
const volumeQueue = new Map();

function getVolume(target, callback) {
  if (volumeQueue.has(target)) {
    volumeQueue.get(target).push(callback);
    return;
  }

  volumeQueue.set(target, [callback]);

  exec(`wpctl get-volume ${target}`, (err, stdout) => {
    const callbacks = volumeQueue.get(target);
    volumeQueue.delete(target);

    if (err || !stdout) {
      for (const cb of callbacks) cb(null);
      return;
    }

    const volumeMatch = stdout.match(/Volume:\s([0-9.]+)/);
    const muteMatch = stdout.includes("[MUTED]");

    if (!volumeMatch) {
      for (const cb of callbacks) cb(null);
      return;
    }

    const result = { percent: Math.round(parseFloat(volumeMatch[1]) * 100), muted: muteMatch };
    for (const cb of callbacks) cb(result);
  });
}

// --- Volume and mute control ---
function nodeVolume(id, change, callback) {
  if (!id) return;
  const vol = toWpctlVol(change);
  const limit = change.startsWith("+") ? " -l 1.0" : "";
  run(`wpctl set-volume ${id} ${vol}${limit}`, callback);
}

function nodeMute(id, callback) {
  if (!id) return;
  run(`wpctl set-mute ${id} toggle`, callback);
}

// Set mute to a specific state (true = muted, false = unmuted)
function nodeMuteSet(id, muted, callback) {
  if (!id) return;
  run(`wpctl set-mute ${id} ${muted ? 1 : 0}`, callback);
}

// --- pw-dump based enumeration ---

// Shared helper: parse pw-dump once, extract app streams, sinks, and sources.
// Concurrent calls are queued and share a single pw-dump execution.
let pwDumpQueue = null;

function parsePwDump(callback) {
  if (pwDumpQueue) {
    pwDumpQueue.push(callback);
    return;
  }

  pwDumpQueue = [callback];

  exec("pw-dump", { maxBuffer: 25000000 }, (err, stdout) => {
    const queue = pwDumpQueue;
    pwDumpQueue = null;

    if (err) {
      for (const cb of queue) cb([], [], []);
      return;
    }

    try {
      const jsonStart = stdout.indexOf("[");
      if (jsonStart === -1) throw new Error("No JSON array found in pw-dump output");
      // Walk forward from the opening bracket to find the matching closing bracket,
      // correctly handling nested arrays/objects and strings with escaped characters.
      // This is robust against any trailing non-JSON content, even if it contains ']'.
      let depth = 0, inString = false, escape = false, jsonEnd = -1;
      for (let i = jsonStart; i < stdout.length; i++) {
        const c = stdout[i];
        if (escape) { escape = false; continue; }
        if (inString) { if (c === "\\") escape = true; else if (c === '"') inString = false; continue; }
        if (c === '"') { inString = true; continue; }
        if (c === "[" || c === "{") depth++;
        else if (c === "]" || c === "}") { if (--depth === 0) { jsonEnd = i; break; } }
      }
      if (jsonEnd === -1) throw new Error("No JSON array found in pw-dump output");
      const nodes = JSON.parse(stdout.slice(jsonStart, jsonEnd + 1));
      const apps = [];
      const sinks = [];
      const sources = [];

      for (const node of nodes) {
        if (node.type !== "PipeWire:Interface:Node" || !node.info || !node.info.props) continue;
        const props = node.info.props;
        const mediaClass = props["media.class"];

        if (mediaClass === "Stream/Output/Audio") {
          apps.push({
            id: node.id,
            name: props["application.name"] || props["node.name"] || `Node ${node.id}`,
            appName: props["application.name"] || null,
          });
        } else if (mediaClass === "Audio/Sink") {
          sinks.push({
            id: node.id,
            name: props["node.nick"] || props["node.description"] || props["node.name"] || `Node ${node.id}`,
            nodeName: props["node.name"],
          });
        } else if (mediaClass === "Audio/Source") {
          sources.push({
            id: node.id,
            name: props["node.nick"] || props["node.description"] || props["node.name"] || `Node ${node.id}`,
            nodeName: props["node.name"],
          });
        }
      }

      for (const cb of queue) cb(apps, sinks, sources);
    } catch (e) {
      console.error("Failed to parse pw-dump output:", e.message);
      for (const cb of queue) cb([], [], []);
    }
  });
}

function getAppList(callback) {
  parsePwDump((apps) => callback(apps));
}

function getSinkList(callback) {
  parsePwDump((apps, sinks) => callback(sinks));
}

function getSourceList(callback) {
  parsePwDump((apps, sinks, sources) => callback(sources));
}

// Get app, sink, and source lists in one pw-dump call
function getLists(callback) {
  parsePwDump(callback);
}

// Resolve a stable node.name to the current numeric ID (for sinks)
function resolveNodeId(nodeName, callback) {
  parsePwDump((apps, sinks) => {
    const match = sinks.find((s) => s.nodeName === nodeName);
    callback(match ? match.id : null);
  });
}

// Resolve a stable application.name to all current matching node IDs (for app streams)
function resolveAppIds(appName, callback) {
  parsePwDump((apps) => {
    const ids = apps.filter((a) => a.appName === appName).map((a) => a.id);
    callback(ids);
  });
}

// Resolve a stable node.name to the current numeric ID (for sources)
function resolveSourceId(nodeName, callback) {
  parsePwDump((apps, sinks, sources) => {
    const match = sources.find((s) => s.nodeName === nodeName);
    callback(match ? match.id : null);
  });
}

// Set a node as the default device
function setDefault(id, callback) {
  if (!id) return;
  run(`wpctl set-default ${id}`, callback);
}

// --- wpctl inspect based lookups ---

// Inspect a node and extract multiple properties in one call.
// Concurrent calls for the same target are queued and share a single wpctl execution.
const inspectQueue = new Map();

function inspectNode(target, callback) {
  if (inspectQueue.has(target)) {
    inspectQueue.get(target).push(callback);
    return;
  }

  inspectQueue.set(target, [callback]);

  exec(`wpctl inspect ${target}`, (err, stdout) => {
    const callbacks = inspectQueue.get(target);
    inspectQueue.delete(target);

    if (err || !stdout) {
      for (const cb of callbacks) cb(null);
      return;
    }

    const nodeName = stdout.match(/node\.name\s*=\s*"(.+?)"/);
    const nick = stdout.match(/node\.nick\s*=\s*"(.+?)"/);
    const desc = stdout.match(/node\.description\s*=\s*"(.+?)"/);
    const appName = stdout.match(/application\.name\s*=\s*"(.+?)"/);

    const result = {
      stableName: nodeName ? nodeName[1] : null,
      displayName: (nick && nick[1]) || (desc && desc[1]) || null,
      appName: (appName && appName[1]) || (nodeName && nodeName[1]) || null,
    };
    for (const cb of callbacks) cb(result);
  });
}

// Get short display name for a physical device (sink/source)
function getNodeName(target, callback) {
  inspectNode(target, (info) => {
    callback(info ? info.displayName : null);
  });
}

// Get application name for a stream node
function getAppName(target, callback) {
  inspectNode(target, (info) => {
    callback(info ? info.appName : null);
  });
}

module.exports = {
  getVolume,
  inspectNode,
  getNodeName,
  getAppName,
  resolveNodeId,
  resolveSourceId,
  resolveAppIds,
  setDefault,
  nodeVolume,
  nodeMute,
  nodeMuteSet,
  getAppList,
  getSinkList,
  getSourceList,
  getLists,
};
