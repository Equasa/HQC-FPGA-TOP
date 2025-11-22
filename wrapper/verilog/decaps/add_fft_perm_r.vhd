-- ==============================================================
-- Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC v2020.1 (64-bit)
-- Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
-- ==============================================================
library ieee; 
use ieee.std_logic_1164.all; 
use ieee.std_logic_unsigned.all;

entity add_fft_perm_r_rom is 
    generic(
             DWIDTH     : integer := 5; 
             AWIDTH     : integer := 7; 
             MEM_SIZE    : integer := 128
    ); 
    port (
          addr0      : in std_logic_vector(AWIDTH-1 downto 0); 
          ce0       : in std_logic; 
          q0         : out std_logic_vector(DWIDTH-1 downto 0);
          clk       : in std_logic
    ); 
end entity; 


architecture rtl of add_fft_perm_r_rom is 

signal addr0_tmp : std_logic_vector(AWIDTH-1 downto 0); 
type mem_array is array (0 to MEM_SIZE-1) of std_logic_vector (DWIDTH-1 downto 0); 
signal mem : mem_array := (
    0 => "00000", 1 => "00010", 2 => "00100", 3 => "00110", 4 => "01000", 
    5 => "01010", 6 => "01100", 7 => "01110", 8 => "10000", 9 => "10010", 
    10 => "10100", 11 => "10110", 12 => "11000", 13 => "11010", 14 => "11100", 
    15 => "11110", 16 => "00001", 17 => "00011", 18 => "00101", 19 => "00111", 
    20 => "01001", 21 => "01011", 22 => "01101", 23 => "01111", 24 => "10001", 
    25 => "10011", 26 => "10101", 27 => "10111", 28 => "11001", 29 => "11011", 
    30 => "11101", 31 => "11111", 32 => "00000", 33 => "00010", 34 => "00100", 
    35 => "00110", 36 => "01000", 37 => "01010", 38 => "01100", 39 => "01110", 
    40 => "00001", 41 => "00011", 42 => "00101", 43 => "00111", 44 => "01001", 
    45 => "01011", 46 => "01101", 47 => "01111", 48 => "10000", 49 => "10010", 
    50 => "10100", 51 => "10110", 52 => "11000", 53 => "11010", 54 => "11100", 
    55 => "11110", 56 => "10001", 57 => "10011", 58 => "10101", 59 => "10111", 
    60 => "11001", 61 => "11011", 62 => "11101", 63 => "11111", 64 => "00000", 
    65 => "00010", 66 => "00100", 67 => "00110", 68 => "00001", 69 => "00011", 
    70 => "00101", 71 => "00111", 72 => "01000", 73 => "01010", 74 => "01100", 
    75 => "01110", 76 => "01001", 77 => "01011", 78 => "01101", 79 => "01111", 
    80 => "10000", 81 => "10010", 82 => "10100", 83 => "10110", 84 => "10001", 
    85 => "10011", 86 => "10101", 87 => "10111", 88 => "11000", 89 => "11010", 
    90 => "11100", 91 => "11110", 92 => "11001", 93 => "11011", 94 => "11101", 
    95 => "11111", 96 => "00000", 97 => "00010", 98 => "00001", 99 => "00011", 
    100 => "00100", 101 => "00110", 102 => "00101", 103 => "00111", 104 => "01000", 
    105 => "01010", 106 => "01001", 107 => "01011", 108 => "01100", 109 => "01110", 
    110 => "01101", 111 => "01111", 112 => "10000", 113 => "10010", 114 => "10001", 
    115 => "10011", 116 => "10100", 117 => "10110", 118 => "10101", 119 => "10111", 
    120 => "11000", 121 => "11010", 122 => "11001", 123 => "11011", 124 => "11100", 
    125 => "11110", 126 => "11101", 127 => "11111" );

attribute syn_rom_style : string;
attribute syn_rom_style of mem : signal is "select_rom";
attribute ROM_STYLE : string;
attribute ROM_STYLE of mem : signal is "distributed";

begin 


memory_access_guard_0: process (addr0) 
begin
      addr0_tmp <= addr0;
--synthesis translate_off
      if (CONV_INTEGER(addr0) > mem_size-1) then
           addr0_tmp <= (others => '0');
      else 
           addr0_tmp <= addr0;
      end if;
--synthesis translate_on
end process;

p_rom_access: process (clk)  
begin 
    if (clk'event and clk = '1') then
        if (ce0 = '1') then 
            q0 <= mem(CONV_INTEGER(addr0_tmp)); 
        end if;
    end if;
end process;

end rtl;

Library IEEE;
use IEEE.std_logic_1164.all;

entity add_fft_perm_r is
    generic (
        DataWidth : INTEGER := 5;
        AddressRange : INTEGER := 128;
        AddressWidth : INTEGER := 7);
    port (
        reset : IN STD_LOGIC;
        clk : IN STD_LOGIC;
        address0 : IN STD_LOGIC_VECTOR(AddressWidth - 1 DOWNTO 0);
        ce0 : IN STD_LOGIC;
        q0 : OUT STD_LOGIC_VECTOR(DataWidth - 1 DOWNTO 0));
end entity;

architecture arch of add_fft_perm_r is
    component add_fft_perm_r_rom is
        port (
            clk : IN STD_LOGIC;
            addr0 : IN STD_LOGIC_VECTOR;
            ce0 : IN STD_LOGIC;
            q0 : OUT STD_LOGIC_VECTOR);
    end component;



begin
    add_fft_perm_r_rom_U :  component add_fft_perm_r_rom
    port map (
        clk => clk,
        addr0 => address0,
        ce0 => ce0,
        q0 => q0);

end architecture;


