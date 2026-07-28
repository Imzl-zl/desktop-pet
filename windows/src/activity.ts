// Whimsical activity vocabulary , a 1:1 port of the macOS app's
// ClaudeActivityFormatter (5 themes, per-tool phrase pools, file-type hints,
// rotating pick per key). Phrases are intentionally English, like macOS.

export type ActivityThemeName = "chef" | "engineer" | "wizard" | "explorer" | "scientist";

interface ThemePools {
  reading: string[];
  writing: string[];
  running: string[];
  searching: string[];
  delegating: string[];
  thinking: string[];
  done: string[];
  waiting: string[];
  skill: string[];
  generic: string[];
}

export const ACTIVITY_THEMES: Record<ActivityThemeName, ThemePools> = {
  chef: {
    reading: ["Perusing…", "Leafing through…", "Absorbing…", "Studying…", "Browsing…"],
    writing: ["Cooking…", "Baking…", "Crafting…", "Whittling…", "Sculpting…", "Stitching…"],
    running: ["Brewing…", "Simmering…", "Stirring the pot…", "Running the numbers…"],
    searching: ["Foraging…", "Scouting…", "Hunting…", "Exploring…", "Investigating…"],
    delegating: ["Delegating…", "Hatching a plan…", "Spawning help…", "Rounding up agents…"],
    thinking: ["Photosynthesizing…", "Sprouting…", "Planning…", "Pondering…", "Germinating…", "Marinating…", "Noodling…"],
    done: ["All done!", "Wrapped up!", "Delivered!", "Finished!", "Mission complete!"],
    waiting: ["Awaiting instructions…", "Standing by…", "Listening…"],
    skill: ["Consulting the recipe…", "Checking the cookbook…", "Following the method…"],
    generic: ["Working…", "Tinkering…", "Doing the thing…"],
  },
  engineer: {
    reading: ["Inspecting…", "Reviewing…", "Parsing…", "Auditing…", "Loading…"],
    writing: ["Refactoring…", "Implementing…", "Patching…", "Scaffolding…", "Committing…"],
    running: ["Compiling…", "Building…", "Executing…", "Deploying…", "Running the pipeline…"],
    searching: ["Scanning…", "Grepping…", "Indexing…", "Tracing…", "Profiling…"],
    delegating: ["Spawning a process…", "Forking…", "Dispatching…", "Queueing a job…"],
    thinking: ["Architecting…", "Designing…", "Calculating…", "Debugging…", "Optimizing…"],
    done: ["Build complete!", "Shipped!", "Merged!", "All green!", "Tests passing!"],
    waiting: ["Awaiting input…", "Blocked on dependency…", "Polling…"],
    skill: ["Reading the manual…", "Checking the docs…", "Loading the module…"],
    generic: ["Processing…", "Running…", "Executing…"],
  },
  wizard: {
    reading: ["Studying the scrolls…", "Deciphering…", "Consulting the tome…", "Peering within…"],
    writing: ["Inscribing…", "Enchanting…", "Weaving a spell…", "Scribing…"],
    running: ["Casting…", "Invoking…", "Summoning…", "Channeling magic…"],
    searching: ["Divining…", "Scrying…", "Seeking…", "Gazing into the orb…"],
    delegating: ["Calling forth…", "Summoning a familiar…", "Conjuring help…"],
    thinking: ["Meditating…", "Pondering the arcane…", "Consulting the stars…", "Prophesying…"],
    done: ["The spell is cast!", "It is done!", "Magic complete!", "Quest fulfilled!"],
    waiting: ["Awaiting the omens…", "The stars are aligning…", "Patience, young apprentice…"],
    skill: ["Consulting the scrolls…", "Channeling a skill…", "Reading the grimoire…"],
    generic: ["Weaving…", "Working the magic…", "At work…"],
  },
  explorer: {
    reading: ["Surveying…", "Mapping the terrain…", "Examining the site…", "Charting…"],
    writing: ["Logging the expedition…", "Marking the map…", "Recording findings…", "Documenting…"],
    running: ["Blazing a trail…", "Trekking…", "Venturing forth…", "Pushing on…"],
    searching: ["Scouting ahead…", "Seeking passage…", "Exploring…", "Reconnoitering…"],
    delegating: ["Sending a scout…", "Dispatching a guide…", "Rallying the crew…"],
    thinking: ["Plotting a course…", "Reading the stars…", "Studying the map…", "Planning the route…"],
    done: ["Base camp reached!", "Trail blazed!", "Discovery made!", "Expedition complete!"],
    waiting: ["Awaiting the tide…", "Resting at camp…", "Holding position…"],
    skill: ["Consulting the guide…", "Reading the field notes…", "Checking the compass…"],
    generic: ["Moving forward…", "Pressing on…", "On the trail…"],
  },
  scientist: {
    reading: ["Observing…", "Reviewing the data…", "Analyzing the sample…", "Examining…"],
    writing: ["Synthesizing…", "Documenting findings…", "Writing the report…", "Formulating…"],
    running: ["Running the experiment…", "Executing the protocol…", "Testing the hypothesis…", "Processing…"],
    searching: ["Scanning the dataset…", "Cross-referencing…", "Searching for patterns…", "Correlating…"],
    delegating: ["Assigning to the lab…", "Tasking the team…", "Delegating to an assistant…"],
    thinking: ["Hypothesizing…", "Theorizing…", "Modeling…", "Calculating…", "Reasoning…"],
    done: ["Hypothesis confirmed!", "Results in!", "Experiment complete!", "Published!"],
    waiting: ["Awaiting results…", "Incubating…", "Waiting for the reaction…"],
    skill: ["Consulting the protocol…", "Reviewing the literature…", "Checking the procedure…"],
    generic: ["Analyzing…", "Processing…", "At work…"],
  },
};

export function currentTheme(): ThemePools {
  const name = (localStorage.getItem("ap_theme_phrases") || "chef") as ActivityThemeName;
  return ACTIVITY_THEMES[name] ?? ACTIVITY_THEMES.chef;
}

// Rotating pick per key, like the macOS formatter's callCounts.
const callCounts = new Map<string, number>();
function pick(phrases: string[], key: string): string {
  if (!phrases.length) return "Working…";
  const n = ((callCounts.get(key) ?? 0) + 1) % phrases.length;
  callCounts.set(key, n);
  return phrases[n];
}

/// File-type hints that beat the generic tool pools (port of extensionHint).
function extensionHint(tool: string, filePath: string | undefined): string | null {
  if (!filePath) return null;
  const lower = filePath.toLowerCase();
  const isTest = lower.includes("tests/") || lower.endsWith("tests.swift") || lower.endsWith("test.swift")
    || lower.includes("__tests__") || /\.(test|spec)\.[jt]sx?$/.test(lower);
  const isDoc = lower.endsWith(".md") || lower.endsWith(".txt") || lower.endsWith(".rst");
  const isCfg = lower.endsWith(".json") || lower.endsWith(".yaml") || lower.endsWith(".yml")
    || lower.endsWith(".plist") || lower.endsWith(".toml");
  const isRead = tool === "Read";
  const isWrite = tool === "Edit" || tool === "Write" || tool === "MultiEdit";
  if (isTest && isRead) return "Reviewing tests…";
  if (isTest && isWrite) return "Refining tests…";
  if (isDoc && isRead) return "Reading the docs…";
  if (isDoc && isWrite) return "Updating the docs…";
  if (isCfg && isRead) return "Parsing config…";
  if (isCfg && isWrite) return "Adjusting config…";
  return null;
}

function toolActivity(tool: string, filePath?: string): string | null {
  if (!tool) return null;
  const hint = extensionHint(tool, filePath);
  if (hint) return hint;
  const t = currentTheme();
  let pool: string[];
  switch (tool) {
    case "Read": pool = t.reading; break;
    case "Edit": case "Write": case "MultiEdit": pool = t.writing; break;
    case "Bash": pool = t.running; break;
    case "Glob": case "Grep": case "WebSearch": case "WebFetch": pool = t.searching; break;
    case "Agent": case "Task": pool = t.delegating; break;
    case "Skill": pool = t.skill; break;
    default: pool = t.generic;
  }
  return pick(pool, tool);
}

/// Live activity line from a hook event (port of activityMessage).
export function activityMessage(
  event: string, tool: string, filePath: string | undefined, explicit: string | undefined,
): string | null {
  const trimmed = explicit?.trim() || null;
  if (event === "Notification") return trimmed;
  if (event === "UserPromptSubmit") return pick(currentTheme().thinking, event);
  if (event === "PreToolUse" || event === "PostToolUse") return toolActivity(tool, filePath);
  if (tool) return toolActivity(tool, filePath);
  return trimmed;
}

/// Themed fallback for a state with no live activity (port of stateMessage).
export function stateMessage(state: string): string | null {
  const t = currentTheme();
  if (state === "done") return pick(t.done, "state.done");
  if (state === "waiting") return pick(t.waiting, "state.waiting");
  return null;
}

// ---- Built-in bubble message pools (port of PetChat / IdleBoost / defaults) --

export const PET_CHAT: Record<string, string[]> = {
  working: [
    "Thinking…", "Working on it…", "On it!", "Crunching code…",
    "Hmm, let me see…", "Cooking something up…", "Deep in thought…",
    "Brain go brrr…", "Almost there…", "Wiring it up…",
  ],
  waiting: ["Waiting for your input", "Your turn — over to you", "Needs your input"],
  done: [
    "All done!", "Finished!", "Ta-da!", "Done and dusted!",
    "Nailed it!", "That's a wrap!", "Mission complete!",
  ],
  celebrate: ["Woohoo!", "We did it!", "Victory!", "Yesss!", "High five!", "Champion!"],
};

export const IDLE_BOOST = [
  "Let's grill some bugs.",
  "I miss you. Open a branch for me.",
  "Tiny commit, tiny dopamine.",
  "The build is quiet. Too quiet.",
  "Ship something small. Future you is watching.",
  "Your TODOs are pretending not to see us.",
  "No agents running. The keyboard has entered standby drama.",
  "Turn coffee into code. Carefully.",
  "Open one file. Intimidate it professionally.",
  "The repo is calm. Suspicious, but calm.",
  "Refactor lightly. Leave with dignity.",
  "One clean diff can fix the whole afternoon.",
];

/// Default editable lines per mood (port of BubbleMessages.defaultLines).
export function defaultLines(mood: string): string[] {
  switch (mood) {
    case "waiting": return PET_CHAT.waiting;
    case "done": return PET_CHAT.done;
    case "celebrate": return PET_CHAT.celebrate;
    case "idle": return IDLE_BOOST;
    default: return []; // working: blank = live activity wins
  }
}

/// Effective custom/system lines for (agent kind, mood) , port of
/// BubbleMessages.lines. Keys: ap_msg_src, ap_msg_<agent|all>_<mood>.
export function bubbleLines(kind: string | null, mood: string): string[] {
  if ((localStorage.getItem("ap_msg_src") || "system") === "system") return defaultLines(mood);
  const read = (key: string): string[] | null => {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const lines = raw.split("\n").map((s) => s.trim()).filter(Boolean);
    return lines.length ? lines : null;
  };
  if (kind) { const v = read(`ap_msg_${kind}_${mood}`); if (v) return v; }
  const all = read(`ap_msg_all_${mood}`);
  return all ?? defaultLines(mood);
}

/// A stable line seeded by session id (djb2), like the macOS app.
export function bubbleLine(kind: string | null, mood: string, seed: string): string {
  const pool = bubbleLines(kind, mood);
  if (!pool.length) return "";
  let h = 5381;
  for (const c of seed) h = (Math.imul(h, 33) + c.charCodeAt(0)) | 0;
  return pool[Math.abs(h) % pool.length];
}
