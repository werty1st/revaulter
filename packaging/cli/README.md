# revaulter-cli + ZFS boot-unlock

Unlocks `keyformat=passphrase` ZFS datasets at boot: the passphrase is wrapped by
a Revaulter server (stored on disk only as an encrypted JSON envelope), and at
boot a systemd unit asks a passkey holder to approve the unwrap, then pipes the
plaintext passphrase straight into `zfs load-key` - it is never written to disk.

## Install

On the ZFS host:

```sh
wget https://vault.vpnpro.eu/revaulter-cli.deb
sudo apt install ./revaulter-cli.deb
```

(add `--no-check-certificate` to `wget` for a self-signed cert)

The server URL is already set in `/etc/revaulter/cli/config`. Add your request
key (from the Revaulter web UI):

```sh
sudoedit /etc/revaulter/cli/config      # REVAULTER_REQUEST_KEY="rvk_..."
```

## Register a dataset

For an existing encrypted dataset (`keyformat=passphrase`):

```sh
sudo revaulter-zfs-setup z1pool32tb/encrypted
```

You are prompted for the dataset's current passphrase. The script then:

1. pins the server anchor into `/etc/revaulter/cli/trust.json` (first run only)
2. wraps the passphrase via Revaulter -> `/etc/revaulter/keys/<dataset>.json`
3. verifies it against the dataset with a dry-run `zfs load-key -n`
4. enables `revaulter-zfs-unlock@<escaped-dataset>.service`

Each step needs a passkey approval in the web UI.

To also create the dataset with a fresh random passphrase, add `--create`:

```sh
sudo revaulter-zfs-setup --create z1pool32tb/encrypted
```

Test without rebooting:

```sh
sudo systemctl start revaulter-zfs-unlock@z1pool32tb-encrypted.service
```

`load-key` / `unload-key` run recursively and mounting is `zfs mount -a`, so one
instance covers a whole encryption-root tree.

## Retry behaviour at boot

The unit never fails. `revaulter-zfs-unlock` retries internally until the request
is approved, so a single start can legitimately stay `activating` for hours and
`systemctl status` shows every attempt in the journal. That is deliberate: units
that depend on the dataset can safely use `Requires=` / `x-systemd.requires=`,
because a *failing* unit would cancel their jobs and a later successful restart is
a new transaction that would not revive them.

One new approval request goes out roughly every
`REVAULTER_UNLOCK_TIMEOUT + REVAULTER_UNLOCK_RETRY_DELAY` seconds (default ~16 min).
Tune both in `/etc/revaulter/cli/config` — a long unattended outage queues up one
notification per round.

## Files

| Path | Purpose |
|------|---------|
| `/usr/bin/revaulter-cli` | the CLI |
| `/usr/bin/revaulter-zfs-setup` | register a dataset (see above) |
| `/usr/bin/revaulter-zfs-unlock` | run by the unit at boot |
| `/lib/systemd/system/revaulter-zfs-unlock@.service` | templated unit, `%I` = dataset |
| `/etc/revaulter/cli/config` | conffile: server URL (pre-set) + request key |
| `/etc/revaulter/cli/trust.json` | pinned anchor (created by setup) |
| `/etc/revaulter/keys/<dataset>.json` | wrapped passphrase envelope, safe on unencrypted disk |

Services that need the dataset should declare
`Requires=revaulter-zfs-unlock@<esc>.service` and `After=...`.

`apt purge revaulter-cli` removes `/etc/revaulter/cli` and `/etc/revaulter/keys` -
back up your envelopes first if you still need them.
