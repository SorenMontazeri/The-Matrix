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

    -- Sreg
    signal shift_counter : unsigned(7 downto 0); -- Counts how many bits have been shifted in
    signal sreg_full : std_logic;                -- Set high when all 136 bits are received
    signal sreg : std_logic_vector(135 downto 0);
    
    -- Matrix dimensions
    signal matrix1_rows : unsigned(1 downto 0);
    signal matrix1_cols : unsigned(1 downto 0);
    signal matrix2_rows : unsigned(1 downto 0);
    signal matrix2_cols : unsigned(1 downto 0);

    -- Output / result
    signal output_reg : std_logic_vector(13 downto 0);
    signal result_rows : unsigned(1 downto 0);
    signal result_cols : unsigned(1 downto 0);
    signal output_data : std_logic_vector(9 downto 0);

    -- Handshake to start TX after compute
    signal send_data       : std_logic;
    signal send_data_done  : std_logic;
    signal compute_done    : std_logic;

    -- Loop indices
    signal element_row : unsigned(1 downto 0);
    signal element_col : unsigned(1 downto 0);
    signal sum_k       : unsigned(1 downto 0);

    -- UART TX support (uses uart_clk as the baud clock)
    signal tx_shreg       : std_logic_vector(9 downto 0); -- {stop, d7..d0, start}
    signal tx_bit_idx     : unsigned(3 downto 0);         -- 0..9
    signal tx_busy        : std_logic;
    signal tx_clk_prev    : std_logic;

    -- Computation signals
    signal compute_start  : std_logic;
    signal compute_active : std_logic;
    signal temp_sum       : unsigned(9 downto 0);

    -- State machine for computation
    type state_type is (IDLE, COMPUTE, DONE);
    signal state : state_type;

begin
    -- Map pins
    uart_data <= ui_in(0);  -- Serial data input
    uart_clk  <= ui_in(1);  -- External clock input (acts as UART bit clock)

    -- Drive external outputs
    uo_out(0) <= uart_data_out;         -- UART TX line on OUT[0]
    uo_out(7 downto 1) <= (others => '0');
    uio_out <= (others => '0');
    uio_oe  <= (others => '0');

    -- Extract matrix dimensions from shift register
    matrix1_rows <= unsigned(sreg(1 downto 0));
    matrix1_cols <= unsigned(sreg(3 downto 2));
    matrix2_rows <= unsigned(sreg(5 downto 4));
    matrix2_cols <= unsigned(sreg(7 downto 6));

    -- Result dimensions
    result_rows <= matrix1_rows;
    result_cols <= matrix2_cols;

    ----------------------------------------------------------------------
    -- Serial shift process
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
                rx_clk_prev <= uart_clk;
                
                -- Detect rising edge of uart_clk
                if (rx_clk_prev = '0' and uart_clk = '1') then
                    if sreg_full = '0' then
                        if shift_counter = 0 then
                            -- Look for start bit
                            if uart_data = '0' then
                                shift_counter <= shift_counter + 1;
                            end if;
                        elsif shift_counter > 0 and shift_counter < 136 then
                            -- Shift in data bits
                            sreg <= uart_data & sreg(135 downto 1);
                            shift_counter <= shift_counter + 1;
                        elsif shift_counter = 136 then
                            sreg_full <= '1';
                            shift_counter <= (others => '0');
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    compute_start <= '1' when sreg_full = '1' and compute_done = '0' else '0';

    ----------------------------------------------------------------------
    -- Compute process - Fixed with proper state machine
    ----------------------------------------------------------------------
    process(clk)
        variable mat1_idx : integer;
        variable mat2_idx : integer;
        variable product : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                output_reg   <= (others => '0');
                output_data  <= (others => '0');
                element_row  <= (others => '0');
                element_col  <= (others => '0');
                sum_k        <= (others => '0');
                send_data    <= '0';
                compute_done <= '0';
                temp_sum     <= (others => '0');
                state        <= IDLE;
            else
                case state is
                    when IDLE =>
                        if compute_start = '1' then
                            -- Initialize computation
                            output_reg(1 downto 0) <= std_logic_vector(matrix1_rows);
                            output_reg(3 downto 2) <= std_logic_vector(matrix2_cols);
                            element_row <= (others => '0');
                            element_col <= (others => '0');
                            sum_k       <= (others => '0');
                            temp_sum    <= (others => '0');
                            send_data   <= '0';
                            compute_done <= '0';
                            state <= COMPUTE;
                        end if;

                    when COMPUTE =>
                        -- Calculate matrix indices (fixed indexing)
                        mat1_idx := 8 + to_integer(element_row) * 16 + to_integer(sum_k) * 4;
                        mat2_idx := 72 + to_integer(sum_k) * 16 + to_integer(element_col) * 4;
                        
                        -- Ensure indices are within bounds
                        if mat1_idx + 3 <= 135 and mat2_idx + 3 <= 135 then
                            -- Multiply 4-bit values
                            product := unsigned(sreg(mat1_idx + 3 downto mat1_idx)) * 
                                      unsigned(sreg(mat2_idx + 3 downto mat2_idx));
                            
                            temp_sum <= temp_sum + resize(product, 10);
                        end if;
                        
                        -- Increment k
                        if sum_k < matrix1_cols then
                            sum_k <= sum_k + 1;
                        else
                            -- k loop done, store result
                            output_data <= std_logic_vector(temp_sum);
                            temp_sum <= (others => '0');
                            sum_k <= (others => '0');
                            
                            -- Increment column
                            if element_col < matrix2_cols then
                                element_col <= element_col + 1;
                            else
                                -- Column loop done, increment row
                                element_col <= (others => '0');
                                if element_row < matrix1_rows then
                                    element_row <= element_row + 1;
                                else
                                    -- All elements computed
                                    state <= DONE;
                                end if;
                            end if;
                        end if;

                    when DONE =>
                        compute_done <= '1';
                        send_data <= '1';
                        state <= IDLE;  -- Ready for next computation

                end case;
                
                -- Clear send_data after transmission starts
                if send_data_done = '1' then
                    send_data <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Pack output register
    output_reg(13 downto 4) <= output_data;

    ----------------------------------------------------------------------
    -- UART Transmitter
    ----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                tx_shreg       <= (others => '1');
                tx_bit_idx     <= (others => '0');
                tx_busy        <= '0';
                tx_clk_prev    <= '0';
                uart_data_out  <= '1'; -- idle high
                send_data_done <= '0';
            else
                tx_clk_prev <= uart_clk;
                send_data_done <= '0';
                
                -- Start transmission when requested and idle
                if send_data = '1' and tx_busy = '0' then
                    tx_shreg   <= '1' & output_data(7 downto 0) & '0';  -- stop, data, start
                    tx_bit_idx <= (others => '0');
                    tx_busy    <= '1';
                    uart_data_out <= '0'; -- start bit
                end if;

                -- Shift on rising edge of uart_clk
                if tx_busy = '1' then
                    if tx_clk_prev = '0' and uart_clk = '1' then
                        if tx_bit_idx < 9 then
                            uart_data_out <= tx_shreg(to_integer(tx_bit_idx));
                            tx_bit_idx <= tx_bit_idx + 1;
                        else
                            -- Transmission complete
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