#!/usr/bin/env python3
"""Launch native VICE, using a LaunchServices app context for macOS GTK.

The generated .app is only a launcher for the installed x64sc executable.
The C64 PRG itself is platform-independent. No emulator is bundled.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("program", type=Path)
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--model", choices=("pal", "ntsc", "oldntsc"), default="pal")
    parser.add_argument("--sid", choices=("6581", "8580"), default="6581")
    parser.add_argument("--monitor-port", type=int)
    args = parser.parse_args()
    executable = shutil.which(args.vice)
    if not executable:
        parser.error(f"VICE executable not found: {args.vice}")
    program = args.program.resolve()
    if not program.is_file():
        parser.error(f"PRG not found: {program}")
    models = {"pal": "c64", "ntsc": "ntsc", "oldntsc": "oldntsc"}
    command = [executable, "-default", "-model", models[args.model],
               "-sidmodel", "0" if args.sid == "6581" else "1",
               "-autostartprgmode", "1", "-autostart", str(program)]
    if program.suffix.lower() == ".d64":
        command += ["-drive8type", "1541", "-drive8truedrive", "+trapdevice8"]
    if args.monitor_port:
        if not 1024 <= args.monitor_port < 65536:
            parser.error("monitor port must be 1024..65535")
        command += ["-binarymonitor", "-binarymonitoraddress",
                    f"ip4://127.0.0.1:{args.monitor_port}", "-refreshonbreak"]
    output = (Path("build") / ("dance" if program.stem == "nocturne" else program.stem)).resolve()
    output.mkdir(parents=True, exist_ok=True)
    label = f"C64 {program.stem.title()} {args.model.upper()}"
    if sys.platform == "darwin":
        compiler = shutil.which("clang")
        if not compiler:
            parser.error("macOS launcher needs clang (Xcode Command Line Tools)")
        bundle = output / (label + ".app")
        contents = bundle / "Contents"
        binary = contents / "MacOS" / "launcher"
        binary.parent.mkdir(parents=True, exist_ok=True)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleDisplayName": label, "CFBundleName": label,
                          "CFBundleExecutable": "launcher",
                          "CFBundleIdentifier": f"local.c64.{program.stem}.{args.model}",
                          "CFBundlePackageType": "APPL", "CFBundleVersion": "1.0"}, handle)
        literals = ",\n        ".join(json.dumps(arg) for arg in command)
        source = output / f"launcher_{args.model}.c"
        logfile = json.dumps(str(output / f"vice_{args.model}.log"))
        source.write_text("#include <stdlib.h>\n#include <unistd.h>\n#include <stdio.h>\n#include <fcntl.h>\n"
                          "int main(void) {\n    char *const args[] = {\n        "
                          + literals + ",\n        NULL};\n"
                          + f"    int logfd = open({logfile}, O_WRONLY | O_CREAT | O_APPEND, 0644);\n"
                          '    if (logfd >= 0) { dup2(logfd, 1); dup2(logfd, 2); close(logfd); }\n'
                          '    setenv("GDK_BACKEND", "quartz", 1);\n'
                          '    execv(args[0], args);\n    perror("x64sc");\n    return 127;\n}\n')
        subprocess.run([compiler, str(source), "-o", str(binary)], check=True)
        subprocess.run(["open", "-n", str(bundle)], check=True)
    else:
        log = (output / f"vice_{args.model}.log").open("ab")
        subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True)
        log.close()
    print(f"Launched {label}; {program}")


if __name__ == "__main__":
    main()
