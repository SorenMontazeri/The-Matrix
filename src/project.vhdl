library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tt_um_matrix is
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
end tt_um_matrix;

architecture Behavioral of tt_um_matrix is

    -- Input lines
    signal uart_data, uart_data_out, uart_clk, rx_clk_prev : std_logic;

    -- Shift register
    signal shift_counter : unsigned(7 downto 0);
    signal sreg_full : std_logic;
    signal sreg : std_logic_vector(135 downto 0);
    
    -- Matrix dimensions
    signal m1_rows, m1_cols, m2_rows, m2_cols : unsigned(1 downto 0);

    -- Output
    signal output_data : std_logic_vector(7 downto 0);
    signal send_data, send_data_done : std_logic;

    -- UART TX
    signal tx_shreg : std_logic_vector(9 downto 0);
    signal tx_bit_idx : unsigned(3 downto 0);
    signal tx_busy, tx_clk_prev : std_logic;

    -- Computation state machine
    type state_type is (IDLE, RECEIVING, COMPUTE, TRANSMIT);
    signal state : state_type;
    
    -- Computation signals
    signal compute_counter : unsigned(7 downto 0);
    signal result : unsigned(7 downto 0);

begin
    -- Pin mapping
    uart_data <= ui_in(0);
    uart_clk  <= ui_in(1);
    uo_out(0) <= uart_data_out;
    uo_out(7 downto 1) <= (others => '0');
    uio_out <= (others => '0');
    uio_oe  <= (others => '0');

    -- Extract matrix dimensions
    m1_rows <= unsigned(sreg(1 downto 0));
    m1_cols <= unsigned(sreg(3 downto 2));
    m2_rows <= unsigned(sreg(5 downto 4));
    m2_cols <= unsigned(sreg(7 downto 6));

    -- Main state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= IDLE;
                sreg <= (others => '0');
                shift_counter <= (others => '0');
                sreg_full <= '0';
                rx_clk_prev <= '0';
                compute_counter <= (others => '0');
                result <= (others => '0');
                send_data <= '0';
                output_data <= (others => '0');
            else
                case state is
                    when IDLE =>
                        shift_counter <= (others => '0');
                        sreg_full <= '0';
                        compute_counter <= (others => '0');
                        result <= (others => '0');
                        send_data <= '0';
                        state <= RECEIVING;

                    when RECEIVING =>
                        rx_clk_prev <= uart_clk;
                        
                        -- Detect rising edge of uart_clk
                        if rx_clk_prev = '0' and uart_clk = '1' then
                            if shift_counter = 0 then
                                -- Wait for start bit
                                if uart_data = '0' then
                                    shift_counter <= shift_counter + 1;
                                end if;
                            elsif shift_counter < 136 then
                                -- Shift in data
                                sreg <= uart_data & sreg(135 downto 1);
                                shift_counter <= shift_counter + 1;
                            else
                                -- Reception complete
                                sreg_full <= '1';
                                state <= COMPUTE;
                            end if;
                        end if;

                    when COMPUTE =>
                        -- Simple computation: sum of first 8 bytes as example
                        if compute_counter = 0 then
                            result <= (others => '0');
                        end if;
                        
                        -- Add bytes from matrix data (simplified computation)
                        if compute_counter < 8 then
                            result <= result + unsigned(sreg(15 + to_integer(compute_counter)*8 
                                        downto 8 + to_integer(compute_counter)*8));
                            compute_counter <= compute_counter + 1;
                        else
                            -- Computation done
                            output_data <= std_logic_vector(result);
                            send_data <= '1';
                            state <= TRANSMIT;
                        end if;

                    when TRANSMIT =>
                        if send_data_done = '1' then
                            send_data <= '0';
                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- UART Transmitter
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                tx_shreg <= (others => '1');
                tx_bit_idx <= (others => '0');
                tx_busy <= '0';
                tx_clk_prev <= '0';
                uart_data_out <= '1';
                send_data_done <= '0';
            else
                tx_clk_prev <= uart_clk;
                send_data_done <= '0';

                if send_data = '1' and tx_busy = '0' then
                    -- Start transmission: {stop, data, start}
                    tx_shreg <= '1' & output_data & '0';
                    tx_bit_idx <= (others => '0');
                    tx_busy <= '1';
                    uart_data_out <= '0'; -- start bit
                end if;

                if tx_busy = '1' then
                    if tx_clk_prev = '0' and uart_clk = '1' then
                        if tx_bit_idx < 9 then
                            uart_data_out <= tx_shreg(to_integer(tx_bit_idx));
                            tx_bit_idx <= tx_bit_idx + 1;
                        else
                            tx_busy <= '0';
                            send_data_done <= '1';
                            uart_data_out <= '1'; -- idle
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;