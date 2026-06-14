# Bypass MDM for macOS

Forked from [assafdori/bypass-mdm](https://github.com/assafdori/bypass-mdm) and extended with safer support for macOS installations on external drives.

Use only on Macs you own or are explicitly authorized to manage.

## Features

### Basic

- Runs from macOS Recovery
- Creates a temporary administrator account
- Validates usernames, passwords, paths, and available UIDs
- Blocks MDM enrollment domains and configures setup markers
- Provides clear errors and avoids duplicate entries

### External Drive Support

- Detects mounted APFS volumes by their real System and Data roles
- Lists only System volumes; Data volumes cannot be selected manually
- Shows Internal/External labels
- Uses Up/Down arrow keys and Enter for all fixed choices
- Automatically binds the matching Data volume by APFS Volume Group ID
- `--require-external` prevents changes to an internal macOS installation
- `--validate-only` checks the selected volume pair without making changes
- Never renames System or Data volumes
- Revalidates the selected volume pair before writing

## Usage

Boot into macOS Recovery, connect to the internet, open Terminal, and run:

```bash
curl -fL https://raw.githubusercontent.com/prestige12138/bypass-mdm-external/main/bypass-mdm-v2.sh -o bypass-mdm.sh && chmod +x bypass-mdm.sh && ./bypass-mdm.sh --require-external
```

Select the external System volume with the Up/Down arrow keys and press Enter. The matching Data volume is selected automatically.

```text
   Macintosh HD [Internal]
 > GoldenGate [External]
```

Validate without making changes:

```bash
./bypass-mdm.sh --require-external --validate-only
```

To allow selecting either an internal or external installation, omit `--require-external`.

## Requirements

- macOS Recovery Terminal
- Mounted APFS System and Data volumes
- Internet access when downloading with `curl`
- Authorization to modify the selected Mac

## License

Released under the MIT License. The original copyright and permission notice are preserved in [LICENSE](LICENSE).
