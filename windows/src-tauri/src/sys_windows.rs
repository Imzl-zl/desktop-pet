// Windows-only: enumerate visible top-level windows so the pet can climb
// their edges. On other platforms the command returns an empty list.
//
// We use the `windows` crate (microsoft/windows-rs) with Win32
// EnumWindows + IsWindowVisible + GetWindowRect + GetWindowTextW.
//
// A short-lived TTL cache sits in front of the enumeration: the roam engine
// ticks every 30ms per pet window, and without the cache N pets would fire
// N×33 EnumWindows calls per second. The cache returns the previous snapshot
// for 150ms, capping the real enumeration at ~7 calls/sec regardless of how
// many pets are roaming.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const WIN_CACHE_TTL: Duration = Duration::from_millis(150);
/// Cache stores an `Arc` so cache hits return via a cheap atomic ref-count
/// increment instead of deep-cloning ~20 JSON values per call. With N pets
/// each calling 33×/sec, this avoids thousands of short-lived allocations/sec.
static WIN_CACHE: Mutex<Option<(Instant, Arc<Vec<serde_json::Value>>)>> = Mutex::new(None);

#[cfg(windows)]
mod win {
    use serde::Serialize;
    use windows::Win32::Foundation::{BOOL, HWND, LPARAM, RECT, TRUE};
    use windows::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetWindowRect, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible,
    };

    #[derive(Serialize)]
    pub struct SystemWindowInfo {
        pub title: String,
        pub x: i32,
        pub y: i32,
        pub width: i32,
        pub height: i32,
    }

    /// Collect visible top-level windows with a non-empty title and a
    /// reasonable size (>40x40). Excludes the pet's own process windows so
    /// the pet doesn't try to climb itself.
    pub fn enumerate() -> Vec<SystemWindowInfo> {
        let mut result: Vec<SystemWindowInfo> = Vec::new();
        let ptr = &mut result as *mut Vec<SystemWindowInfo> as isize;
        // SAFETY: EnumWindows calls our callback synchronously. The callback
        // only touches the Vec through the raw pointer we pass as LPARAM.
        unsafe {
            let _ = EnumWindows(Some(enum_proc), LPARAM(ptr));
        }
        result
    }

    extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
        unsafe {
            if !IsWindowVisible(hwnd).as_bool() {
                return TRUE;
            }

            // Skip zero-size / minimized windows.
            let mut rect = RECT::default();
            if GetWindowRect(hwnd, &mut rect).is_err() {
                return TRUE;
            }
            let w = rect.right - rect.left;
            let h = rect.bottom - rect.top;
            if w < 40 || h < 40 {
                return TRUE;
            }

            // Exclude the pet's own process windows so it doesn't climb itself.
            let mut pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == std::process::id() {
                return TRUE;
            }

            // Only keep windows with a non-empty title (filters out
            // tooltips, IME bars, and other shell chrome).
            let mut buf = [0u16; 512];
            let len = GetWindowTextW(hwnd, &mut buf);
            if len == 0 {
                return TRUE;
            }
            let title = String::from_utf16_lossy(&buf[..len as usize]);

            let vec = &mut *(lparam.0 as *mut Vec<SystemWindowInfo>);
            vec.push(SystemWindowInfo {
                title,
                x: rect.left,
                y: rect.top,
                width: w,
                height: h,
            });
        }
        TRUE
    }
}

/// Tauri command: returns visible application windows (physical pixels).
/// On non-Windows platforms, returns an empty list. A 150ms TTL cache caps the
/// real enumeration rate so multi-pet roaming doesn't flood Win32 EnumWindows.
/// Returns an `Arc<Vec>` so cache hits are O(1) (atomic ref-count increment)
/// instead of deep-cloning every JSON value on every call.
#[tauri::command]
pub fn list_system_windows() -> Arc<Vec<serde_json::Value>> {
    // Fast path: return the cached snapshot if it's still fresh.
    if let Ok(guard) = WIN_CACHE.lock() {
        if let Some((ts, ref data)) = *guard {
            if ts.elapsed() < WIN_CACHE_TTL {
                return Arc::clone(data);
            }
        }
    }

    #[cfg(windows)]
    let fresh: Vec<serde_json::Value> = {
        win::enumerate()
            .into_iter()
            .map(|w| serde_json::json!({
                "title": w.title,
                "x": w.x,
                "y": w.y,
                "width": w.width,
                "height": w.height,
            }))
            .collect()
    };
    #[cfg(not(windows))]
    let fresh: Vec<serde_json::Value> = Vec::new();

    let arc = Arc::new(fresh);
    // Update the cache for the next caller. A poisoned lock (panic in another
    // thread) just skips caching; the command still returns fresh data.
    if let Ok(mut guard) = WIN_CACHE.lock() {
        *guard = Some((Instant::now(), Arc::clone(&arc)));
    }
    arc
}
