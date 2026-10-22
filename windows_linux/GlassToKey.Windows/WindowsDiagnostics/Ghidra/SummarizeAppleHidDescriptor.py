"""Read embedded HID descriptor collections from the inspected Apple 6.1.8000.6 drivers.

This parses only PE section mapping and HID item structure. It never opens a device.
"""

import argparse
import pathlib
import struct


def read_rva(data: bytes, rva: int, length: int) -> bytes:
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    section_offset = pe + 24 + optional_size
    for index in range(count):
        offset = section_offset + index * 40
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
            "<IIII", data, offset + 8
        )
        if virtual_address <= rva and rva + length <= virtual_address + raw_size:
            start = raw_offset + rva - virtual_address
            return data[start : start + length]
    raise ValueError(f"RVA 0x{rva:x} length {length} is not file-backed")


def summarize(descriptor: bytes) -> list[dict]:
    page = 0
    report_id = 0
    report_size = 0
    report_count = 0
    globals_stack = []
    local_usage = None
    collections = []
    depth = 0
    current_top = None
    index = 0
    while index < len(descriptor):
        prefix = descriptor[index]
        index += 1
        if prefix == 0xFE:
            size = descriptor[index]
            index += 2 + size
            continue
        size_code = prefix & 3
        size = 4 if size_code == 3 else size_code
        payload = descriptor[index : index + size]
        if len(payload) != size:
            raise ValueError("truncated HID item")
        value = int.from_bytes(payload, "little")
        index += size
        kind = (prefix >> 2) & 3
        tag = (prefix >> 4) & 15
        if kind == 1:
            if tag == 0:
                page = value
            elif tag == 8:
                report_id = value
                if current_top is not None:
                    current_top["report_ids"].add(report_id)
            elif tag == 7:
                report_size = value
            elif tag == 9:
                report_count = value
            elif tag == 10:
                globals_stack.append((page, report_id, report_size, report_count))
            elif tag == 11:
                page, report_id, report_size, report_count = globals_stack.pop()
        elif kind == 2 and tag == 0:
            local_usage = value
        elif kind == 0:
            if tag == 10:
                if depth == 0:
                    usage = local_usage if local_usage is not None else 0
                    usage_page = usage >> 16 if usage > 0xFFFF else page
                    current_top = {
                        "page": usage_page,
                        "usage": usage & 0xFFFF,
                        "type": value,
                        "report_ids": set(),
                        "input_bits": {},
                    }
                    collections.append(current_top)
                depth += 1
            elif tag == 12:
                depth -= 1
                if depth < 0:
                    raise ValueError("unbalanced HID collection end")
                if depth == 0:
                    current_top = None
            elif tag in (8, 9, 11) and current_top is not None:
                current_top["report_ids"].add(report_id)
                if tag == 8:
                    bits = current_top["input_bits"]
                    bits[report_id] = bits.get(report_id, 0) + report_size * report_count
            local_usage = None
    if depth != 0:
        raise ValueError("unclosed HID collection")
    return collections


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("driver", type=pathlib.Path)
    parser.add_argument("--transport", choices=("usb", "bluetooth"), required=True)
    args = parser.parse_args()
    rva, length = (0x6040, 835) if args.transport == "usb" else (0x73C0, 835)
    descriptor = read_rva(args.driver.read_bytes(), rva, length)
    print(f"{args.driver.name}: embedded descriptor RVA 0x{rva:x}, {length} bytes")
    for collection in summarize(descriptor):
        ids = ",".join(f"0x{value:02x}" for value in sorted(collection["report_ids"]))
        print(
            f"page=0x{collection['page']:04x} usage=0x{collection['usage']:04x} "
            f"type=0x{collection['type']:02x} report_ids={ids} "
            f"input_bits={collection['input_bits']}"
        )


if __name__ == "__main__":
    main()
