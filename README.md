# What is kconst?
<img width="762" height="692" alt="image" src="https://github.com/user-attachments/assets/80c5beac-3d88-4d0e-8dad-995734e130e4" />
<br>
kconst is a convenient Bash command-line tool that helps you easily inspect compile-time constants (#define macros) from Linux kernel header files. It extracts "magic numbers", syscall numbers, flags, etc. defined in kernel headers such as linux/magic.h, asm/unistd.h, etc., and displays them in a clean, colored, human-readable format.

# Main Features
Default behavior: Scans four useful kernel headers by default:
<ul>
  <li>linux/magic.h</li>
  <li>linux/sysrq.h</li>
  <li>linux/reboot.h</li>
  <li>asm/unistd.h</li>
</ul>

# Options:
<ul>
  <li>--all → Scan all .h files under /usr/include/linux/</li>
  <li>--filter PATTERN or -f → Show only constants matching a pattern (case-insensitive)</li>
  <li>--sort name|value → Sort output by constant name (default) or by numeric value</li>
  <li>--hex-only → Minimal output: just NAME and HEX value (great for scripting)</li>
  <li>--root PATH → Use a custom include directory (default: /usr/include)</li>
  <li>--no-color → Disable colored output</li>
</ul>

# How it works
1. Uses grep to find #define lines that look like constants.
2. Uses the C preprocessor (cpp) to evaluate/expand each constant (handles complex expressions, bitwise ops, etc.).
3. Filters out non-numeric values, function-like macros, and internal __xxx__ defines.
4. Displays nicely formatted output with:
     Header file name
     Constant name (bold)
     Hex value (yellow)
     Decimal value (green)
     Fancy box-drawing borders when not in --hex-only mode

# Example usage
<img width="2968" height="1132" alt="image" src="https://github.com/user-attachments/assets/6e4e0ce8-ab92-434e-87b5-775bea27efc0" />

# Purpose
This tool is especially useful for:
Kernel/module developers
Reverse engineers
Security researchers
Anyone who frequently needs to look up kernel magic numbers, flags, or syscall values without manually digging through header files.

# Installation
1. Download kconst.sh
2. Open a terminal, go to the directory you downloaded kconst.sh and run `sudo install -m 755 kconst.sh /usr/local/bin/kconst`
3. Now it should work with `bash /usr/local/bin/kconst --all`
4. You can add an aliash to your ~/.bashrc file if you want to call `kconst` command at any time.



