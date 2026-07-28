<div align="center">
  <img src="../../assets/banner.png" alt="DesktopPet" width="100%" />
  <p><em>DesktopPet là fork được đổi tên và chỉnh sửa từ <a href="https://github.com/ntd4996/agentpet">AgentPet</a>, sử dụng theo giấy phép MIT.</em></p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%C2%B7%20Windows%2010%2F11-black" alt="macOS 13+ &middot; Windows 10/11" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" />
    <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift" />
    <a href="https://github.com/Imzl-zl/desktop-pet"><img src="https://img.shields.io/github/stars/Imzl-zl/desktop-pet?style=social" alt="GitHub stars" /></a>
  </p>
  <p><b>Nếu DesktopPet giúp ích cho bạn, hãy <a href="https://github.com/Imzl-zl/desktop-pet">tặng một sao</a> nhé!</b></p>
  <p>
    <a href="../../README.md">English</a> ·
    <b>Tiếng Việt</b> ·
    <a href="README.zh-Hans.md">简体中文</a> ·
    <a href="README.ja.md">日本語</a>
  </p>
</div>

Chạy nhiều agent lập trình cùng lúc (Claude Code, Codex, ...) và DesktopPet cho bạn biết ngay con nào **đang chạy**, con nào **đã xong**, con nào **đang chờ bạn nhập liệu**, để khỏi phải lật qua lại giữa các terminal. Một chú pet nhỏ nổi trên màn hình và phản ứng theo tất cả.

## Vì sao

Chạy nhiều agent song song nghĩa là phải liên tục đổi cửa sổ để xem con nào cần mình. DesktopPet hiển thị điều đó ở hai nơi:

- **Trình theo dõi ở menu bar** cho chi tiết: mọi agent đang chạy, trạng thái, đang làm gì, và bộ đếm thời gian trực tiếp.
- **Pet trên desktop** cho tín hiệu nhẹ nhàng, đọc được mà không phải dứt khỏi công việc.

## Tính năng

- **Theo dõi đa agent** ở menu bar: danh sách trực tiếp từng agent với chấm màu trạng thái, tên project, đang làm gì (công cụ đang chạy / lý do chờ), và bộ đếm theo trạng thái cập nhật thời gian thực.
- **Icon menu bar liếc-là-biết**: hiện số agent đang chạy, chuyển **cam kèm số** khi có agent cần bạn nhập liệu.
- **Pet trên desktop** phản ứng theo trạng thái tổng hợp (working / waiting / done / celebrate), kèm **bong bóng chat** tùy chọn (tin nhắn mặc định hoặc tự đặt).
- **Thông báo hệ thống** khi agent xong hoặc cần nhập liệu.
- Tích hợp **Claude Code, Codex & Gemini CLI** qua hook, cài một chạm từ Settings (nhận đúng working / waiting / done / idle, kể cả "cần bạn nhập liệu").
- **Wrapper phổ quát** `desktoppet run -- <lệnh>` để theo dõi *bất kỳ* agent CLI nào (working/done), không cần cấu hình riêng.
- **Hệ thống pet**: duyệt thư viện pet trực tuyến và tải về một chạm, gán animation cho từng trạng thái, đổi kích thước, tùy biến câu chat.
- **Settings native, chỉn chu** (chia tab, nền tối) và không bao giờ cướp focus.

## Ảnh chụp

<div align="center">
  <img src="../../assets/screenshot-hud.png" width="300" alt="Chuột phải vào pet để xem HUD chỉ số: level, XP, độ đói, biểu đồ token 7 ngày và hạn mức gói" />
  <p><sub><b>Chuột phải vào pet</b> để mở HUD kiểu game , level, XP, độ đói, biểu đồ token 7 ngày và hạn mức Claude/Codex trực tiếp.</sub></p>
</div>

<table align="center">
  <tr>
    <td align="center" width="50%"><img src="../../assets/screenshot-menubar.png" width="380" alt="Trình theo dõi menu bar" /><br/><sub>Theo dõi menu bar , mọi agent trong một cái nhìn</sub></td>
    <td align="center" width="50%"><img src="../../assets/screenshot-care.png" width="380" alt="Tab Chăm sóc" /><br/><sub>Tab Chăm sóc , nuôi pet bằng công việc thật</sub></td>
  </tr>
  <tr>
    <td align="center" width="50%"><img src="../../assets/screenshot-settings.png" width="380" alt="Cài đặt" /><br/><sub>Cài đặt native, dạng tab</sub></td>
    <td align="center" width="50%"><img src="../../assets/screenshot-pet.png" width="380" alt="Pet trên desktop" /><br/><sub>Pet trên desktop</sub></td>
  </tr>
</table>

<div align="center">
  <br/>
  <img src="../../assets/screenshot-leaderboard.png" width="660" alt="Bảng xếp hạng cộng đồng" />
  <p><sub><a href="https://agentpet.thenightwatcher.online/leaderboard">Bảng xếp hạng</a> cộng đồng , theo level, phiên hoặc token.</sub></p>
  <img src="../../assets/demo.gif" width="600" alt="Pet phản ứng theo agent" />
</div>

## Yêu cầu

- **macOS 13 Ventura trở lên** (khuyến nghị macOS 14 Sonoma trở lên; phần tắt focus ring dùng API có từ macOS 14+).
- Hỗ trợ cả **Mac Apple Silicon (M1/M2/M3/M4) và Mac Intel**.
- Hỗ trợ macOS 13+ (Apple Silicon & Intel) và Windows 10/11 (64-bit). Bản Windows ở thư mục `windows/` (Tauri + Rust).
- Để build từ mã nguồn: Xcode 16 / Swift 6.

## Cài đặt

### Homebrew

```bash
brew install --cask Imzl-zl/tap/desktoppet
```

### Tải trực tiếp

Tải `DesktopPet.dmg` mới nhất ở [Releases](https://github.com/Imzl-zl/desktop-pet/releases), mở ra và kéo DesktopPet vào Applications.

### Build từ mã nguồn

```bash
git clone https://github.com/Imzl-zl/desktop-pet.git
cd desktoppet
./scripts/build-app.sh release
open build/DesktopPet.app
```

> **Lưu ý:** bản hiện tại đã ký Developer ID nhưng **chưa notarize**, nên macOS có thể chặn lần mở đầu. Gỡ cờ quarantine một lần:
> ```bash
> xattr -dr com.apple.quarantine "/Applications/DesktopPet.app"
> ```
> Bản notarize đầy đủ (không cảnh báo) sắp có.

Lần đầu mở, vào **Settings → General**, bấm **Install** cạnh Claude Code, rồi **Enable** thông báo.

## Cách dùng

**Claude Code** (khuyến nghị): cài hook từ Settings. DesktopPet sẽ phản ánh đúng trạng thái thật của từng phiên (kể cả "đang chờ nhập liệu").

**Agent CLI khác**: bọc nó lại.

```bash
desktoppet run -- <lệnh-agent-của-bạn>     # ví dụ: desktoppet run -- aider
```

Phiên hiện *working* khi đang chạy và *done* khi kết thúc.

## Pet

Pet dùng định dạng pet-pack mở của Codex (`pet.json` + spritesheet lưới 8×9). Bạn có thể:

- **Duyệt** thư viện trực tuyến và tải pet về một chạm (Settings → Pet → Browse pets).
- **Gán animation**: chọn animation nào chạy cho từng trạng thái.
- **Xóa** pet không dùng nữa.

Một pet khởi đầu được cài tự động lần đầu chạy. DesktopPet không đóng gói sẵn art pet nào; pet được thêm lúc chạy.

## Lộ trình

- DMG notarize + Homebrew cask
- Bấm vào agent để mở terminal của nó
- Pet riêng theo từng project

## Công nghệ

Swift + SwiftUI, một daemon Unix-socket cho sự kiện agent, và một CLI helper nhỏ, gói gọn trong một package SwiftPM. Xem [`docs/specs`](../specs) để biết thiết kế.

## Ủng hộ

Nếu DesktopPet giúp bạn đỡ phải lật terminal, đây là cách giúp lại:

- ⭐ **[Tặng sao cho repo](https://github.com/Imzl-zl/desktop-pet)** để nhiều người biết tới hơn.
- ☕ **[Mời mình một ly cà phê](https://buymeacoffee.com/ntd4996)** nếu bạn muốn tiếp thêm động lực.

Thực hiện bởi **[Nguyễn Thành Đạt (@ntd4996)](https://github.com/ntd4996)**.

## Ghi nhận

Định dạng pet-pack Codex và thư viện pet trực tuyến do **[Petdex](https://github.com/crafter-station/petdex)** (MIT) cung cấp. DesktopPet là một client interop độc lập: đọc pack theo định dạng của Petdex và cho phép tải pet từ API công khai của Petdex. DesktopPet không đóng gói art pet; mỗi asset pet thuộc về người đóng góp theo giấy phép riêng của họ. Nếu bạn giữ bản quyền một nhân vật, vui lòng gửi yêu cầu gỡ tới Petdex.

## Giấy phép

MIT, xem [LICENSE](../../LICENSE). Chỉ áp dụng cho mã ứng dụng; art pet không thuộc repo này.
