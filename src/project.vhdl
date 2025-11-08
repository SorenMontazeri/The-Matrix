library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tt_um_example is
    port (
        ui_in   : in  std_logic_vector(7 downto 0);  -- IN pins
        uo_out  : out std_logic_vector(7 downto 0);  -- OUT pins
        uio_in  : in  std_logic_vector(7 downto 0);  -- GPIO input
        uio_out : out std_logic_vector(7 downto 0);  -- GPIO output
        uio_oe  : out std_logic_vector(7 downto 0);  -- GPIO port direction
        ena     : in  std_logic;
        clk     : in  std_logic;
        rst_n   : in  std_logic
    );
end tt_um_example;

architecture Behavioral of tt_um_example is

    -- Input lines
    signal uart_data, uart_clk, rx_clk_prev : std_logic;

    -- 136-bit shift register
    signal sreg : std_logic_vector(135 downto 0);

    -- Counts how many bits have been shifted in
    signal shift_counter : unsigned(7 downto 0);

    -- Set high when all 136 bits are received
    signal sreg_full : std_logic;

    -- Size
    alias matrix1_col : std_logic_vector(1 downto 0) is sreg(135 downto 134);
    alias matrix1_row : std_logic_vector(1 downto 0) is sreg(133 downto 132);
    alias matrix2_col : std_logic_vector(1 downto 0) is sreg(131 downto 130);
    alias matrix2_row : std_logic_vector(1 downto 0) is sreg(129 downto 128);

    -- Matrix 1
    alias matrix1_1   : std_logic_vector(3 downto 0) is sreg(127 downto 124);
    alias matrix1_2   : std_logic_vector(3 downto 0) is sreg(123 downto 120);
    alias matrix1_3   : std_logic_vector(3 downto 0) is sreg(119 downto 116);
    alias matrix1_4   : std_logic_vector(3 downto 0) is sreg(115 downto 112);
    alias matrix1_5   : std_logic_vector(3 downto 0) is sreg(111 downto 108);
    alias matrix1_6   : std_logic_vector(3 downto 0) is sreg(107 downto 104);
    alias matrix1_7   : std_logic_vector(3 downto 0) is sreg(103 downto 100);
    alias matrix1_8   : std_logic_vector(3 downto 0) is sreg(99 downto 96);
    alias matrix1_9   : std_logic_vector(3 downto 0) is sreg(95 downto 92);
    alias matrix1_10  : std_logic_vector(3 downto 0) is sreg(91 downto 88);
    alias matrix1_11  : std_logic_vector(3 downto 0) is sreg(87 downto 84);
    alias matrix1_12  : std_logic_vector(3 downto 0) is sreg(83 downto 80);
    alias matrix1_13  : std_logic_vector(3 downto 0) is sreg(79 downto 76);
    alias matrix1_14  : std_logic_vector(3 downto 0) is sreg(75 downto 72);
    alias matrix1_15  : std_logic_vector(3 downto 0) is sreg(71 downto 68);
    alias matrix1_16  : std_logic_vector(3 downto 0) is sreg(67 downto 64);

    -- Matrix 2
    alias matrix2_1   : std_logic_vector(3 downto 0) is sreg(63 downto 60);
    alias matrix2_2   : std_logic_vector(3 downto 0) is sreg(59 downto 56);
    alias matrix2_3   : std_logic_vector(3 downto 0) is sreg(55 downto 52);
    alias matrix2_4   : std_logic_vector(3 downto 0) is sreg(51 downto 48);
    alias matrix2_5   : std_logic_vector(3 downto 0) is sreg(47 downto 44);
    alias matrix2_6   : std_logic_vector(3 downto 0) is sreg(43 downto 40);
    alias matrix2_7   : std_logic_vector(3 downto 0) is sreg(39 downto 36);
    alias matrix2_8   : std_logic_vector(3 downto 0) is sreg(35 downto 32);
    alias matrix2_9   : std_logic_vector(3 downto 0) is sreg(31 downto 28);
    alias matrix2_10  : std_logic_vector(3 downto 0) is sreg(27 downto 24);
    alias matrix2_11  : std_logic_vector(3 downto 0) is sreg(23 downto 20);
    alias matrix2_12  : std_logic_vector(3 downto 0) is sreg(19 downto 16);
    alias matrix2_13  : std_logic_vector(3 downto 0) is sreg(15 downto 12);
    alias matrix2_14  : std_logic_vector(3 downto 0) is sreg(11 downto 8);
    alias matrix2_15  : std_logic_vector(3 downto 0) is sreg(7 downto 4);
    alias matrix2_16  : std_logic_vector(3 downto 0) is sreg(3 downto 0);


    begin

        -- Assign UART input signals
        uart_data <= ui_in(0);  -- Serial data input
        uart_clk  <= ui_in(1);  -- External clock input (9600 baud)
    
        ----------------------------------------------------------------------
        -- Serial shift process
        -- Shifts in one bit from uart_data on each rising edge of uart_clk.
        -- When 136 bits have been shifted in, sreg_full is set to '1'.
        ----------------------------------------------------------------------
        process(clk)
        begin
            if rising_edge(clk) then
                if rst_n = '0' then
                    sreg <= (others => '0');
                    shift_counter <= (others => '0');
                    rx_clk_prev <= '0';
                    sreg_full <= '0';
                else
                    -- Detect rising edge of uart_clk
                    if (rx_clk_prev = '0' and uart_clk = '1') then
                        -- Shift new bit in only if not full
                        if sreg_full = '0' then
                            sreg <= uart_data & sreg(135 downto 1);
                            shift_counter <= shift_counter + 1;
    
                            -- Once 136 bits received, set flag
                            if shift_counter = 135 then
                                sreg_full <= '1';
                            end if;
                        end if;
                    end if;
                    rx_clk_prev <= uart_clk;
                end if;
            end if;
        end process;

    end Behavioral;