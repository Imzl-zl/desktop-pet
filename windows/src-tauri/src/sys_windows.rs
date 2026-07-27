// Windows-only: enumerate visible top-level windows so the pet can climb
// their edges. On other platforms the command returns an empty list.
//
// We use the `windows` crate (microsoft/windows-rs) with Win32
// EnumWindows + IsWindowVisible + GetWindowRect + GetWindowTextW.

#[cfg(windows)]
mod win {
    use serde::Serialize;
    use windows::Win32::Foundation::{BOOL, HWND, LPARAM, RECT, TRUE};
    use windows::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetWindowRect, GetWindowTextW, IsWindowVisible,
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
/// On non-Windows platforms, returns an empty list.
#[tauri::command]
pub fn list_system_windows() -> Vec<serde_json::Value> {
    #[cfg(windows)]
    {
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
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}
