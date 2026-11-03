<!-- markdownlint-disable MD033 MD041 -->

<div align="center">

# Enzo Quickshell Bar for Hyprland

_A modern floating status bar built with [Quickshell](https://quickshell.outfoxxed.me/) for [Hyprland](https://hyprland.org)_  
_Minimal. Smooth. Fast._

<br>

![Hyprland](https://img.shields.io/badge/Hyprland-303446?style=for-the-badge&logo=hyprland&logoColor=8caaee)
![Quickshell](https://img.shields.io/badge/Quickshell-303446?style=for-the-badge&logo=qt&logoColor=ca9ee6)
![License](https://img.shields.io/badge/License-MIT-303446?style=for-the-badge&logo=github&logoColor=a6d189)

<br><br>

<img src="https://i.ibb.co/DD4fw8Yv/image.png" width="100%">

</div>

---

## Features

- **Dynamic Workspaces**: Animated workspace pills that react instantly to Hyprland state.
- **Smart Media**: MPRIS-powered controls, dynamic player detection, and smooth scrolling titles.
- **System Stats**: Live CPU & Memory tracking with lightweight polling and clean graphs.
- **Network & Audio**: Wi-Fi status via `nmcli`, scroll-to-volume, and quick action bindings.
- **Battery Module**: Adaptive battery icons, low-power alerts, and live percentage.
- **Action Buttons**: Fully custom commands (launcher, wallpaper, power) via `config.json`.
- **Window Titles**: Smart title shortening and app-specific icons.
- **Premium UI**: Nerd Fonts for crisp icons combined with native sans-serif fonts for sharp UI text.

---

## Design Philosophy

This bar is designed around:
- Floating layouts
- Soft transparency
- Catppuccin-inspired colors
- Glassmorphism aesthetics
- Smooth animations
- Pixel-perfect spacing

The goal is to feel premium without becoming distracting.

---

## Dependencies

| Package | Purpose |
|---|---|
| **[Quickshell](https://quickshell.outfoxxed.me/)** | Core framework |
| **[Hyprland](https://hyprland.org)** | Wayland compositor |
| `rofi` | App launcher |
| `playerctl` | Media controls |
| `wpctl` | Audio control |
| `pavucontrol` | Audio mixer |
| `nmcli` | Network status |
| `wlogout` | Power menu |
| `JetBrainsMono Nerd Font` | Icons & typography |

---

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/EnzoNotNice/quickshell-bar.git ~/.config/quickshell
```

### 2. Launch the Bar
```bash
quickshell
```

### 3. Autostart with Hyprland
Add this to your `hyprland.conf`:
```conf
exec-once = quickshell &
```

> [!TIP]
> Add this bind to your `hyprland.conf` to easily reload the bar on-the-fly while customizing:
> ```conf
> bind = $mainMod SHIFT, R, exec, killall quickshell; quickshell &
> ```

---

## Configuration

All interactive buttons are configurable through `config.json`.

```json
{
    "launcherCommand": "rofi -show drun",
    "launcherIcon": "",

    "wallpaperCommand": "qs ipc call wallpaper toggle",
    "wallpaperIcon": "",

    "powerCommand": "wlogout -b 2 -c 0 -r 0 -L 930 -R 930 -T 300 -B 300 --protocol layer-shell",
    "powerIcon": ""
}
```

> [!NOTE]
> Icons can be left blank (`""`) to use default text, or populated with any Nerd Font characters (e.g., ``, ``, ``) to display custom symbols in the bar.

---

## Modules

| Module | Description |
|---|---|
| `Workspaces.qml` | Animated workspace pills |
| `Clock.qml` | Minimal clock module |
| `SystemStats.qml` | CPU & RAM usage |
| `Media.qml` | MPRIS media integration |
| `Network.qml` | Wi-Fi monitoring |
| `Volume.qml` | Audio controls |
| `Battery.qml` | Battery status |
| `WindowTitle.qml` | Active window display |

---

## File Structure

```text
~/.config/quickshell/
├── shell.qml
├── config.json
├── modules/
│   ├── Workspaces.qml
│   ├── Clock.qml
│   ├── SystemStats.qml
│   ├── Media.qml
│   ├── Network.qml
│   ├── Volume.qml
│   ├── Battery.qml
│   └── WindowTitle.qml
└── assets/
```

---

## Goals

- [x] **Lightweight**
- [x] **Fully modular**
- [x] **Smooth animations**
- [x] **Easy customization**
- [x] **Modern Wayland aesthetics**

---

## Contributing

Pull requests, ideas, and improvements are welcome.

If you contribute:
- Keep modules clean & modular
- Preserve the minimal aesthetic
- Avoid unnecessary dependencies

---

## License

Licensed under the **[MIT License](LICENSE)**.

> Use it, modify it, break it, rebuild it, i dont give a fuck.

<br>

<div align="center">
<i>Built for the Hyprland community</i><br>
<b>Manually programmed by Enzo</b><br>
<b>Enjoy</b>
</div>
