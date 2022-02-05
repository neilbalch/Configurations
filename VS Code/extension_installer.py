#!/usr/bin/python3
import subprocess

# VSCode Extension Installer
# - Batch installs a list of VSCode extensions from the VSCode marketplace
#   specified in the (relative) file path specified by EXTENSIONS_FILE
# - Extension names expected to be formatted like the output of the command:
#   `code --list-extensions`
# - Create this list from an already initialized VSCode environment using these
#   instructions: https://stackoverflow.com/a/49398449/3339274
EXTENSIONS_FILE = "extensions_list.txt"

# Required (primarily) because Powershell on Windows saves to 'UTF-16 LE` when
# using the `> FILENAME` syntax and Python expects `UTF-8` by default
# https://stackoverflow.com/a/33981557/3339274
def guess_encoding(csv_file):
    """guess the encoding of the given file"""
    import io
    import locale
    with io.open(csv_file, "rb") as f:
        data = f.read(5)
    if data.startswith(b"\xEF\xBB\xBF"):  # UTF-8 with a "BOM"
        return "utf-8-sig"
    elif data.startswith(b"\xFF\xFE") or data.startswith(b"\xFE\xFF"):
        return "utf-16"
    else:  # in Windows, guessing utf-8 doesn't work, so we have to try
        try:
            with io.open(csv_file, encoding="utf-8") as f:
                preview = f.read(222222)
                return "utf-8"
        except:
            return locale.getdefaultlocale()[1]

with open(EXTENSIONS_FILE, "r", encoding=guess_encoding(EXTENSIONS_FILE)) as file:
  for line in file.readlines():
    # https://docs.python.org/3/library/subprocess.html#subprocess.run
    # https://github.com/minimaxir/automl-gs/issues/13#issuecomment-477102177
    output = subprocess.run(["code", "--install-extension", line[0:len(line) - 1]],
                            capture_output=True, shell=True, text=True)

    if(not output.returncode):
      print(output.stdout[0:len(output.stdout) - 1])
    else:
      print(output.stderr)
