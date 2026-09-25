# tenant-allow-block-list
This repository is for testing the limits of tenant allow and block list in Microsoft Defender for XDR

## Usage

### 1. Connect to Exchange Online

In devcontainers/headless environments there is no browser available for interactive sign-in, so
connect using the device code flow with the `-Device` switch. This prints a URL and a code that
you open/enter in a browser on your host machine instead of launching one inside the container:

```powershell
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -Device
```

### 2. Add entries

```powershell
# Add 5000 sender block entries (default count)
./allow-block-list-demo.ps1 -Operation Add -EntryAction Block -ListType Sender

# Add 5001 sender block entries to test the tenant limit
./allow-block-list-demo.ps1 -Operation Add -EntryAction Block -ListType Sender -Count 5001

# Add 10 URL block entries without making any changes (dry run)
./allow-block-list-demo.ps1 -Operation Add -EntryAction Block -ListType Url -Count 10 -TestOnly
```

### 3. Delete entries

Use the same `-EntryAction`, `-ListType`, `-Count` and `-StartIndex`/`-Prefix` values used when
adding, so the deterministic entry names match:

```powershell
./allow-block-list-demo.ps1 -Operation Delete -EntryAction Block -ListType Sender -Count 5001
```
