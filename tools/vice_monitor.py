#!/usr/bin/env python3
"""Small, loopback-only VICE binary monitor client (Python standard library).

Start VICE with ``-binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502``.
Every request enters the monitor and pauses emulation; call ``resume()`` when
finished. The CLI resumes after inspection/capture unless ``--leave-paused``.

Protocol: https://vice-emu.sourceforge.io/vice_13.html
Display layout checked against the official monitor_binary.c implementation:
https://github.com/VICE-Team/svn-mirror/blob/main/vice/src/monitor/monitor_binary.c
The display is VICE's rasterized indexed framebuffer, including sprites. It is
not reconstructed from C64 RAM. Its colors come from VICE's palette response.
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
import ipaddress
import json
from pathlib import Path
import socket
import struct
import sys
import time
import zlib


EVENT_ID = 0xFFFFFFFF
MAX_BODY = 16 * 1024 * 1024
ERROR_NAMES = {
    0x01: "object missing",
    0x02: "invalid memory space",
    0x80: "invalid command length",
    0x81: "invalid parameter",
    0x82: "invalid API version",
    0x83: "invalid command type",
    0x8F: "command failed",
}


class MonitorError(RuntimeError):
    """A protocol violation or error returned by VICE."""


@dataclass(frozen=True)
class Response:
    type: int
    error: int
    request_id: int
    body: bytes


def _items(body: bytes):
    """Decode a counted array whose entries each have a one-byte length."""
    if len(body) < 2:
        raise MonitorError("truncated array count")
    count = struct.unpack_from("<H", body)[0]
    offset = 2
    for _ in range(count):
        if offset >= len(body):
            raise MonitorError("truncated array item size")
        size = body[offset]
        offset += 1
        if offset + size > len(body):
            raise MonitorError("truncated array item")
        yield body[offset:offset + size]
        offset += size
    if offset != len(body):
        raise MonitorError("unexpected trailing bytes in array")


def _chunk(kind: bytes, content: bytes) -> bytes:
    return (struct.pack(">I", len(content)) + kind + content
            + struct.pack(">I", zlib.crc32(kind + content) & 0xFFFFFFFF))


@dataclass(frozen=True)
class DisplayFrame:
    width: int
    height: int
    x_offset: int
    y_offset: int
    inner_width: int
    inner_height: int
    bits_per_pixel: int
    pixels: bytes
    palette: tuple[tuple[int, int, int], ...]
    overscan_padding: int = 0

    def save_png(self, path: str | Path, *, inner: bool = False) -> None:
        """Save raw emulator pixels, optionally cropping the 320×200 inner area."""
        if inner:
            x, y = self.x_offset, self.y_offset
            width, height = self.inner_width, self.inner_height
        else:
            x, y, width, height = 0, 0, self.width, self.height
        if not (width > 0 and height > 0 and x + width <= self.width
                and y + height <= self.height):
            raise MonitorError("invalid framebuffer crop")
        if not self.palette or len(self.palette) > 256:
            raise MonitorError("invalid 8-bit palette")
        if any(index >= len(self.palette) for index in self.pixels):
            raise MonitorError("framebuffer uses an index outside its palette")
        scanlines = bytearray()
        for row in range(y, y + height):
            start = row * self.width + x
            scanlines.append(0)  # PNG filter: none
            scanlines.extend(self.pixels[start:start + width])
        header = struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)
        palette = bytes(component for color in self.palette for component in color)
        png = (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", header)
               + _chunk(b"PLTE", palette)
               + _chunk(b"IDAT", zlib.compress(scanlines, 9))
               + _chunk(b"IEND", b""))
        Path(path).write_bytes(png)

    def metadata(self) -> dict:
        return {
            "debug_width": self.width, "debug_height": self.height,
            "x_offset": self.x_offset, "y_offset": self.y_offset,
            "inner_width": self.inner_width, "inner_height": self.inner_height,
            "bits_per_pixel": self.bits_per_pixel,
            "buffer_length": len(self.pixels),
            "palette_colors": len(self.palette),
            "used_color_indices": sorted(set(self.pixels)),
            "overscan_padding_bytes": self.overscan_padding,
        }


class ViceMonitor:
    """Synchronous client; unsolicited events are queued, never lost as replies."""

    def __init__(self, host: str = "127.0.0.1", port: int = 6502,
                 timeout: float = 5.0):
        if host == "localhost":
            host = "127.0.0.1"
        try:
            address = ipaddress.ip_address(host)
        except ValueError as exc:
            raise ValueError("use a loopback IP literal or localhost") from exc
        if not address.is_loopback:
            raise ValueError("VICE monitor connections must be loopback only")
        if not (0 < port < 65536 and timeout > 0):
            raise ValueError("invalid port or timeout")
        self.socket = socket.create_connection((host, port), timeout)
        self.timeout = timeout
        self.events: deque[Response] = deque(maxlen=1024)
        self._request_id = 0
        self._register_info: dict[int, dict[int, tuple[str, int]]] = {}
        self.paused: bool | None = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        self.socket.close()

    def _read_exact(self, length: int, deadline: float) -> bytes:
        result = bytearray()
        while len(result) < length:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("VICE monitor response timed out")
            self.socket.settimeout(remaining)
            block = self.socket.recv(length - len(result))
            if not block:
                raise ConnectionError("VICE closed the binary monitor connection")
            result.extend(block)
        return bytes(result)

    def _receive(self, deadline: float) -> Response:
        header = self._read_exact(12, deadline)
        stx, version, length, kind, error, request_id = struct.unpack("<BBIBBI", header)
        if stx != 2 or version != 2:
            raise MonitorError(f"unexpected response header: {header.hex()}")
        if length > MAX_BODY:
            raise MonitorError(f"response body too large: {length}")
        result = Response(kind, error, request_id, self._read_exact(length, deadline))
        if kind in (0x61, 0x62):
            self.paused = True
        elif kind == 0x63:
            self.paused = False
        return result

    def request(self, command: int, body: bytes = b"", *,
                response_type: int | None = None) -> Response:
        """Send one command, collecting events until the matching reply arrives."""
        if len(body) > MAX_BODY:
            raise ValueError("command body too large")
        self._request_id = (self._request_id + 1) % EVENT_ID
        request_id = self._request_id
        packet = struct.pack("<BBIIB", 2, 2, len(body), request_id, command) + body
        deadline = time.monotonic() + self.timeout
        self.socket.settimeout(self.timeout)
        self.socket.sendall(packet)
        while True:
            response = self._receive(deadline)
            if response.request_id == EVENT_ID:
                self.events.append(response)
                continue
            if response.request_id != request_id:
                raise MonitorError(f"unexpected response ID {response.request_id}, expected {request_id}")
            if response.error:
                reason = ERROR_NAMES.get(response.error, "unknown error")
                raise MonitorError(f"VICE command ${command:02x}: {reason} (${response.error:02x})")
            expected = command if response_type is None else response_type
            if response.type != expected:
                raise MonitorError(f"response type ${response.type:02x}, expected ${expected:02x}")
            return response

    def wait_event(self, kind: int | None = None, timeout: float | None = None) -> Response:
        """Wait for a queued/new asynchronous event, e.g. STOPPED (0x62)."""
        for event in self.events:
            if kind is None or event.type == kind:
                self.events.remove(event)
                return event
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        while True:
            event = self._receive(deadline)
            if event.request_id != EVENT_ID:
                raise MonitorError("unexpected command reply while waiting for an event")
            if kind is None or event.type == kind:
                return event
            self.events.append(event)

    def memread(self, address: int, length: int, *, bank: int | str = 0,
                memspace: int = 0, side_effects: bool = False) -> bytes:
        if not (length > 0 and 0 <= address and address + length <= 65536):
            raise ValueError("memory range must fit the 16-bit address space")
        if isinstance(bank, str):
            available = self.banks()
            if bank not in available:
                raise ValueError(f"unknown memory bank {bank!r}; available: {list(available)}")
            bank = available[bank]
        body = struct.pack("<BHHBH", side_effects, address, address + length - 1, memspace, bank)
        reply = self.request(0x01, body).body
        if len(reply) < 2:
            raise MonitorError("truncated memory response")
        size = struct.unpack_from("<H", reply)[0] or 65536
        if size != length or len(reply) != length + 2:
            raise MonitorError("memory response length does not match request")
        return reply[2:]

    def memwrite(self, address: int, data: bytes, *, bank: int = 0,
                 memspace: int = 0, side_effects: bool = False):
        if not (data and 0 <= address and address + len(data) <= 65536):
            raise ValueError("memory range must fit the 16-bit address space")
        body = struct.pack("<BHHBH", side_effects, address, address + len(data) - 1, memspace, bank)
        self.request(0x02, body + data)

    def banks(self) -> dict[str, int]:
        result = {}
        for item in _items(self.request(0x82).body):
            if len(item) < 3 or len(item) != 3 + item[2]:
                raise MonitorError("invalid bank descriptor")
            result[item[3:].decode("ascii")] = struct.unpack_from("<H", item)[0]
        return result

    def register_info(self, memspace: int = 0) -> dict[int, tuple[str, int]]:
        if memspace not in self._register_info:
            descriptors = {}
            for item in _items(self.request(0x83, bytes([memspace])).body):
                if len(item) < 3 or len(item) != 3 + item[2]:
                    raise MonitorError("invalid register descriptor")
                descriptors[item[0]] = (item[3:].decode("ascii"), item[1])
            self._register_info[memspace] = descriptors
        return self._register_info[memspace]

    def registers(self, memspace: int = 0) -> dict[str, int]:
        descriptors = self.register_info(memspace)
        return self._decode_registers(self.request(0x31, bytes([memspace])).body, descriptors)

    @staticmethod
    def _decode_registers(body: bytes, descriptors: dict) -> dict[str, int]:
        result = {}
        for item in _items(body):
            if len(item) < 3:
                raise MonitorError("truncated register value")
            name = descriptors.get(item[0], (f"ID_{item[0]}", 16))[0]
            result[name] = struct.unpack_from("<H", item, 1)[0]
        return result

    def set_registers(self, values: dict[str, int], memspace: int = 0):
        by_name = {name.upper(): (regid, bits)
                   for regid, (name, bits) in self.register_info(memspace).items()}
        body = bytearray(struct.pack("<BH", memspace, len(values)))
        for name, value in values.items():
            if name.upper() not in by_name:
                raise ValueError(f"unknown register {name!r}")
            regid, bits = by_name[name.upper()]
            if not (0 <= value < (1 << min(bits, 16))):
                raise ValueError(f"value out of range for {name}")
            body.extend(struct.pack("<BBH", 3, regid, value))
        self.request(0x32, bytes(body), response_type=0x31)

    def resume(self):
        self.request(0xAA)
        self.paused = False

    exit = resume

    def execute_text(self, command: str):
        raise NotImplementedError(
            "VICE binary API has no textual execute command; use binary operations "
            "or launch VICE with -moncommands for monitor scripts")

    def resource_get(self, name: str) -> str | int:
        encoded = name.encode("ascii")
        if not (0 < len(encoded) <= 255):
            raise ValueError("resource name must contain 1 to 255 ASCII bytes")
        body = self.request(0x51, bytes([len(encoded)]) + encoded).body
        if len(body) < 2 or len(body) != body[1] + 2:
            raise MonitorError("invalid resource response")
        if body[0] == 0:
            return body[2:].decode("utf-8")
        if body[0] == 1:
            return int.from_bytes(body[2:], "little")
        raise MonitorError("unknown resource type")

    def resource_set(self, name: str, value: int | str):
        encoded = name.encode("ascii")
        if not (0 < len(encoded) <= 255):
            raise ValueError("resource name must contain 1 to 255 ASCII bytes")
        if isinstance(value, int):
            kind, data = 1, struct.pack("<I", value & 0xFFFFFFFF)
        else:
            kind, data = 0, value.encode("utf-8")
        if not (0 < len(data) <= 255):
            raise ValueError("resource value must contain 1 to 255 bytes")
        self.request(0x52, bytes([kind, len(encoded)]) + encoded + bytes([len(data)]) + data)

    def checkpoint(self, start: int, end: int | None = None, *,
                   operation: int = 4, stop: bool = True, temporary: bool = False,
                   memspace: int = 0) -> int:
        end = start if end is None else end
        if not (0 <= start <= end <= 0xFFFF):
            raise ValueError("invalid checkpoint address range")
        body = struct.pack("<HHBBBBB", start, end, stop, 1, operation, temporary, memspace)
        reply = self.request(0x12, body, response_type=0x11).body
        if len(reply) < 4:
            raise MonitorError("truncated checkpoint response")
        return struct.unpack_from("<I", reply)[0]

    def delete_checkpoint(self, number: int):
        self.request(0x13, struct.pack("<I", number))

    def condition(self, number: int, expression: str):
        encoded = expression.encode("ascii")
        if len(encoded) > 255:
            raise ValueError("checkpoint condition exceeds 255 bytes")
        self.request(0x22, struct.pack("<IB", number, len(encoded)) + encoded)

    def palette_get(self, use_vic: bool = True) -> tuple[tuple[int, int, int], ...]:
        colors = []
        for item in _items(self.request(0x91, bytes([use_vic])).body):
            if len(item) < 3:
                raise MonitorError("truncated palette entry")
            colors.append(tuple(item[:3]))
        return tuple(colors)

    def display_get(self, use_vic: bool = True) -> DisplayFrame:
        body = self.request(0x84, bytes([use_vic, 0])).body
        if len(body) < 21:
            raise MonitorError("truncated display metadata")
        fields_length = struct.unpack_from("<I", body)[0]
        if fields_length < 13 or len(body) < fields_length + 8:
            raise MonitorError("invalid display metadata length")
        width, height, x, y, inner_width, inner_height, bpp = struct.unpack_from("<6HB", body, 4)
        buffer_length = struct.unpack_from("<I", body, 4 + fields_length)[0]
        pixels = body[8 + fields_length:]
        if (bpp != 8 or not width or not height or buffer_length != width * height):
            raise MonitorError("invalid indexed framebuffer dimensions or length")
        if x + inner_width > width or y + inner_height > height:
            raise MonitorError("inner framebuffer exceeds debug dimensions")
        padding = buffer_length - len(pixels)
        if padding:
            # VICE 3.10 can understate the response body by four bytes: it writes
            # FL + 13 metadata bytes + BL + pixels, but transmits only 17+pixels.
            # Accept that exact release bug only when the absent last four
            # pixels lie beyond the inner picture in debug overscan. Never
            # synthesize visible C64 pixels; annotate the padded debug margin.
            if (padding != 4 or width < 4
                    or (y + inner_height >= height and x + inner_width > width - 4)):
                raise MonitorError("truncated indexed framebuffer")
            pixels += bytes(padding)
        return DisplayFrame(width, height, x, y, inner_width, inner_height,
                            bpp, pixels, self.palette_get(use_vic), padding)

    def capture_png(self, path: str | Path, *, inner: bool = False) -> DisplayFrame:
        frame = self.display_get()
        frame.save_png(path, inner=inner)
        return frame


def _integer(text: str) -> int:
    return int(text[1:], 16) if text.startswith("$") else int(text, 0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6502)
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("--leave-paused", action="store_true", help="keep VICE stopped after inspection")
    actions = parser.add_subparsers(dest="action", required=True)
    read = actions.add_parser("memory", help="read C64 memory without device side effects")
    read.add_argument("address", type=_integer)
    read.add_argument("length", type=_integer)
    read.add_argument("--bank", default="cpu", help="VICE bank name or integer ID")
    read.add_argument("--output", type=Path, help="write raw bytes")
    actions.add_parser("registers")
    actions.add_parser("banks")
    capture = actions.add_parser("capture", help="capture VICE's actual rasterized framebuffer")
    capture.add_argument("path", type=Path)
    capture.add_argument("--inner", action="store_true", help="crop borders to the inner display")
    actions.add_parser("resume")
    args = parser.parse_args()
    try:
        with ViceMonitor(args.host, args.port, args.timeout) as monitor:
            try:
                if args.action == "memory":
                    try:
                        bank = _integer(args.bank)
                    except ValueError:
                        bank = args.bank
                    memory = monitor.memread(args.address, args.length, bank=bank)
                    if args.output:
                        args.output.write_bytes(memory)
                    else:
                        for offset in range(0, len(memory), 16):
                            print(f"{args.address + offset:04x}: {memory[offset:offset + 16].hex(' ')}")
                elif args.action == "registers":
                    print(json.dumps(monitor.registers(), indent=2))
                elif args.action == "banks":
                    print(json.dumps(monitor.banks(), indent=2))
                elif args.action == "capture":
                    frame = monitor.capture_png(args.path, inner=args.inner)
                    print(json.dumps({"path": str(args.path), **frame.metadata()}, indent=2))
                elif args.action == "resume":
                    monitor.resume()
            finally:
                if not args.leave_paused and args.action != "resume":
                    monitor.resume()
    except (OSError, MonitorError, ValueError) as exc:
        print(f"vice_monitor: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
