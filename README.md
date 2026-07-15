# VHDL DMA Controller

> **Course:** VHDL Lab  
> **Authors:** Oren Nizry  
> **Language:** VHDL (IEEE 1076)  
> **Toolchain:** Quartus / ModelSim (Altera/Intel)

---

## Table of Contents

- [Overview](#overview)
- [Entity Interface](#entity-interface)
- [Architecture](#architecture)
  - [Memory Model](#memory-model)
  - [Internal Signals](#internal-signals)
  - [State Machine](#state-machine)
  - [Timing Diagram](#timing-diagram)
- [VHDL Code Walkthrough](#vhdl-code-walkthrough)
  - [Reset](#reset)
  - [Load](#load)
  - [Read Phase](#read-phase)
  - [Write Phase](#write-phase)
  - [Idle / Completion Check](#idle--completion-check)
- [Address Advancement by 2](#address-advancement-by-2)
- [Files](#files)

---

## Overview

`DMA_FOR_TEST` is a **Direct Memory Access (DMA) controller** implemented in VHDL. It autonomously transfers a configurable number of 16-bit words from a **source memory** (starting at address `A`) to a **destination memory** (starting at address `B`), without any CPU involvement during the transfer.

The DMA takes control of the shared memory bus, alternating between **read** and **write** cycles until `C` words have been moved.

---

## Entity Interface

```vhdl
entity DMA is
    port (
        A        : in  std_logic_vector(7 downto 0);   -- source start address (8-bit)
        B        : in  std_logic_vector(7 downto 0);   -- destination start address (8-bit)
        C        : in  std_logic_vector(3 downto 0);   -- number of 16-bit words to transfer
        datain   : in  std_logic_vector(15 downto 0);  -- data bus from source memory
        Clk      : in  std_logic;                      -- system clock
        Rst      : in  std_logic;                      -- synchronous reset (active-high)
        Load     : in  std_logic;                      -- latch A/B/C and start transfer
        current_addr : out std_logic_vector(7 downto 0);  -- address driven onto bus
        dataout      : out std_logic_vector(15 downto 0); -- data driven to destination
        R_W          : out std_logic                       -- 0 = Read, 1 = Write
    );
end entity DMA;
```

### Port Descriptions

| Port | Dir | Width | Description |
|---|---|---|---|
| `A` | in | 8 bits | Start address in the **source** memory |
| `B` | in | 8 bits | Start address in the **destination** memory |
| `C` | in | 4 bits | Number of 16-bit words to transfer (1–15) |
| `datain` | in | 16 bits | Data read from the source memory |
| `Clk` | in | 1 bit | Rising-edge clock |
| `Rst` | in | 1 bit | Active-high synchronous reset |
| `Load` | in | 1 bit | Loads A, B, C and starts the DMA sequence |
| `current_addr` | out | 8 bits | Current address being driven on the bus |
| `dataout` | out | 16 bits | Data word being written to the destination |
| `R_W` | out | 1 bit | Bus direction: `'0'` = Read, `'1'` = Write |

---

## Architecture

### Memory Model

Each memory has the following interface per the lab specification:

| Signal | Width | Direction | Description |
|---|---|---|---|
| Address input | 8 bits | → memory | Address of the cell to access |
| Data input | 16 bits | → memory | Data to write (used in write mode) |
| Data output | 16 bits | ← memory | Data read out (valid on the **next** clock after address is asserted) |
| R/W | 1 bit | → memory | `'0'` = Read, `'1'` = Write |

> **Key timing constraint:** When reading, the data appears on `datain` only on the **clock cycle after** the address and `R_W='0'` are asserted. This one-cycle read latency is handled explicitly in the state machine.

**Word size:** 16 bits. **Cell size:** 8 bits. Therefore, each 16-bit word occupies **2 consecutive 8-bit cells**, and all addresses advance by **2** per word.

---

### Internal Signals

```vhdl
signal source_addr : std_logic_vector(7 downto 0);  -- current read address (advances by 2)
signal dst_addr    : std_logic_vector(7 downto 0);  -- current write address (advances by 2)
signal data_buffer : std_logic_vector(15 downto 0); -- holds word captured from source
signal read_flag   : std_logic;   -- '1' = currently in read phase
signal write_flag  : std_logic;   -- '1' = currently in write phase
signal start_flag  : std_logic;   -- '1' = DMA transfer is active
variable word_count : std_logic_vector(6 downto 0); -- counts words transferred so far
```

---

### State Machine

The DMA operates as a 3-state cyclic machine once activated:

```
         ┌─── Load asserted ────────────────────────────────┐
         │                                                   │
    [IDLE / CHECK] ──────────── word_count = C ──────────► [DONE]
         │  ▲                                                (start_flag = '0')
         │  │
    read_flag='1'
         │  │
         ▼  │
      [READ]                           R_W = '0', drive source_addr
         │                             capture datain into data_buffer
         │  write_flag='1'             source_addr += 2
         ▼
      [WRITE]                          R_W = '1', drive dst_addr
         │                             drive data_buffer to dataout
         └──────────────────────────► dst_addr += 2, word_count++
                                       → back to IDLE/CHECK
```

| State | `read_flag` | `write_flag` | Action |
|---|---|---|---|
| **IDLE / CHECK** | `0` | `0` | Set `read_flag='1'`; if `word_count = C`, stop |
| **READ** | `1` | `0` | Assert source address + `R_W='0'`; latch `datain`; set `write_flag='1'` |
| **WRITE** | `0` | `1` | Assert dest address + `R_W='1'`; drive `dataout`; increment `word_count` |

Each complete word transfer (IDLE → READ → WRITE) takes **3 clock cycles**.

---

### Timing Diagram

```
Clk         ____    ____    ____    ____    ____    ____    ____
           |    |  |    |  |    |  |    |  |    |  |    |  |    |
     _____/      \__/    \__/    \__/    \__/    \__/    \__/

Load        ──────────┐
                      └─────────────────────────────────────────

start_flag            ┌─────────────────────────────────────────
                      │

Phase       IDLE    CHECK   READ    WRITE   CHECK   READ    WRITE ...
                                    ↑               ↑
R_W                        '0'    '1'      '0'    '1'
                                    │
current_addr               A+0    B+0      A+2    B+2
                                    │
datain              (A+0 valid here)│
                                    │
data_buffer                  [word0 latched]      [word1 latched]

dataout                           word0            word1

word_count                         0       1        1       2
```

---

## VHDL Code Walkthrough

### Reset

```vhdl
if (Rst = '1') then
    word_count  := (others => '0');
    read_flag   <= '0';
    write_flag  <= '0';
    start_flag  <= '0';
    source_addr <= (others => '1');
    dst_addr    <= (others => '1');
```

All flags and counters are cleared. Addresses are set to `0xFF` (inactive/sentinel value). The DMA will not do anything until `Load` is asserted.

---

### Load

```vhdl
elsif (Load = '1') then
    source_addr <= A;
    dst_addr    <= B;
    start_flag  <= '1';
```

The start addresses are latched from inputs `A` and `B`. `start_flag` is raised to begin the transfer on the next clock edge. `Load` is checked **before** the clock edge — it acts as an asynchronous enable for the latch operation (priority over clock).

---

### Read Phase

```vhdl
if (read_flag = '1') then
    current_addr <= source_addr;      -- drive source address onto bus
    source_addr  <= source_addr + 2;  -- pre-increment for next word
    data_buffer  <= datain;           -- latch the data from PREVIOUS read cycle
    R_W          <= '0';              -- tell memory: this is a read
    read_flag    <= '0';
    write_flag   <= '1';              -- transition to write phase
```

> **Note on latency:** `data_buffer <= datain` captures the result of the **previous** clock's address assertion (because memory has a 1-cycle read delay). The address asserted **this** cycle will be available on `datain` in the next cycle.

---

### Write Phase

```vhdl
elsif (write_flag = '1') then
    current_addr <= dst_addr;         -- drive destination address onto bus
    dst_addr     <= dst_addr + 2;     -- pre-increment for next word
    dataout      <= data_buffer;      -- place buffered data on the data bus
    R_W          <= '1';              -- tell memory: this is a write
    write_flag   <= '0';
    word_count   := word_count + 1;   -- count completed word transfers
```

The `data_buffer` content (captured during the read phase) is written to the destination memory.

---

### Idle / Completion Check

```vhdl
elsif (write_flag = '0') then
    read_flag <= '1';                 -- arm the next read phase
    if (word_count = C) then
        start_flag <= '0';            -- all C words transferred — done
        word_count := (others => '0');
    end if;
```

After each write, the machine returns here. If the word count has reached `C`, the transfer completes (`start_flag` drops). Otherwise, `read_flag` is raised and the next word's read cycle begins.

---

## Address Advancement by 2

Since the memory's **cell size is 8 bits** but each **data word is 16 bits**, every word occupies two consecutive cells:

```
Address   Content
  A+0  →  word[15:8]  (high byte)
  A+1  →  word[7:0]   (low byte)
  A+2  →  next word high byte
  A+3  →  next word low byte
  ...
```

Therefore both `source_addr` and `dst_addr` increment by **2** after each word transfer, not by 1.

---

## Files

| File | Description |
|---|---|
| [`DMA_for_test.vhd`](DMA_for_test.vhd) | Full VHDL source — entity + architecture |
| [`vhdl הגשה (1).docx`](vhdl%20הגשה%20(1).docx) | Original Hebrew submission document |
