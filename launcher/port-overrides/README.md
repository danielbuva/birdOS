# Fixed PortMaster overrides

## Stardew Valley

The launcher log proved that PortMaster installed the game wrapper and retail
data but not its declared Mono runtime. The exact dependency comes from the
card's own `runtimes.json` manifest:

- Source: <https://github.com/PortsMaster/PortMaster-New/releases/download/2024-02-11_0846/mono-6.12.0.122-aarch64.squashfs>
- Size: 262,057,984 bytes
- MD5: `dc7145731bf17610c13c07d6e69de550`
- Mac location: `$HOME/Games/runtimes/mono-6.12.0.122-aarch64.squashfs`
- Card location: `/MUOS/PortMaster/libs/mono-6.12.0.122-aarch64.squashfs`

`StardewValley.sh` is reduced to the fixed RG34XX-SP/muOS paths. It validates
and mounts the runtime explicitly, keeps PortMaster's patches and savedata bind,
returns the real Mono pipeline result, and performs only the cleanup this
system uses. The rebuild script re-stages this override after PortMaster
updates, but the retail game data remains outside this repository.
