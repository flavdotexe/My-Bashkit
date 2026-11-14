# FW Manager v0.2

Edits `/etc/nftables.conf` directly. No parallel managed ruleset. Requires Bash, Python 3, nftables, root and a terminal.

```bash
sudo pacman -S nftables python
sudo ./fw-manager.sh
```

Use arrows UP/DOWN, RIGHT or Enter to select, LEFT to return to main menu, Esc to quit. File edits are validated with `nft -c -f` before writing, and backed up to `/var/backups/fw-manager`. You can apply immediately after an edit or later from the Apply menu. List shows the real file; Status shows the live kernel ruleset.

**Limitations:** The simple rule editor requires a unique chain name and a chain declaration formatted as `chain NAME {` on its own line. If multiple tables have chains named `input`, it refuses to modify them. Removal supports simple rule lines only, not blocks or policy declarations. It does not understand nftables `include` trees or edit included files. `nft -c` checks syntax, not connectivity or operational safety. Applying a file containing `flush ruleset` may reset Docker/libvirt/Tailscale dynamic rules; keep a local console available. It does not automatically roll back live rules on lost connectivity. Changes made directly to the file are not automatically applied until confirmed. Do not rely on this prototype as a production firewall manager.

To test on a copy, run `sudo FW_CONF=/path/to/test.conf ./fw-manager.sh`. This still permits applying that copy to the live firewall, so **do not select Apply** when testing.
