import os
from cocotb_test.simulator import run
import pytest

@pytest.mark.parametrize("fwft_en", [0, 1])
def test_fifo(fwft_en):
    
    # Resolve paths relative to this script file
    test_dir = os.path.dirname(os.path.abspath(__file__))
    rtl_dir = os.path.abspath(os.path.join(test_dir, "..", "rtl"))
    
    params = {
        "ADDR_WIDTH": "4",
        "DATA_WIDTH": "32",
        "FWFT_EN": str(fwft_en)
    }

    run(
        verilog_sources=[os.path.join(rtl_dir, "axis_async_fifo.sv")],
        toplevel="axis_async_fifo",
        module="test_axis_async_fifo",
        simulator="verilator",
        parameters=params,
        extra_args=["--trace", "--trace-structs"], # Enable tracing
        sim_build=f"sim_build_fwft_{fwft_en}",
    )
