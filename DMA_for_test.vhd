-- =============================================================================
-- DMA_FOR_TEST — Direct Memory Access Controller
-- =============================================================================
-- Course   : VHDL Lab
-- Authors  : Oren Nizry (208708784), Roi Dolev (207252479), Or Gureli (211571922)
--
-- Description:
--   Transfers N 16-bit words from a source memory (base address A) to a
--   destination memory (base address B) without CPU involvement.
--   Each 16-bit word spans two consecutive 8-bit memory cells, so addresses
--   advance by 2 after every word transfer.
--
-- Interface:
--   A, B      : 8-bit start addresses for source and destination memories
--   C         : number of 16-bit words to transfer (4-bit, max 15 words)
--   datain    : 16-bit data bus from the source memory
--   Clk       : system clock (transfers happen on rising edge)
--   Rst       : synchronous reset — clears all internal state
--   Load      : latch A, B, C and begin the DMA transfer sequence
--   current_addr : 8-bit address driven onto the shared bus
--   dataout   : 16-bit data bus driven to the destination memory
--   R_W       : '0' = Read (from source), '1' = Write (to destination)
--
-- Timing:
--   Every word transfer takes 3 clock cycles:
--     Cycle 1 — idle/check  : evaluate state, assert read address + R_W='0'
--     Cycle 2 — read latch  : capture datain into data_buffer, advance source
--     Cycle 3 — write       : drive dataout from data_buffer, advance dest,
--                             increment word counter
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity DMA is
    port (
        -- Inputs
        A        : in  std_logic_vector(7 downto 0);   -- source start address
        B        : in  std_logic_vector(7 downto 0);   -- destination start address
        C        : in  std_logic_vector(3 downto 0);   -- word count to transfer
        datain   : in  std_logic_vector(15 downto 0);  -- data from source memory
        Clk      : in  std_logic;
        Rst      : in  std_logic;
        Load     : in  std_logic;
        -- Outputs
        current_addr : out std_logic_vector(7 downto 0);  -- address on bus
        dataout      : out std_logic_vector(15 downto 0); -- data to dest memory
        R_W          : out std_logic                       -- 0=Read, 1=Write
    );
end entity DMA;

architecture Behavior of DMA is

    -- Internal address registers
    signal source_addr : std_logic_vector(7 downto 0);
    signal dst_addr    : std_logic_vector(7 downto 0);

    -- Intermediate data register (holds word read from source until write phase)
    signal data_buffer : std_logic_vector(15 downto 0);

    -- State flags
    signal read_flag  : std_logic;  -- '1' during read phase
    signal write_flag : std_logic;  -- '1' during write phase
    signal start_flag : std_logic;  -- '1' while DMA transfer is active

begin

    process (Clk, Rst, Load)
        variable word_count : std_logic_vector(6 downto 0);  -- counts words transferred
    begin

        -- ----------------------------------------------------------------
        -- Synchronous Reset: clear all state
        -- ----------------------------------------------------------------
        if (Rst = '1') then
            word_count  := (others => '0');
            read_flag   <= '0';
            write_flag  <= '0';
            start_flag  <= '0';
            source_addr <= (others => '1');
            dst_addr    <= (others => '1');

        -- ----------------------------------------------------------------
        -- Load: latch start addresses and kick off transfer
        -- ----------------------------------------------------------------
        elsif (Load = '1') then
            source_addr <= A;
            dst_addr    <= B;
            start_flag  <= '1';

        -- ----------------------------------------------------------------
        -- Rising clock edge: run DMA state machine
        -- ----------------------------------------------------------------
        elsif (Clk'event and Clk = '1') then

            if (start_flag = '1') then

                -- ── READ phase ─────────────────────────────────────────
                -- Drive source address onto bus, assert R_W='0' (read).
                -- datain will be valid on the *next* clock cycle.
                if (read_flag = '1') then
                    current_addr <= source_addr;
                    source_addr  <= source_addr + 2;  -- 16-bit word = 2 bytes
                    data_buffer  <= datain;            -- latch previous read
                    R_W          <= '0';
                    read_flag    <= '0';
                    write_flag   <= '1';

                -- ── WRITE phase ────────────────────────────────────────
                -- Drive destination address + buffered data, assert R_W='1'.
                elsif (write_flag = '1') then
                    current_addr <= dst_addr;
                    dst_addr     <= dst_addr + 2;
                    dataout      <= data_buffer;
                    R_W          <= '1';
                    write_flag   <= '0';
                    word_count   := word_count + 1;

                -- ── IDLE / next-read setup ─────────────────────────────
                -- Check whether transfer is complete; otherwise start next read.
                elsif (write_flag = '0') then
                    read_flag <= '1';
                    if (word_count = C) then
                        start_flag <= '0';
                        word_count := (others => '0');
                    end if;

                end if;
            end if;

        end if;
    end process;

end architecture Behavior;
