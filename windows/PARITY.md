# macOS → Windows parity matrix

Đối chiếu từng chức năng sau khi đọc toàn bộ 9.010 dòng Swift (Sources/App + DesktopPetCore).
Trạng thái: ✅ có rồi · 🔧 đang port đợt này · ⏳ để đợt sau · ➖ không áp dụng trên Windows.

## Event pipeline (Core)
| Chức năng | macOS | Windows |
|---|---|---|
| Hook CLI → app (socket/HTTP) | unix socket | ✅ HTTP 127.0.0.1:47628 |
| State mapping (StateMapper) | ✓ | ✅ ported |
| Session store + prune (done 30s, stale 300s/90s) | ✓ | ✅ ported |
| Offline queue (hook chạy khi app tắt → replay) | ✓ | ✅ queue file + drain (đã test) |
| Claude Stop → đọc transcript → câu hỏi? → waiting (QuestionDetector) | ✓ | ✅ Rust port (đã test end-to-end) |
| Title hội thoại từ transcript (summary/first msg) | ✓ | ✅ Rust port |
| `desktoppet run -- <cmd>` wrapper (working/heartbeat/done) | ✓ | ✅ (đã test) |
| Notifications (waiting: "X needs input"+msg, done: "X finished") | ✓ | ✅ cùng copy với mac |
| Sounds: bật/tắt riêng done & waiting | ✓ | ✅ + upload file riêng (play/upload/default) |

## Pet window
| Chức năng | macOS | Windows |
|---|---|---|
| Sprite slicing alpha-gutter (frame trống không blink) | ✓ | ✅ ported |
| Mood tổng hợp (working>waiting>done>idle) | ✓ | ✅ |
| **Celebrate burst 3s khi xong việc** | ✓ | ✅ (đã test, pet nhảy + câu celebrate → done) |
| FPS theo mood (working 8 / waiting 4 / idle 3) | ✓ | ✅ |
| Idle line hiện LIÊN TỤC (không nhấp nháy 4s/30s) | ✓ | ✅ hết nhấp nháy |
| Kéo thả + nhớ vị trí + clamp màn hình | ✓ | ✅ |
| Click-through vùng trong suốt | ✓ | ✅ (Win32) |
| Right-click pet → menu | ✓ popover | ✅ mở Settings |
| Show/hide pet từ menu | ✓ | ✅ tray toggle (persist) |
| Pet size + animate mượt | 60–240 + S/M/L | ✅ 70–130% (đủ dùng) |

## Bubble đa agent
| Chức năng | macOS | Windows |
|---|---|---|
| Display mode: list / **carousel** (3s + dots) / compact (+N more) | ✓ (mặc định carousel) | ✅ cả 3 (carousel đã test) |
| Grouping theo agent (×N badge) / mọi session | ✓ | ✅ |
| Max rows (1–10), min-state filter, ẩn agent | ✓ | ✅ |
| Token layout 8 phần (dot/icon/title/project/sep/message/state/elapsed) + 3 preset | ✓ | ✅ + preview sống |
| **Icon brand từng agent (SVG nhúng)** | ✓ | ✅ đúng asset mac (đã test Anthropic/OpenAI) |
| Dot style: plain (blooming pulse) / Claude (✻ xoay) | ✓ | ✅ |
| AnimatedStatusText: xoá-gõ lại + ellipsis cycle + shimmer | ✓ | ✅ (đã test ellipsis) |
| Waiting: chữ cam + nhấp nháy nhẹ | ✓ | ✅ (đã test) |
| Separator tuỳ chọn (· → \| space) | ✓ | ✅ |
| Activity themes 5 bộ (Chef/Engineer/Wizard/Explorer/Scientist) theo TOOL + extensionHint + thinking | ✓ (mặc định Chef) | ✅ đủ 5 bộ (đã test Chef/Baking) |
| Custom messages per agent+mood, system/custom, reset, celebrate | ✓ | ✅ |
| Theme light/dark/system + opacity + font size | ✓ | ✅ |
| Elapsed format (5s/3m/1h 4m) tick 1s | ✓ | ✅ format mac |

## Tray / Menu bar
| Chức năng | macOS | Windows |
|---|---|---|
| Đếm agent cạnh icon (cam khi waiting) | ✓ | ✅ tray tooltip (N working / N waiting) |
| Popover sessions (project, msg, elapsed, dismiss, Clear all) | ✓ | ✅ trong Settings General + snapshot sync |
| Toggle: Show pet / count / chat / bubble on menu bar | ✓ | ✅ Show pet; còn lại ➖ (Windows tray không treo UI) |
| Chat pill + bubble treo menu bar | ✓ | ➖ |

## Settings
| Chức năng | macOS | Windows |
|---|---|---|
| Tabs General/Pet/Bubble/About + bottom bar preview | ✓ | ✅ |
| Sounds: 2 hàng riêng (play/upload/default) | ✓ | ✅ đầy đủ |
| Codex help (trust /hooks) modal | ✓ | ✅ |
| Sessions list + dismiss + Clear all | ✓ (popover) | ✅ trong General |
| Pet: hero + browse + import + size | ✓ | ✅ |
| Animations: gán clip cho từng mood (PetBindings) | ✓ | ✅ (5 mood × 9 animation) |
| Create pet (đặt tên → local pack) + delete | ✓ | ✅ import giữ tên file làm tên pet |
| Onboarding 3 bước | ✓ | ⏳ (mở Settings lần đầu) |
| Segmented controls + bold headers + About pills + icon app từ icns mac | ✓ | ✅ đối chiếu screenshot từng tab |
| Multi-agent bubble toggle (off = simple bubble) | ✓ | ✅ |
| Live preview panel (demo webhook đa agent) | ✓ | ✅ FULL panel (stage + quick scenarios + webhook list + add column, cửa sổ nở 640→1380) |
| Updater | Sparkle + badge | ✅ Tauri updater |
