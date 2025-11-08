# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    # Set the input values you want to test
    dut.ui_in.value = 20
    dut.uio_in.value = 30

    # Wait for one clock cycle to see the output values
    await ClockCycles(dut.clk, 1)




    
@cocotb.test()
async def test_minimal_140_chars(dut):
    """Minimal test for 140-character UART transmission"""
    
    # Start clock
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ui_in.value  = 0b0000001  # Stop bit high
    await Timer(10, unit="us")
    
    # Create message
    message = "010111" * 140  # 140 'A' characters
    
    baud_period = 104.1667  # microseconds for 9600 baud
    
    print(f"Sending {len(message)} characters...")
    
    for i, char in enumerate(message):
        byte_val = ord(char)
        
        # Start bit
        dut.ui_in.value  = 0b0000000  # Start bit low
        await Timer(baud_period, unit="us")

        # Data bits
        for bit in range(140):
            dut.ui_in.value = 0b0000000 + ((byte_val >> bit) & 0x1)
            await Timer(baud_period, unit="us")
            dut.ui_in.value = 0b0000010
        
        # Stop bit  
        dut.ui_in.value  = 0b0000001  # Stop bit high
        await Timer(baud_period, unit="us")
        
        if (i + 1) % 35 == 0:
            print(f"Sent {i + 1}/140")

    assert dut.sreg.value == message, "Shift register should be empty after transmission"

    print("✓ Test completed!")
    
    
    
    
    
    
    
    
    
    
    
    

    # The following assersion is just an example of how to check the output values.
    # Change it to match the actual expected output of your module:
    assert dut.uo_out.value == 50

    # Keep testing the module by changing the input values, waiting for
    # one or more clock cycles, and asserting the expected output values.
