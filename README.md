# Mac Cleaner

[![Gem Version](https://badge.fury.io/rb/mac_cleaner.svg)](https://badge.fury.io/rb/mac_cleaner)

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/ojisanchamchi)

A script to clean your Mac and analyze disk space.

## Installation

### From RubyGems

```bash
gem install mac_cleaner
```

### From the `.gem` file

```bash
gem install ./mac_cleaner-1.2.2.gem
```

### From the git repository

```bash
git clone https://github.com/ojisanchamchi/mac_cleaner.git
cd mac_cleaner
rake install
```

## Usage

### Clean up your Mac

```bash
mac_cleaner clean
```

#### Options

*   `--dry-run`, `-n`: Perform a dry run without deleting files.
*   `--sudo`: Run with sudo for system-level cleanup.
*   `--interactive`, `-i`: Review each section and choose what to clean before anything runs.

### Check the current version

```bash
mac_cleaner --version
```

### Analyze disk space

```bash
mac_cleaner analyze [PATH]
```

#### Arguments

*   `PATH`: The path to analyze. Defaults to `~`.
