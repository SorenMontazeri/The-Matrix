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
    # The following assersion is just an example of how to check the output values.
    # Change it to match the actual expected output of your module:
    assert dut.uo_out.value == 50





    
@cocotb.test()
async def test_minimal_140_chars(dut):
    """Minimal test for 140-character UART transmission"""
    
    
    # Start clock
    clock = Clock(dut.clk, 50, unit="us")
    cocotb.start_soon(clock.start())
    
    # Reset
    # Initialize
    dut.uart_clk.value = 0b1  # Stop bit high
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    
    
    await Timer(10, unit="us")
    
    # Create message
    message = "01" * 68  # 68 pairs = 136 chars total of 140
    
    baud_period = 104.1667  # microseconds for 9600 baud

    
    print(f"Sending {len(message)} characters...")
    

    await Timer(baud_period, unit="us")

    # Data bits
    for bit in range(len(message)):
        dut.uart_clk.value = 0b1  # Idle state between bits

        dut.uart_data.value =  message[bit]  # Set data bit
        print(f"Sending char {bit}, bit {bit}: {message[bit]} \n sreg value: {dut.sreg.value}")

        
        await Timer(baud_period, unit="us")
        dut.uart_clk.value = 0b0  # Idle state between bits
        await Timer(baud_period, unit="us")
        dut.uart_clk.value = 0b1  # Idle state between bits

        #print(f"Sent char {bit}, bit {bit}: {message[bit]} \n sreg value: {dut.sreg.value}")
    await Timer(baud_period, unit="us")
    dut.uart_clk.value = 0b1  # Idle state between bits
    await Timer(baud_period, unit="us")
    print("All characters sent.")
    print(f"message length: {len(message)}")
    message_reversed = ''.join(reversed(message))
    print(f"message was: {message_reversed}")
    sreg = str(dut.sreg.value)
    print(f"dut.sreg value: {sreg}")
    print(f"dut.sreg length: {len(dut.sreg.value)}")
    print("Message sent, waiting for processing...")
    
    print(f"{sreg == message_reversed}")
    
    print("Asserting received message...")
    # Wait for processing
    assert ( sreg == message_reversed ) == True, "sreg does not match sent message"
    print("✓ Test completed!")

    # Keep testing the module by changing the input values, waiting for
    # one or more clock cycles, and asserting the expected output values.
