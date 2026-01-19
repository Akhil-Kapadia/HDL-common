import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

@cocotb.test()
async def test_cdc_sync_basic(dut):
    """Test basic synchronization with default stages"""
    
    # Initialize clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    # Reset
    dut.reset_n.value = 0
    dut.d.value = 0
    await Timer(50, units="ns")
    dut.reset_n.value = 1
    await RisingEdge(dut.clk)
    
    # Check initial value
    assert dut.q.value == 0, f"Initial value should be 0, got {dut.q.value}"
    
    # Toggle input and check output after STAGES clock cycles
    stages = int(dut.STAGES.value)
    
    # Test high pulse
    dut.d.value = 1
    for i in range(stages):
        await RisingEdge(dut.clk)
        # Output shouldn't be high yet until the last stage
        if i < stages - 1:
            assert dut.q.value == 0, f"Output changed too early at cycle {i}"
    
    # Now it should be 1
    await Timer(1, units="ns") # Small delay for logic propagation in sim if needed
    assert dut.q.value == 1, f"Output should be 1 after {stages} cycles"
    
    # Test low pulse
    dut.d.value = 0
    for i in range(stages):
        await RisingEdge(dut.clk)
        if i < stages - 1:
            assert dut.q.value == 1, f"Output changed too early at cycle {i}"
    
    await Timer(1, units="ns")
    assert dut.q.value == 0, f"Output should be 0 after {stages} cycles"

@cocotb.test()
async def test_cdc_sync_random(dut):
    """Test with random input toggling"""
    
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.reset_n.value = 0
    dut.d.value = 0
    await Timer(50, units="ns")
    dut.reset_n.value = 1
    await RisingEdge(dut.clk)
    
    stages = int(dut.STAGES.value)
    
    # Monitor input and expected output (delayed by 'stages' cycles)
    history = [0] * stages
    
    for _ in range(100):
        new_val = random.randint(0, 1)
        dut.d.value = new_val
        
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        
        expected = history.pop(0)
        assert dut.q.value == expected, f"Mismatch: expected {expected}, got {dut.q.value}"
        
        history.append(new_val)
