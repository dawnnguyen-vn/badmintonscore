#!/usr/bin/env python3
"""Make bumble's android_netsim transport work with a modern Android emulator.

Run with the venv's python:  <venv>/bin/python patch-netsim.py

Two fixes, both needed against bumble 0.0.233 + emulator 37.x:

1. Wire format. Emulator ~37+ sends the raw H4 frame in PacketRequest.packet;
   bumble only accepted the structured PacketRequest.hci_packet, so it answered
   every packet with 'Unexpected request type' and no HCI ever flowed. Both
   fields already exist in bumble's bundled proto.

2. Sink leasing / emulator crash. pump_loop() leases its sink only inside the
   `initial_info` branch. This emulator streams HCI *without* sending
   initial_info, so execution fell through to the data path with sink=None and
   hit `assert self.sink is not None`. That AssertionError escapes the gRPC
   servicer, kills the stream, and aborts the emulator process (core dump).
   Fixed by leasing lazily and never asserting in a servicer.

Locates android_netsim.py through the running interpreter, so it does not care
which Python version or venv layout is in use. Restores from the .orig backup
first, so it is idempotent and safe after `pip install -U bumble`.
"""
import importlib.util, pathlib, shutil, sys

spec = importlib.util.find_spec("bumble.transport.android_netsim")
if spec is None or not spec.origin:
    sys.exit("bumble is not importable by this interpreter - run me with the venv's python")
TARGET = pathlib.Path(spec.origin)
BACKUP = TARGET.with_suffix(".py.orig")

OLD_INIT = """            self.name = None
            self.sink = None"""
NEW_INIT = """            self.name = None
            self.sink = None
            # Set once we see which packet encoding the peer speaks.
            self.raw_packets = False"""

OLD_BODY = """                        # We only accept BLUETOOTH
                        if request.initial_info.chip.kind != ChipKind.BLUETOOTH:
                            logger.debug('Request for unsupported chip type')
                            error = PacketResponse(error='Unsupported chip type')
                            await self.context.write(error)
                            # return
                            continue

                        # Lease the sink so that no other device can send
                        self.sink = self.server.lease_sink(self)
                        if self.sink is None:
                            logger.warning('Another device is already connected')
                            error = PacketResponse(error='Device busy')
                            await self.context.write(error)
                            # return
                            continue

                        continue

                # Expect a data packet
                request_type = request.WhichOneof('request_type')
                if request_type != 'hci_packet':
                    logger.warning(f'Unexpected request type: {request_type}')
                    error = PacketResponse(error='Unexpected request type')
                    await self.context.write(error)
                    continue

                # Process the packet
                assert self.sink is not None
                self.sink(
                    bytes([request.hci_packet.packet_type]) + request.hci_packet.packet
                )

        async def send_packet(self, data):
            return await self.context.write(
                PacketResponse(
                    hci_packet=HCIPacket(packet_type=data[0], packet=data[1:])
                )
            )"""

NEW_BODY = """                        # We only accept BLUETOOTH
                        if request.initial_info.chip.kind != ChipKind.BLUETOOTH:
                            logger.warning(
                                'Ignoring non-Bluetooth chip: %s',
                                request.initial_info.chip.kind,
                            )
                            error = PacketResponse(error='Unsupported chip type')
                            await self.context.write(error)
                            # return
                            continue

                        # Lease the sink so that no other device can send
                        self.sink = self.server.lease_sink(self)
                        if self.sink is None:
                            logger.warning('Another device is already connected')
                            error = PacketResponse(error='Device busy')
                            await self.context.write(error)
                            # return
                            continue

                        continue

                # Expect a data packet. Newer emulators (~37+) send the raw
                # H4 frame in `packet`; older ones send structured `hci_packet`.
                # Accept either, and reply in whichever form the peer used.
                request_type = request.WhichOneof('request_type')
                if request_type == 'hci_packet':
                    self.raw_packets = False
                    data = (
                        bytes([request.hci_packet.packet_type])
                        + request.hci_packet.packet
                    )
                elif request_type == 'packet':
                    self.raw_packets = True
                    data = request.packet
                else:
                    logger.warning(f'Unexpected request type: {request_type}')
                    error = PacketResponse(error='Unexpected request type')
                    await self.context.write(error)
                    continue

                # Process the packet. A stream can start sending HCI without a
                # preceding initial_info, so lease the sink lazily. Never assert
                # here: an exception escaping the servicer kills the stream and
                # aborts the emulator process.
                if self.sink is None:
                    self.sink = self.server.lease_sink(self)
                    if self.sink is None:
                        logger.warning('No sink available, dropping packet')
                        continue
                    if self.name is None:
                        self.name = '(implicit)'
                    logger.info('Leased sink on first data packet')
                self.sink(data)

        async def send_packet(self, data):
            if self.raw_packets:
                return await self.context.write(PacketResponse(packet=data))
            return await self.context.write(
                PacketResponse(
                    hci_packet=HCIPacket(packet_type=data[0], packet=data[1:])
                )
            )"""


def main():
    print(f"target: {TARGET}")
    if BACKUP.exists():
        shutil.copy2(BACKUP, TARGET)          # always start from pristine
    else:
        shutil.copy2(TARGET, BACKUP)
        print(f"backed up -> {BACKUP.name}")

    src = TARGET.read_text()
    for old in (OLD_INIT, OLD_BODY):
        if src.count(old) != 1:
            sys.exit(
                f"android_netsim.py does not match this patch ({src.count(old)} "
                "occurrences). bumble likely changed upstream - check whether "
                "these fixes are already in before re-patching."
            )
    TARGET.write_text(src.replace(OLD_INIT, NEW_INIT).replace(OLD_BODY, NEW_BODY))
    print("patched: raw `packet` frames + lazy sink lease, no assert")


main()
