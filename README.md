# Srunix

A Linux-like operating system for **CC:Tweaked** (Minecraft mod).
Written in pure Lua, no external dependencies.

```
 #####  ####   #   #  #   #  ###  #   #
 #      #   #  #   #  ##  #   #    # #
 #####  ####   #   #  # # #   #     #
     #  #  #   #   #  #  ##   #    # #
 #####  #   #  ### #  #   #  ###  #   #
```

## What is Srunix

Srunix is a hobby OS that tries to bring a Linux/Windows hybrid feel
to CC:Tweaked computers. It provides a full shell with users, groups,
file permissions, a virtual file system, a package manager stub, and
its own PNG/BMP image decoder — all running on pure Lua inside the game.

The project is designed to be modular: the kernel, shell, and every
userland command live in separate files, so you can add new programs
by dropping a `.lua` file into `/srunix/bin/`.

## Requirements

- Minecraft 1.21.1 (or compatible)
- NeoForge 1.20+
- [CC:Tweaked](https://modrinth.com/mod/cc-tweaked) 1.116.1+
- *(optional)* [CC:Graphics](https://modrinth.com/mod/cc-graphics) for 256-color mode
- *(optional)* [Tom's Peripherals](https://modrinth.com/mod/toms-peripherals) for GPU + keyboard

## Installation

1. Place a Computer block in Minecraft and open it.
2. In the CraftOS prompt, run:

```
wget run https://raw.githubusercontent.com/VVitek8/srunix/main/install.lua
```

3. Wait for the installer to download all system files.
4. Reboot:

```
reboot
```

You should see the Srunix boot loader, then the login prompt.
Default user is `root` (no password).

### Manual installation

If `wget` is unavailable, you can install manually:

1. Run `edit install.lua` in CraftOS.
2. Paste the contents of `install.lua` from this repository.
3. Save with **Ctrl -> Save -> Exit**.
4. Run `install`.
5. Reboot.

## Quick start

After boot you'll see a prompt like:

```
root@srunix C:\srunix\home\root>
```

Try:

```
help                    # list all commands
ls                      # list files
cd srunix               # enter system folder
pic                     # open image list
about                   # system info with ASCII art
morse "hello world"     # encode text to Morse
colorall red            # colorize ALL output
colorall reset          # back to normal
```

## File layout

```
/                       — real CC:Tweaked disk root
├── startup.lua         — auto-run on boot
├── boot/
│   └── boot.lua        — bootloader (loads kernel)
├── srunix/             — system (mounted as SYS:)
│   ├── kernel/
│   │   ├── init.lua    — kernel entry point
│   │   ├── vfs.lua     — virtual file system
│   │   ├── screen.lua  — screen buffer, scrolling, colors
│   │   ├── shell.lua   — main shell loop
│   │   ├── users.lua   — users, groups, permissions
│   │   └── utils.lua   — helpers, color tables
│   ├── bin/            — userland commands (add .lua here)
│   ├── etc/            — passwd, shadow, group, perms
│   ├── var/log/        — log files
│   └── home/           — user home directories
└── programs/           — third-party packages
```

## Adding a new command

Any `.lua` file placed in `/srunix/bin/` is automatically available
as a command. Inside it, use the `Srunix` global:

```lua
local Srunix = _G.Srunix
local SB = Srunix.SB
local args = Srunix.args or {}

SB.addLine("Hello from my command!", colors.lime)
SB.addLine("You passed: " .. table.concat(args, " "), colors.white)
```

Save as `/srunix/bin/hello.lua`, then run `hello` from the shell.

## Command overview

| Command | Description |
|---|---|
| `help [cmd]` | General help or per-command detail |
| `dir` / `ls [-l]` | List files |
| `cd [path]` | Change directory |
| `cat` / `type <file>` | Print file contents |
| `cp` / `copy` | Copy file |
| `mv` / `move` | Move / rename |
| `rm` / `del` | Delete file |
| `mkdir` / `md` | Create directory |
| `run <prog>` | Run program from `/srunix/bin/` |
| `login` / `logout` | Switch user |
| `whoami` / `id` / `users` | User info |
| `useradd` / `userdel` | Manage users (root) |
| `passwd [user]` | Change password |
| `chmod <mode> <file>` | Change permissions |
| `chown <user> <file>` | Change owner (root) |
| `pic [list/last/random/name]` | Image viewer |
| `srun [n]` | Print SRUN n times |
| `cube [size] [color] [mode]` | Rotating 3D cube |
| `textnum <word>` | Letters to number |
| `morse <text>` | Morse encode/decode |
| `colorall <color>` | Override all output color |
| `about` / `neofetch` | System info + ASCII art |
| `history [-c]` | Command history |
| `colors` | Show color palette |
| `clear` / `cls` | Clear screen |
| `exit` / `quit` | Shut down |

## Image viewer (pic)

`pic` reads images from `/images`, `/srunix/images`, or `/programs/images`.

**Supported input formats:**
- `.nfp` — native Paint format (RGB or 16-color)
- `.nft` — legacy text format
- `.png` — 8-bit RGB, RGBA, palette, grayscale (no interlacing)
- `.bmp` — 24-bit uncompressed

**PNG/BMP are decoded inside Srunix** — no external conversion needed.
Decoding takes a few seconds for a 480×270 image. Larger images may
be slow or run out of memory; recommended source size is **480×270**.

**GPU acceleration.** If Tom's Peripherals is installed, `pic` uses
its GPU for 24-bit RGB rendering. Otherwise it falls back to
CC:Graphics 256-color mode, then to standard 16-color text mode.

## Design notes

- **No coroutines for multitasking.** Instead of a hand-rolled
  scheduler, Srunix uses CC:Tweaked's `parallel.waitForAny` — it
  handles event yielding correctly, including inside `pcall`.
- **The VFS is a security boundary.** Programs that go through
  `VFS.read` / `VFS.write` are checked. Programs that use the raw
  `fs` API bypass this — but the shell never passes `fs` into the
  user environment, so well-behaved programs stay sandboxed.
- **Colored output, everywhere.** The screen buffer stores colored
  segments, so word wrapping preserves per-character colors.
  A global `colorOverride` lets the `colorall` command recolor
  absolutely everything on screen.

## Status

This is a hobby project — incomplete, opinionated, and evolving.
Some things work, some don't. The code is not battle-tested.
Contributions and ideas are welcome.

## License

MIT — see `LICENSE`.

## Credits

- **CC:Tweaked** — the mod that makes this possible
- **CC:Graphics** — 256-color support
- **Tom's Peripherals** — GPU + keyboard
- **Basalt2** — inspiration for future GUI work
