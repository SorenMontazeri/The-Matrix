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
    alias matrix1_row  : std_logic_vector(1 downto 0) is sreg(1 downto 0);
    alias matrix1_col  : std_logic_vector(1 downto 0) is sreg(3 downto 2);
    alias matrix2_row  : std_logic_vector(1 downto 0) is sreg(5 downto 4);
    alias matrix2_col  : std_logic_vector(1 downto 0) is sreg(7 downto 6);
    alias matrix1_data : std_logic_vector(63 downto 0) is sreg(71 downto 8);
    alias matrix2_data : std_logic_vector(63 downto 0) is sreg(135 downto 72);

    -- Output / result packing
    signal output_reg : std_logic_vector(13 downto 0);
    alias output_row : std_logic_vector(1 downto 0) is output_reg(1 downto 0);
    alias output_col : std_logic_vector(1 downto 0) is output_reg(3 downto 2);
    alias output_z   : std_logic_vector(9 downto 0) is output_reg(13 downto 4);

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
    signal temp_product   : unsigned(7 downto 0);

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
                rx_clk_prev <= uart_clk;
                
                -- Detect rising edge of uart_clk
                if (rx_clk_prev = '0' and uart_clk = '1') then
                    if sreg_full = '0' then
                        if shift_counter = 0 then
                            -- Not started yet, look for start bit
                            if uart_data = '0' then
                                -- Start bit detected, begin shifting from next clock
                                shift_counter <= shift_counter + 1;
                            end if;
                        elsif shift_counter > 0 and shift_counter < 136 then
                            -- Shift in 136 data bits (ignore start bit)
                            sreg <= uart_data & sreg(135 downto 1);
                            shift_counter <= shift_counter + 1;
                        elsif shift_counter = 136 then
                            -- When full, stop shifting and set flag
                            sreg_full <= '1';
                            shift_counter <= (others => '0');
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Start computation when shift register is full
    compute_start <= '1' when sreg_full = '1' and compute_done = '0' else '0';

    ----------------------------------------------------------------------
    -- Compute process - Fixed version with proper state machine
    ----------------------------------------------------------------------
    process(clk)
        variable mat1_idx : integer;
        variable mat2_idx : integer;
        variable temp_sum : unsigned(9 downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                output_reg    <= (others => '0');
                element_row   <= (others => '0');
                element_col   <= (others => '0');
                sum_k         <= (others => '0');
                send_data     <= '0';
                compute_done  <= '0';
                compute_active <= '0';
                temp_sum      := (others => '0');
            else
                if compute_start = '1' and compute_active = '0' then
                    -- Initialize computation
                    output_reg(1 downto 0) <= matrix1_row;  -- Result rows = matrix1 rows
                    output_reg(3 downto 2) <= matrix2_col;  -- Result cols = matrix2 cols
                    element_row <= (others => '0');
                    element_col <= (others => '0');
                    sum_k       <= (others => '0');
                    temp_sum    := (others => '0');
                    compute_active <= '1';
                    compute_done <= '0';
                    send_data <= '0';
                    
                elsif compute_active = '1' then
                    -- Matrix multiplication: C[i][j] = sum(A[i][k] * B[k][j])
                    
                    -- Calculate indices for matrix access
                    mat1_idx := 8 + to_integer(element_row) * 16 + to_integer(sum_k) * 4;
                    mat2_idx := 72 + to_integer(sum_k) * 16 + to_integer(element_col) * 4;
                    
                    -- Multiply 4-bit values and accumulate
                    temp_product <= unsigned(sreg(mat1_idx + 3 downto mat1_idx)) * 
                                   unsigned(sreg(mat2_idx + 3 downto mat2_idx));
                    
                    temp_sum := temp_sum + resize(temp_product, 10);
                    
                    -- Increment k
                    if sum_k < unsigned(matrix1_col) then
                        sum_k <= sum_k + 1;
                    else
                        -- k loop done, store result for this element
                        output_z <= std_logic_vector(temp_sum);
                        temp_sum := (others => '0');
                        sum_k <= (others => '0');
                        
                        -- Increment column
                        if element_col < unsigned(matrix2_col) then
                            element_col <= element_col + 1;
                        else
                            -- Column loop done, increment row
                            element_col <= (others => '0');
                            if element_row < unsigned(matrix1_row) then
                                element_row <= element_row + 1;
                            else
                                -- All elements computed
                                compute_active <= '0';
                                compute_done <= '1';
                                send_data <= '1';
                            end if;
                        end if;
                    end if;
                end if;
                
                -- Clear send_data after transmission is done
                if send_data_done = '1' then
                    send_data <= '0';
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
                tx_shreg       <= (others => '1');
                tx_bit_idx     <= (others => '0');
                tx_busy        <= '0';
                tx_clk_prev    <= '0';
                uart_data_out  <= '1'; -- idle high
                send_data_done <= '0';
            else
                tx_clk_prev <= uart_clk;
                send_data_done <= '0';
                
                -- Start a transmission when requested and idle
                if send_data = '1' and tx_busy = '0' then
                    -- Frame: start(0), data LSB-first, stop(1)
                    tx_shreg   <= '1' & output_z(7 downto 0) & '0';
                    tx_bit_idx <= (others => '0');
                    tx_busy    <= '1';
                    uart_data_out <= '0'; -- drive start bit immediately
                end if;

                -- Shift one bit per rising edge of uart_clk
                if tx_busy = '1' then
                    if tx_clk_prev = '0' and uart_clk = '1' then
                        if tx_bit_idx < 10 then
                            uart_data_out <= tx_shreg(0);
                            tx_shreg <= '1' & tx_shreg(9 downto 1);
                            tx_bit_idx <= tx_bit_idx + 1;
                        end if;
                        
                        if tx_bit_idx = 9 then
                            -- sent 10 bits
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