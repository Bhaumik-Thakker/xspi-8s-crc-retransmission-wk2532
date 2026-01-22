# xSPI (xSPI-like) Controller + Slave in Verilog (CRC8 + Retransmission)

This repository contains a small **simulation-focused** Verilog design that models an **xSPI-inspired** command/address/data protocol over an **8-bit shared I/O bus**, with **CRC8 checking** and **automatic retransmission** on CRC errors.

> Note: The current RTL is an educational / template implementation and does **not** aim to be a complete JEDEC JESD251 (xSPI) drop-in replacement. It is best treated as a starting point for learning, experimenting, and building out a more realistic PHY/timing model.

## Highlights

- Controller (master) + slave RTL
- Command + 48-bit address phase
- Optional 64-bit data phase (read or write)
- CRC8 (poly `0x07`) for **command+address** and **data**
- Retransmission logic (up to 3 retries)
- Self-contained testbench + VCD waveform dump

## Repository layout

```
.
├── src/                  # Synthesizable-ish RTL
│   ├── xspi_top.v
│   ├── xspi_sopi_controller.v
│   ├── xspi_sopi_slave.v
│   ├── crc8.v
│   └── crc8_slave.v
├── tb/                   # Testbench
│   └── xspi_stimulus.v
├── docs/
│   └── waveform.png
├── .github/workflows/     # CI (Icarus)
├── Makefile
└── LICENSE
```

## Protocol summary

A transaction is modeled as a sequence of byte transfers on the shared 8-bit bus:

1. **Command** (1 byte)
2. **Address** (6 bytes = 48-bit)
3. **CRC8(Cmd+Addr)** (1 byte)
4. **Write (`0xA5`)**: 8 data bytes + CRC8(data)
5. **Read  (`0xFF`)**: slave waits a fixed latency, then returns 8 data bytes + CRC8(data)

The included testbench performs:

- A **write** of `64'h1122334455667788` to address `48'h6655443322AB`
- A **read** back from the same address and compares the returned data

## Waveform

![Waveform](docs/waveform.png)

## Quick start (simulation)

### Requirements

- Icarus Verilog (`iverilog`, `vvp`)
- GTKWave (optional, for viewing `*.vcd`)

### Run

```bash
make sim
```

This produces a waveform at:

- `build/xspi_tb.vcd`

### View waveform

```bash
make wave
```

## Notes on retransmission / CRC error injection

The RTL includes retry logic on both controller and slave sides. The current slave implementation also contains logic that can intentionally flag CRC errors (useful for demonstrating and verifying the retransmission path). If you want the slave to behave strictly as a normal endpoint (no forced CRC failures), remove or gate the corresponding logic in `xspi_sopi_slave.v`.

## License

MIT (edit `LICENSE` and replace `<YOUR_NAME>`).

## Roadmap ideas

If you want this project to read as a stronger portfolio piece on GitHub, a good next set of increments would be:

- Add `default_nettype none` + explicit net declarations
- Make the testbench fail CI on mismatch (`$fatal`) and add multiple randomized trials
- Add a simple memory map (multiple addresses) instead of a single register
- Add coverage points / assertions for CRC and retry behavior
- Add a real serial PHY layer (toggle `sck`, DDR sampling, DQS, etc.) once the high-level flow is locked down
