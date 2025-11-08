library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tt_um_matrix is
    port (
        ui_in   : in  std_logic_vector(7 downto 0);
        uo_out  : out std_logic_vector(7 downto 0);
        uio_in  : in  std_logic_vector(7 downto 0);
        uio_out : out std_logic_vector(7 downto 0);
        uio_oe  : out std_logic_vector(7 downto 0);
        ena     : in  std_logic;
        clk     : in  std_logic;
        rst_n   : in  std_logic
    );
end tt_um_matrix;

architecture Behavioral of tt_um_matrix is
    signal uart_data, uart_data_out, uart_clk : std_logic;
    signal data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy, send_data : std_logic := '0';
    signal bit_counter : unsigned(2 downto 0) := (others => '0');
    signal sample_counter : unsigned(7 downto 0) := (others => '0');
    
    -- Simple state machine
    type state_type is (IDLE, RECEIVE, PROCESS_DATA, TRANSMIT);
    signal state : state_type := IDLE;
    
    -- UART receiver signals
    signal rx_buffer : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_bit_count : unsigned(2 downto 0) := (others => '0');
    signal rx_done : std_logic := '0';
    
    -- UART transmitter signals  
    signal tx_buffer : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_count : unsigned(3 downto 0) := (others => '0');
    
begin
    -- Pin mapping
    uart_data <= ui_in(0);
    uart_clk  <= ui_in(1);
    uo_out(0) <= uart_data_out;
    uo_out(7 downto 1) <= (others => '0');
    uio_out <= (others => '0');
    uio_oe  <= (others => '0');

    -- Main state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= IDLE;
                data_reg <= (others => '0');
                tx_data <= (others => '0');
                send_data <= '0';
                sample_counter <= (others => '0');
                rx_done <= '0';
            else
                case state is
                    when IDLE =>
                        send_data <= '0';
                        rx_done <= '0';
                        if uart_data = '0' then  -- Start bit detected
                            state <= RECEIVE;
                            rx_bit_count <= (others => '0');
                            sample_counter <= (others => '0');
                        end if;
                        
                    when RECEIVE =>
                        if sample_counter = 7 then  -- Sample in middle of bit
                            if rx_bit_count < 8 then
                                rx_buffer(to_integer(rx_bit_count)) <= uart_data;
                                rx_bit_count <= rx_bit_count + 1;
                            else
                                -- All bits received
                                data_reg <= rx_buffer;
                                rx_done <= '1';
                                state <= PROCESS_DATA;
                            end if;
                            sample_counter <= (others => '0');
                        else
                            sample_counter <= sample_counter + 1;
                        end if;
                        
                    when PROCESS_DATA =>
                        -- Simple processing: invert bits as example
                        tx_data <= not data_reg;
                        send_data <= '1';
                        state <= TRANSMIT;
                        
                    when TRANSMIT =>
                        if tx_busy = '0' and send_data = '1' then
                            send_data <= '0';
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- UART transmitter (simplified)
    process(clk)
        variable tx_shift : std_logic_vector(9 downto 0) := (others => '1');
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                uart_data_out <= '1';
                tx_busy <= '0';
                tx_bit_count <= (others => '0');
            else
                if send_data = '1' and tx_busy = '0' then
                    -- Start transmission: stop bit, data, start bit
                    tx_shift := '1' & tx_data & '0';
                    tx_bit_count <= (others => '0');
                    tx_busy <= '1';
                    uart_data_out <= '0';  -- Start bit
                elsif tx_busy = '1' then
                    if tx_bit_count < 9 then
                        uart_data_out <= tx_shift(to_integer(tx_bit_count));
                        tx_bit_count <= tx_bit_count + 1;
                    else
                        tx_busy <= '0';
                        uart_data_out <= '1';  -- Idle
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;