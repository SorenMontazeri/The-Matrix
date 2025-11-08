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
        clk     : in  std_logic;                     -- system clock
        rst_n   : in  std_logic                      -- active-low reset
    );
end tt_um_example;

architecture Behavioral of tt_um_example is

    -- Input lines
    signal uart_data, uart_data_out, uart_clk, rx_clk_prev : std_logic;

    -- Sreg
    signal shift_counter : unsigned(7 downto 0); -- Counts how many bits have been shifted in
    signal sreg_full : std_logic;                -- Set high when all 136 bits are received
    signal sreg : std_logic_vector(135 downto 0);
    alias matrix1_row  : std_logic_vector(1 downto 0) is sreg(1 downto 0);
    alias matrix1_col  : std_logic_vector(1 downto 0) is sreg(3 downto 2);
    alias matrix2_row  : std_logic_vector(1 downto 0) is sreg(5 downto 4);
    alias matrix2_col  : std_logic_vector(1 downto 0) is sreg(7 downto 6);
    alias matrix1_data : std_logic_vector(63 downto 0) is sreg(71 downto 8);
    alias matrix2_data : std_logic_vector(63 downto 0) is sreg(135 downto 72);

    -- Output / result packing
    signal output : std_logic_vector(13 downto 0);
    alias output_row : std_logic_vector(1 downto 0) is output(1 downto 0);
    alias output_col : std_logic_vector(1 downto 0) is output(3 downto 2);
    alias output_z   : std_logic_vector(9 downto 0) is output(13 downto 4);

    -- Handshake to start TX after compute
    signal send_data       : std_logic;
    signal send_data_done  : std_logic;

    -- Loop indices
    signal element_row : std_logic_vector(1 downto 0);
    signal element_col : std_logic_vector(1 downto 0);
    signal sum_k       : std_logic_vector(1 downto 0);

    -- UART TX support (uses uart_clk as the baud clock)
    signal tx_shreg       : std_logic_vector(9 downto 0); -- {stop, d7..d0, start}
    signal tx_bit_idx     : unsigned(3 downto 0);         -- 0..9
    signal tx_busy        : std_logic;
    signal tx_clk_prev    : std_logic;

    -- Optional (not strictly required, but handy if you later use it)
    signal sreg_full_prev : std_logic;

begin
    -- Map pins
    uart_data <= ui_in(0);  -- Serial data input
    uart_clk  <= ui_in(1);  -- External clock input (acts as UART bit clock)

    -- Drive external outputs
    uo_out(0) <= uart_data_out;         -- UART TX line on OUT[0]
    uo_out(7 downto 1) <= (others => '0');
    uio_out <= (others => '0');
    uio_oe  <= (others => '0');

    ----------------------------------------------------------------------
    -- Serial shift process: sample one bit from uart_data on rising edge
    -- of uart_clk (detected inside clk domain). After 136 bits, set sreg_full.
    ----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                sreg          <= (others => '0');
                shift_counter <= (others => '0');
                rx_clk_prev   <= '0';
                sreg_full     <= '0';
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

    ----------------------------------------------------------------------
    -- Compute process (kept per your structure). When it finishes the
    -- nested loops, it asserts send_data to trigger UART TX.
    ----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                output      <= (others => '0');
                element_row <= (others => '0');
                element_col <= (others => '0');
                sum_k       <= (others => '0');
                send_data   <= '0';
            else
                if send_data = '0' then
                    -- compare as unsigned
                    while (unsigned(element_row) < unsigned(output_row)) loop
                        while (unsigned(element_col) < unsigned(output_col)) loop
                            while (to_integer(unsigned(sum_k)) <
                                   (to_integer(unsigned(output_row)) * to_integer(unsigned(output_col)))) loop

                                -- accumulate: multiply two 4-bit fields and add to output
                                output <= std_logic_vector(
                                    resize(unsigned(output), output'length) +
                                    resize(
                                        unsigned(
                                            sreg( (8 + to_integer(unsigned(element_col))*4 + to_integer(unsigned(sum_k))*4) + 3
                                                  downto (8 + to_integer(unsigned(element_col))*4 + to_integer(unsigned(sum_k))*4) )
                                        )
                                        *
                                        unsigned(
                                            sreg( (8 + to_integer(unsigned(element_row))*4 + to_integer(unsigned(sum_k))) + 3
                                                  downto (8 + to_integer(unsigned(element_row))*4 + to_integer(unsigned(sum_k))) )
                                        ),
                                        output'length
                                    )
                                );

                                -- sum_k <= sum_k + 1
                                sum_k <= std_logic_vector(unsigned(sum_k) + 1);
                            end loop;

                            -- finished current column
                            sum_k       <= (others => '0');
                            element_col <= std_logic_vector(unsigned(element_col) + 1);
                        end loop;

                        -- next row
                        element_col <= (others => '0');
                        element_row <= std_logic_vector(unsigned(element_row) + 1);
                    end loop;

                    -- all done: request transmit
                    send_data   <= '1';
                    element_row <= (others => '0'); -- optional reset
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- UART Transmitter using uart_clk as the bit clock.
    -- Sends output_z(7 downto 0) as 8-N-1 when send_data='1'.
    ----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                sreg_full_prev <= '0';
                tx_shreg       <= (others => '1');
                tx_bit_idx     <= (others => '0');
                tx_busy        <= '0';
                tx_clk_prev    <= '0';
                uart_data_out  <= '1'; -- idle high
                send_data_done <= '0';
            else
                -- Start a transmission when requested and idle
                if (send_data = '1') and (tx_busy = '0') then
                    -- Frame: start(0), data LSB-first, stop(1)
                    tx_shreg       <= '1' & output_z(7 downto 0) & '0';
                    tx_bit_idx     <= (others => '0');
                    tx_busy        <= '1';
                    send_data_done <= '0';
                    uart_data_out  <= '0'; -- drive start bit immediately
                end if;

                -- Shift one bit per rising edge of uart_clk
                if (tx_busy = '1') then
                    if (tx_clk_prev = '0') and (uart_clk = '1') then
                        uart_data_out <= tx_shreg(1);              -- next bit
                        tx_shreg      <= '1' & tx_shreg(9 downto 1);
                        tx_bit_idx    <= tx_bit_idx + 1;

                        if tx_bit_idx = to_unsigned(9, tx_bit_idx'length) then
                            -- sent 10 bits
                            tx_busy        <= '0';
                            send_data_done <= '1';
                            uart_data_out  <= '1';                 -- idle
                        end if;
                    end if;
                end if;

                -- Clear the send request once done
                if (send_data = '1') and (send_data_done = '1') then
                    send_data <= '0';
                end if;

                -- Edge detector for uart_clk (in clk domain)
                tx_clk_prev    <= uart_clk;
                sreg_full_prev <= sreg_full;
            end if;
        end if;
    end process;

end Behavioral;
