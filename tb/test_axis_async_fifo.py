import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Combine
from cocotb_bus.drivers import BusDriver
from cocotb_bus.monitors import BusMonitor
from cocotb.queue import Queue
import random

# AXI Stream Driver
class AxisDriver(BusDriver):
    _signals = ["tvalid", "tready", "tdata"]
    def __init__(self, entity, name, clock, **kwargs):
        BusDriver.__init__(self, entity, name, clock, **kwargs)

    async def _driver_send(self, transaction, sync=True):
        if sync:
            await RisingEdge(self.clock)
        
        # Drive data
        self.bus.tdata.value = transaction
        self.bus.tvalid.value = 1
        
        # Wait for ready
        while True:
            await RisingEdge(self.clock)
            # Check if current cycle was accepted
            if self.bus.tready.value == 1:
                break
        
        # Clear valid (or keep high if we had more data, but basic driver clears)
        self.bus.tvalid.value = 0

    async def send_sequence(self, data_list):
        for data in data_list:
            if random.random() < 0.2: # Random idle cycles
                self.bus.tvalid.value = 0
                await RisingEdge(self.clock)
            await self._driver_send(data)

# AXI Stream Monitor
class AxisMonitor(BusMonitor):
    _signals = ["tvalid", "tready", "tdata"]
    def __init__(self, entity, name, clock, **kwargs):
        BusMonitor.__init__(self, entity, name, clock, **kwargs)

    async def _monitor_recv(self):
        while True:
            await RisingEdge(self.clock)
            if self.bus.tvalid.value == 1 and self.bus.tready.value == 1:
                self._recv(int(self.bus.tdata.value))

@cocotb.test()
async def test_axis_async_fifo(dut):
    """
    Test AXI Stream Async FIFO Data Integrity and Flow Control
    """
    
    # 1. Clock Generation (Async)
    # Write Clock: 10ns (100 MHz)
    # Read Clock: 7ns (~142 MHz) or 13ns (~76 MHz). Let's randomize or pick distinct.
    cocotb.start_soon(Clock(dut.s_axis_aclk, 10, units='ns').start())
    cocotb.start_soon(Clock(dut.m_axis_aclk, 13, units='ns').start())

    # 2. Reset
    dut.s_axis_aresetn.value = 0
    dut.m_axis_aresetn.value = 0
    dut.s_axis_tvalid.value = 0
    dut.m_axis_tready.value = 0
    
    await Timer(50, units='ns')
    dut.s_axis_aresetn.value = 1
    dut.m_axis_aresetn.value = 1
    await Timer(50, units='ns')

    # 3. Setup Drivers/Monitors
    axis_source = AxisDriver(dut, "s_axis", dut.s_axis_aclk)
    axis_sink   = AxisMonitor(dut, "m_axis", dut.m_axis_aclk)
    
    # 4. Generate random backpressure on Master side
    async def random_backpressure():
        while True:
            dut.m_axis_tready.value = random.choice([0, 1])
            await RisingEdge(dut.m_axis_aclk)
    
    cocotb.start_soon(random_backpressure())

    # 5. Scoreboard
    received_data = []
    expected_data = [random.randint(0, 2**32-1) for _ in range(200)]
    
    def scoreboard_callback(transaction):
        received_data.append(transaction)

    axis_sink.add_callback(scoreboard_callback)

    # 6. Run Test
    dut._log.info(f"Sending {len(expected_data)} packets...")
    await axis_source.send_sequence(expected_data)
    
    # Wait for all data to drain
    timeout = 10000 
    for _ in range(timeout):
        if len(received_data) == len(expected_data):
            break
        await RisingEdge(dut.m_axis_aclk)

    if len(received_data) != len(expected_data):
        raise TestFailure(f"Timeout! Received {len(received_data)}/{len(expected_data)}")

    # 7. Check correctness
    if received_data == expected_data:
        dut._log.info("Test Passed: All data received correctly!")
    else:
        # Check first diff
        for i in range(min(len(received_data), len(expected_data))):
            if received_data[i] != expected_data[i]:
                raise Exception(f"Mismatch at index {i}: Exp {expected_data[i]} vs Got {received_data[i]}")
        raise Exception("Data mismatch (lengths or content)")

    # 8. Sanity check Data Counts
    # Since we are drained, counts should be 0
    await Timer(100, units='ns')
    if dut.wr_data_count.value != 0:
        dut._log.warning(f"Writer Count not 0 at end: {dut.wr_data_count.value}")
    if dut.rd_data_count.value != 0:
        dut._log.warning(f"Reader Count not 0 at end: {dut.rd_data_count.value}")
