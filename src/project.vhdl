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

    -- Sreg
    signal shift_counter : unsigned(7 downto 0); -- Counts how many bits have been shifted in
    signal sreg_full : std_logic; -- Set high when all 136 bits are received
    signal sreg : std_logic_vector(135 downto 0);
    alias matrix1_row : std_logic_vector(1 downto 0) is sreg(1 downto 0);
    alias matrix1_col : std_logic_vector(1 downto 0) is sreg(3 downto 2); -- row 
    alias matrix2_row : std_logic_vector(1 downto 0) is sreg(5 downto 4);
    alias matrix2_col : std_logic_vector(1 downto 0) is sreg(7 downto 6);
    alias matrix1_data : std_logic_vector(63 downto 0) is sreg(71 downto 8);
    alias matrix2_data : std_logic_vector(63 downto 0) is sreg(135 downto 72);

    -- Output
    signal output : std_logic_vector(35 downto 0);
    alias output_row : std_logic_vector(1 downto 0) is output(35 downto 34);
    alias output_col : std_logic_vector(1 downto 0) is output(33 downto 32);
    alias output_z : std_logic_vector(31 downto 0) is output(31 downto 0);

    


    signal z_counter : std_logic_vector(3 downto 0);
    signal output_counter : std_logic_vector(7 downto 0);
    alias z_counter_row : std_logic_vector(1 downto 0) is z_counter(3 downto 2);
    alias z_counter_col : std_logic_vector(1 downto 0) is z_counter(1 downto 0);


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

                        -- Wait for start bit (logic low) before starting shift
                        if sreg_full = '0' then
                            if shift_counter = 0 then
                                -- Not started yet, look for start bit
                                if uart_data = '0' then
                                    -- Start bit detected, begin shifting from next clock
                                    shift_counter <= shift_counter + 1;
                                end if;

                            elsif shift_counter > 0 and shift_counter <= 136 then
                                -- Shift in 136 data bits (ignore start bit)
                                sreg <= uart_data & sreg(135 downto 1);
                                shift_counter <= shift_counter + 1;

                                -- When full, stop shifting and set flag
                                if shift_counter = 136 then
                                    sreg_full <= '1';
                                end if;
                            end if;
                        end if;
                    end if;

                    -- Update previous UART clock state
                    rx_clk_prev <= uart_clk;
                end if;
            end if;
        end process;
    end Behavioral;
