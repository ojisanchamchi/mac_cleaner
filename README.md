# Mac Cleaner

A script to clean your Mac and analyze disk space.

## Installation

### From RubyGems

```bash
gem install mac_cleaner
```

### From the `.gem` file

```bash
gem install ./mac_cleaner-1.0.0.gem
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

### Analyze disk space

```bash
mac_cleaner analyze [PATH]
```

#### Arguments

*   `PATH`: The path to analyze. Defaults to `~`.
