# zpz: An Amstrad CPC emulator frontend written in zig using https://github.com/floooh/chips

<p align="center">
  <img width="385" src="demo-cpc6128.gif">
</p>

`zpz` is an emulator frontend (basically just some zig glue code) that uses
`https://github.com/floooh/chips` to emulate an Amstrad CPC 6128.

I really encourage you to check out https://github.com/floooh/chips for a very
clean and understandable CPC emulator code base.

# Build

The repository https://github.com/floooh/chips must be checked out in the parent
folder.

⚠️ For now, a particular branch must be checked out for `zpz` to compile:
```bash
git clone -b cpc-two-drives git@github.com:LukeSkyw/chips.git
```

Then, in `zpz` folder:
```bash
zig build
```

For best performance:
```bash
zig build -Drelease-fast
```

# Usage

To launch:
```bash
./zig-out/bin/zpz6128
```

To load one or two disks, pass the `dsk` file path in the command line:
```bash
./zig-out/bin/zpz6128 /path/to/some.dsk /another/path.dsk
```
