pub mod cli;
pub mod hooks;
pub mod server;
pub mod statemap;
pub mod sys_windows;
pub mod transcript;

use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindowBuilder};

/// Tray menu items kept around so the language switcher can re-label them live.
struct TrayItems {
    show_pet: tauri::menu::CheckMenuItem<tauri::Wry>,
    settings: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
    tray: tauri::tray::TrayIcon<tauri::Wry>,
}

/// One opaque rectangle reported by the stage frontend. The stage window is a
/// single transparent overlay; anywhere NOT covered by these rects must pass
/// mouse events through to the desktop below.
#[derive(Default, Clone, serde::Deserialize)]
#[cfg_attr(not(windows), allow(dead_code))]
struct HitRect {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

/// All opaque regions inside the single stage window. Replaces the previous
/// per-pet-window HitRectMap.
type StageHitRegions = Vec<HitRect>;

const STAGE_LABEL: &str = "stage";
const EXTRA_PREFIX: &str = "pet-extra-";
const BALL_W: f64 = 80.0;
const BALL_H: f64 = 80.0;
const SNAP_MARGIN: f64 = 4.0;

static EXTRA_COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Set by the frontend for the whole duration of a pet/ball drag. While true,
/// the hit loop keeps the window interactive no matter where the cursor is —
/// otherwise a fast drag can outrun the 60ms hit poll + IPC region update, the
/// cursor lands "outside" the (stale) hit region, click-through re-enables
/// mid-drag and the window stops receiving mousemove/mouseup (drag dies).
static DRAG_LOCK: AtomicBool = AtomicBool::new(false);

/// Frontend toggles this around a drag (mousedown → mouseup). See DRAG_LOCK.
#[tauri::command]
fn set_drag_lock(locked: bool) {
    DRAG_LOCK.store(locked, Ordering::Relaxed);
}

/// Append a line to %APPDATA%/DesktopPet/debug.log , lightweight field
/// diagnostics for the Windows build (no console there).
fn dlog(msg: &str) {
    if let Some(p) = dirs::config_dir().map(|d| d.join("DesktopPet").join("debug.log")) {
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
            use std::io::Write;
            let ts = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let _ = writeln!(f, "[{ts}] {msg}");
        }
    }
}

#[tauri::command]
fn log_debug(msg: String) {
    dlog(&msg);
}

fn pos_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("DesktopPet").join("pos"))
}

#[allow(dead_code)]
fn read_pos() -> Option<(i32, i32)> {
    let s = std::fs::read_to_string(pos_file()?).ok()?;
    let (a, b) = s.trim().split_once(',')?;
    Some((a.trim().parse().ok()?, b.trim().parse().ok()?))
}

#[allow(dead_code)]
fn write_pos(x: i32, y: i32) {
    if let Some(p) = pos_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, format!("{x},{y}"));
    }
}

fn ball_pos_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("DesktopPet").join("ball-pos"))
}

#[tauri::command]
fn read_ball_pos() -> Option<(f64, f64)> {
    let s = std::fs::read_to_string(ball_pos_file()?).ok()?;
    let (a, b) = s.trim().split_once(',')?;
    Some((a.trim().parse().ok()?, b.trim().parse().ok()?))
}

fn write_ball_pos(x: f64, y: f64) {
    if let Some(p) = ball_pos_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, format!("{x},{y}"));
    }
}

fn ball_visible_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("DesktopPet").join("ball-visible"))
}

fn read_ball_visible() -> bool {
    ball_visible_file()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .map(|s| s.trim() != "0")
        .unwrap_or(true)
}

fn write_ball_visible(on: bool) {
    if let Some(p) = ball_visible_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, if on { "1" } else { "0" });
    }
}

fn pet_visible_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("DesktopPet").join("petvisible"))
}

fn read_pet_visible() -> bool {
    pet_visible_file()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .map(|s| s.trim() != "0")
        .unwrap_or(true)
}

fn write_pet_visible(on: bool) {
    if let Some(p) = pet_visible_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, if on { "1" } else { "0" });
    }
}

/// Report all opaque rectangles inside the single stage window (physical px,
/// window-relative). The background thread uses this to pass clicks through
/// everywhere else.
#[tauri::command]
fn set_stage_hit_regions(app: tauri::AppHandle, regions: Vec<HitRect>) {
    if let Some(state) = app.try_state::<Mutex<StageHitRegions>>() {
        if let Ok(mut m) = state.lock() {
            *m = regions;
        }
    }
}

#[tauri::command]
fn read_main_pet_pos() -> Option<(f64, f64)> {
    pos_file().and_then(|p| {
        let s = std::fs::read_to_string(p).ok()?;
        let (a, b) = s.trim().split_once(',')?;
        Some((a.trim().parse().ok()?, b.trim().parse().ok()?))
    })
}

#[tauri::command]
fn save_main_pet_pos(x: f64, y: f64) {
    if let Some(p) = pos_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, format!("{x},{y}"));
    }
}

/// Snap the dropped stage ball to the nearest monitor edge and persist the
/// position. The frontend passes the ball's logical screen position; we find
/// the monitor under that point and apply the same edge-snap logic that the
/// old native floating-ball window used.
#[tauri::command]
fn snap_stage_ball(app: tauri::AppHandle, x: f64, y: f64) {
    let Some(mon) = monitor_at_logical_point(&app, x, y) else { return };
    let sf = mon.scale_factor();
    let mp = mon.position();
    let ms = mon.size();
    let mon_left = mp.x as f64 / sf;
    let mon_top = mp.y as f64 / sf;
    let mon_w = ms.width as f64 / sf;
    let mon_h = ms.height as f64 / sf;
    let mon_right = mon_left + mon_w;
    let mon_bottom = mon_top + mon_h;

    let d_left = x - mon_left;
    let d_right = mon_right - (x + BALL_W);
    let d_top = y - mon_top;
    let d_bottom = mon_bottom - (y + BALL_H);

    let (nx, ny) = if d_left <= d_right && d_left <= d_top && d_left <= d_bottom {
        (mon_left + SNAP_MARGIN, y.max(mon_top).min(mon_bottom - BALL_H))
    } else if d_right <= d_top && d_right <= d_bottom {
        (mon_right - BALL_W - SNAP_MARGIN, y.max(mon_top).min(mon_bottom - BALL_H))
    } else if d_top <= d_bottom {
        (x.max(mon_left).min(mon_right - BALL_W), mon_top + SNAP_MARGIN)
    } else {
        (x.max(mon_left).min(mon_right - BALL_W), mon_bottom - BALL_H - SNAP_MARGIN)
    };

    write_ball_pos(nx, ny);
    let _ = app.emit_to(STAGE_LABEL, "stage-ball-snap", serde_json::json!({ "x": nx, "y": ny }));
}

fn monitor_at_logical_point(app: &tauri::AppHandle, x: f64, y: f64) -> Option<tauri::Monitor> {
    app.available_monitors().ok().and_then(|mons| {
        mons.into_iter().find(|m| {
            let sf = m.scale_factor();
            let p = m.position();
            let s = m.size();
            let left = p.x as f64 / sf;
            let top = p.y as f64 / sf;
            let right = left + s.width as f64 / sf;
            let bottom = top + s.height as f64 / sf;
            x >= left && x < right && y >= top && y < bottom
        })
    }).or_else(|| app.primary_monitor().ok().flatten())
}

#[tauri::command]
fn set_stage_ball_visible(app: tauri::AppHandle, visible: bool) {
    write_ball_visible(visible);
    let _ = app.emit_to(STAGE_LABEL, "stage-ball-visible", visible);
}

#[tauri::command]
fn get_stage_ball_visible() -> bool {
    read_ball_visible()
}

fn lang_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("DesktopPet").join("lang"))
}

fn read_lang() -> String {
    lang_file()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "en".into())
}

fn write_lang(code: &str) {
    if let Some(p) = lang_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, code);
    }
}

/// Localised tray labels (the only app text on the Rust side).
fn tray_labels(code: &str) -> (&'static str, &'static str, &'static str) {
    match code {
        "vi" => ("Hiện pet", "Cài đặt", "Thoát DesktopPet"),
        "zh" => ("显示宠物", "设置", "退出 DesktopPet"),
        _ => ("Show pet", "Settings", "Quit DesktopPet"),
    }
}

#[tauri::command]
fn list_agents() -> Vec<hooks::AgentInfo> {
    hooks::catalog()
}

#[tauri::command]
fn is_installed(kind: String) -> bool {
    hooks::is_installed(&kind)
}

#[tauri::command]
fn toggle_install(kind: String) -> Result<bool, String> {
    hooks::toggle(&kind)
}

/// Window creation MUST NOT run inside a sync command / menu callback on
/// Windows (the webview build deadlocks against the blocked event loop), so
/// every caller goes through this thread-spawning wrapper.
fn open_settings_impl(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        dlog("open_settings: worker thread");
        if let Some(w) = app.get_webview_window("settings") {
            dlog("open_settings: existing window, showing");
            let _ = w.show();
            let _ = w.unminimize();
            let _ = w.set_focus();
            return;
        }
        match WebviewWindowBuilder::new(&app, "settings", WebviewUrl::App("settings.html".into()))
            .title("DesktopPet")
            .inner_size(1000.0, 680.0)
            .min_inner_size(760.0, 560.0)
            .resizable(true)
            .build()
        {
            Ok(_) => dlog("open_settings: window created"),
            Err(e) => dlog(&format!("open_settings: BUILD FAILED: {e}")),
        }
    });
}

#[tauri::command]
async fn open_settings(app: tauri::AppHandle) {
    dlog("open_settings called");
    open_settings_impl(app);
}

/// Logical size of the primary monitor's work area (DPI-divided). Returns a
/// safe fallback (1920×1080) if the monitor can't be read , spawns must never
/// land off-screen on display hotplug / headless CI.
fn primary_work_area(app: &tauri::AppHandle) -> (f64, f64) {
    app.primary_monitor()
        .ok()
        .flatten()
        .and_then(|m| {
            let wa = m.work_area();
            let sf = m.scale_factor();
            if wa.size.width > 0 && wa.size.height > 0 {
                Some((wa.size.width as f64 / sf, wa.size.height as f64 / sf))
            } else {
                None
            }
        })
        .unwrap_or((1920.0, 1080.0))
}

/// Open an external link in the default browser (About tab buttons).
#[tauri::command]
fn open_url(url: String) {
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return;
    }
    #[cfg(windows)]
    {
        let _ = std::process::Command::new("cmd").args(["/c", "start", "", &url]).spawn();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open").arg(&url).spawn();
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
    }
}

/// Bring the terminal running a session to the front when its bubble row is
/// clicked. Warp exports a `warp://session/<uuid>` deep link that focuses the
/// exact pane , the one reliable cross-platform "focus exact tab". Other
/// terminals have no dependable tab-focus API on Windows/Linux, so we only
/// best-effort activate the app on macOS (where the Tauri build is dev-only).
/// A safe `warp://session/<uuid>` deep link: scheme + only URL-safe characters,
/// so it can never carry shell metacharacters into `cmd /c start`.
fn is_safe_warp_url(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("warp://") else { return false };
    !rest.is_empty()
        && rest
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | '-'))
}

#[tauri::command]
fn focus_terminal(program: String, focus_url: String) {
    if is_safe_warp_url(&focus_url) {
        #[cfg(windows)]
        { let _ = std::process::Command::new("cmd").args(["/c", "start", "", &focus_url]).spawn(); }
        #[cfg(target_os = "macos")]
        { let _ = std::process::Command::new("open").arg(&focus_url).spawn(); }
        #[cfg(all(unix, not(target_os = "macos")))]
        { let _ = std::process::Command::new("xdg-open").arg(&focus_url).spawn(); }
        return;
    }
    #[cfg(target_os = "macos")]
    {
        let app = match program.as_str() {
            "Apple_Terminal" => Some("Terminal"),
            "iTerm.app" => Some("iTerm"),
            _ => None,
        };
        if let Some(a) = app {
            let _ = std::process::Command::new("open").args(["-a", a]).spawn();
        }
    }
    let _ = program;
}

/// Deliver the user's Allow/Deny decision for a gated tool call back to the
/// parked hook request (see server::handle_approval).
#[tauri::command]
fn resolve_approval(id: String, decision: String) {
    crate::server::resolve_approval(&id, &decision);
}

/// Settings still calls this to broadcast the current project list. The stage
/// frontend receives the event and owns the actual pet entities.
#[tauri::command]
fn sync_project_windows(app: tauri::AppHandle, projects: Vec<String>) {
    let _ = app.emit_to(STAGE_LABEL, "stage-sync-projects", projects);
}

/// Settings still calls this to request a new extra pet. We generate a label,
/// tell the stage frontend to spawn it, and return the label.
#[tauri::command]
async fn spawn_extra_pet(app: tauri::AppHandle, slug: String) -> Result<String, String> {
    if slug.is_empty() {
        return Err("empty slug".into());
    }
    let n = EXTRA_COUNTER.fetch_add(1, Ordering::Relaxed);
    let label = format!("{EXTRA_PREFIX}{slug}-{n}");
    let (sw, sh) = primary_work_area(&app);
    let x = (120.0 + (n as f64) * 40.0).min(sw - 280.0).max(20.0);
    let y = (120.0 + (n as f64) * 40.0).min(sh - 360.0).max(20.0);
    let _ = app.emit_to(
        STAGE_LABEL,
        "stage-spawn-extra",
        serde_json::json!({ "slug": slug, "label": label, "x": x, "y": y }),
    );
    Ok(label)
}

/// Settings still calls this to close an extra pet. We tell the stage frontend
/// to destroy the entity with this label.
#[tauri::command]
fn close_extra_pet(app: tauri::AppHandle, label: String) -> Result<(), String> {
    if !label.starts_with(EXTRA_PREFIX) {
        return Err("not an extra pet window".into());
    }
    let _ = app.emit_to(STAGE_LABEL, "stage-close-extra", serde_json::json!({ "label": label }));
    Ok(())
}

/// The stage frontend now tracks extra pets internally; return an empty list
/// so Settings doesn't list stale native window labels.
#[tauri::command]
fn list_extra_pets() -> Vec<String> {
    Vec::new()
}

/// Persist the chosen language (for the tray on next launch) and re-label the
/// tray menu items now. Called by the Settings language switcher.
#[tauri::command]
fn set_lang(app: tauri::AppHandle, code: String) {
    write_lang(&code);
    let (p, s, q) = tray_labels(&code);
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let _ = it.show_pet.set_text(p);
            let _ = it.settings.set_text(s);
            let _ = it.quit.set_text(q);
        }
    }
}

/// Live agent counts from the pet window → tray tooltip.
#[tauri::command]
fn set_tray_status(app: tauri::AppHandle, working: u32, waiting: u32) {
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let tip = if waiting > 0 {
                format!("DesktopPet , {waiting} waiting for you")
            } else if working > 0 {
                format!("DesktopPet , {working} working")
            } else {
                "DesktopPet".to_string()
            };
            let _ = it.tray.set_tooltip(Some(tip));
        }
    }
}

#[tauri::command]
fn get_pet_visible(app: tauri::AppHandle) -> bool {
    app.get_webview_window(STAGE_LABEL)
        .and_then(|w| w.is_visible().ok())
        .unwrap_or(true)
}

/// Show the popover inside the single stage window. The stage frontend owns
/// positioning and rendering; Rust just broadcasts the request.
#[tauri::command]
async fn open_popover(app: tauri::AppHandle) {
    dlog("open_popover called");
    let _ = app.emit_to(STAGE_LABEL, "popover-shown", ());
}

/// Show/hide the stage overlay (tray toggle).
#[tauri::command]
fn set_pet_visible(app: tauri::AppHandle, visible: bool) {
    if let Some(win) = app.get_webview_window(STAGE_LABEL) {
        if visible {
            let _ = win.show();
        } else {
            let _ = win.hide();
        }
    }
    write_pet_visible(visible);
    let _ = app.emit_to(STAGE_LABEL, "stage-visibility", visible);
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let _ = it.show_pet.set_checked(visible);
        }
    }
}

/// Resize and position the single stage window to fill the primary monitor's
/// work area, then show it.
fn spawn_stage_impl(app: tauri::AppHandle) {
    let Some(win) = app.get_webview_window(STAGE_LABEL) else {
        dlog("spawn_stage_impl: no stage window in tauri.conf.json");
        return;
    };
    let Some(mon) = app.primary_monitor().ok().flatten() else {
        dlog("spawn_stage_impl: no primary monitor");
        let _ = win.show();
        return;
    };
    let wa = mon.work_area();
    let _ = win.set_position(PhysicalPosition::new(wa.position.x, wa.position.y));
    let _ = win.set_size(PhysicalSize::new(wa.size.width, wa.size.height));
    let _ = win.show();
}

/// Background thread: watch the single stage window and toggle click-through
/// for the whole window whenever the cursor is outside every opaque region.
fn start_stage_hit_loop(handle: tauri::AppHandle) {
    std::thread::spawn(move || {
        let mut last_ignore: Option<bool> = None;
        let mut flip_logs: u32 = 0;
        loop {
            std::thread::sleep(Duration::from_millis(60));
            let Some(win) = handle.get_webview_window(STAGE_LABEL) else { continue };
            let cur = handle.cursor_position();
            let Ok(wp) = win.outer_position() else { continue };
            let inside = if DRAG_LOCK.load(Ordering::Relaxed) {
                // A drag is in progress — keep the whole window interactive so a
                // fast drag that outruns the hit-region update can't slip into
                // click-through and kill the drag.
                true
            } else {
                match &cur {
                Ok(cur) => {
                    let rx = cur.x - wp.x as f64;
                    let ry = cur.y - wp.y as f64;
                    handle
                        .try_state::<Mutex<StageHitRegions>>()
                        .and_then(|s| {
                            s.lock().ok().map(|regions| {
                                regions.is_empty()
                                    || regions.iter().any(|r| {
                                        r.w > 0.0
                                            && rx >= r.x
                                            && rx <= r.x + r.w
                                            && ry >= r.y
                                            && ry <= r.y + r.h
                                    })
                            })
                        })
                        .unwrap_or(true)
                }
                Err(_) => true,
                }
            };
            let ignore = !inside;
            if last_ignore != Some(ignore) {
                let _ = win.set_ignore_cursor_events(ignore);
                last_ignore = Some(ignore);
                if flip_logs < 60 {
                    flip_logs += 1;
                    let cur_str = cur.as_ref().map_or("err".to_string(), |c| format!("({:.0},{:.0})", c.x, c.y));
                    dlog(&format!("stage hit flip: ignore={ignore} cur={cur_str} win=({},{})", wp.x, wp.y));
                }
            }
        }
    });
}

fn build_tray(app: &tauri::App, pet_visible: bool) -> tauri::Result<()> {
    let (p_lbl, s_lbl, q_lbl) = tray_labels(&read_lang());
    let show_pet_i = tauri::menu::CheckMenuItem::with_id(
        app, "show_pet", p_lbl, true, pet_visible, None::<&str>)?;
    let settings_i = MenuItem::with_id(app, "settings", s_lbl, true, None::<&str>)?;
    let quit_i = MenuItem::with_id(app, "quit", q_lbl, true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show_pet_i, &settings_i, &quit_i])?;
    let mut tray = TrayIconBuilder::new()
        .tooltip("DesktopPet")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(|tray, event| {
            if let tauri::tray::TrayIconEvent::Click {
                button: tauri::tray::MouseButton::Left,
                button_state: tauri::tray::MouseButtonState::Up,
                ..
            } = event
            {
                open_settings_impl(tray.app_handle().clone());
            }
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show_pet" => {
                let now_visible = app
                    .get_webview_window(STAGE_LABEL)
                    .and_then(|w| w.is_visible().ok())
                    .unwrap_or(true);
                set_pet_visible(app.clone(), !now_visible);
            }
            "settings" => open_settings_impl(app.clone()),
            "quit" => app.exit(0),
            _ => {}
        });
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    let tray = tray.build(app)?;
    app.manage(Mutex::new(TrayItems {
        show_pet: show_pet_i.clone(),
        settings: settings_i.clone(),
        quit: quit_i.clone(),
        tray,
    }));
    Ok(())
}

fn maybe_onboard(app: tauri::AppHandle) {
    let marker = dirs::config_dir().map(|d| d.join("DesktopPet").join(".onboarded"));
    if let Some(m) = marker {
        if !m.exists() {
            open_settings_impl(app);
            if let Some(parent) = m.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = std::fs::write(&m, "1");
        }
    }
}

fn emit_startup_ball_visible(app: tauri::AppHandle) {
    if read_ball_visible() {
        let _ = app.emit_to(STAGE_LABEL, "stage-ball-visible", true);
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Must be the first plugin: a second launch (double-clicking the
        // shortcut while the app runs) exits immediately and the running
        // instance opens Settings instead , no duplicate pets.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            open_settings_impl(app.clone());
        }))
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .invoke_handler(tauri::generate_handler![
            list_agents,
            is_installed,
            toggle_install,
            open_settings,
            open_url,
            focus_terminal,
            resolve_approval,
            sync_project_windows,
            spawn_extra_pet,
            close_extra_pet,
            list_extra_pets,
            set_lang,
            set_tray_status,
            set_pet_visible,
            get_pet_visible,
            open_popover,
            log_debug,
            set_stage_hit_regions,
            set_drag_lock,
            read_main_pet_pos,
            save_main_pet_pos,
            read_ball_pos,
            snap_stage_ball,
            set_stage_ball_visible,
            get_stage_ball_visible,
            sys_windows::list_system_windows
        ])
        .setup(|app| {
            server::start(app.handle().clone());
            app.manage(Mutex::new(StageHitRegions::new()));

            let pet_visible = read_pet_visible();
            spawn_stage_impl(app.handle().clone());
            if !pet_visible {
                if let Some(win) = app.get_webview_window(STAGE_LABEL) {
                    let _ = win.hide();
                }
            }

            start_stage_hit_loop(app.handle().clone());
            build_tray(app, pet_visible)?;
            maybe_onboard(app.handle().clone());
            emit_startup_ball_visible(app.handle().clone());

            dlog("setup complete, stage + tray + loop running");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running DesktopPet");
}
