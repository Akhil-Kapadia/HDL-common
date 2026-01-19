`timescale 1ns / 1ps
/**
 * @brief AXI-Stream Clock Domain Crossing (CDC) FIFO.
 *
 * This module implements an asynchronous FIFO to transfer AXI-Stream data between
 * two different clock domains. It includes support for First-Word Fall-Through (FWFT)
 * and an optional store-and-forward packet mode.
 *
 * @param DATA_WIDTH   Width of the AXI-Stream data bus.
 * @param ADDR_WIDTH   Address width, determines FIFO depth as 2**ADDR_WIDTH.
 * @param FWFT_EN      Enables First-Word Fall-Through (Skid Buffer) logic.
 * @param PACKET_MODE  If enabled, data is only presented on the master interface after a full packet is received.
 * @param MAX_PKT_SIZE Maximum supported packet size when PACKET_MODE is enabled.
 *
 * @param s_axis_aclk    Clock for the slave (write) interface.
 * @param s_axis_aresetn Active-low reset for the slave interface.
 * @param s_axis_tdata   Input data stream.
 * @param s_axis_tlast   Input end-of-packet indicator.
 * @param s_axis_tvalid  Input valid signal.
 * @param s_axis_tready  Output ready signal (backpressure).
 *
 * @param m_axis_aclk    Clock for the master (read) interface.
 * @param m_axis_aresetn Active-low reset for the master interface.
 * @param m_axis_tdata   Output data stream.
 * @param m_axis_tlast   Output end-of-packet indicator.
 * @param m_axis_tvalid  Output valid signal.
 * @param m_axis_tready  Input ready signal (backpressure).
 *
 * @param m_axis_data_count Current number of words stored in the FIFO (synchronized to m_axis_aclk).
 * @param m_axis_pkt_count  Current number of complete packets stored in the FIFO (synchronized to m_axis_aclk).
 */

module axis_async_fifo #(
    parameter int DATA_WIDTH   = 32,
    parameter int ADDR_WIDTH   = 5,      // Set's FIFO Size to 2^ADDR_WIDTH
    parameter bit FWFT_EN      = 1,      // Skid Buffer (Pipeline), 0: Simple Register
    parameter bit PACKET_MODE  = 0,      // Store-and-forward (valid only after full packet).
    parameter int MAX_PKT_SIZE = 128     // Maximum size of a packet in the FIFO
  ) (
    // Write Domain (Source)
    input  logic                   s_axis_aclk,
    input  logic                   s_axis_aresetn,
    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tlast,
    input  logic                   s_axis_tvalid,
    output logic                   s_axis_tready,

    // Read Domain (Destination)
    input  logic                   m_axis_aclk,
    input  logic                   m_axis_aresetn,
    output logic [DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tlast,
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,

    // Status Counters (Read Domain)
    output logic [(2**ADDR_WIDTH)-1:0] m_axis_data_count,  // Words currently in FIFO
    output logic [(2**ADDR_WIDTH)-1:0] m_axis_pkt_count    // Full packets currently in FIFO
  );

  // -------------------------------------------------------------------------
  // Local Parameters
  // -------------------------------------------------------------------------
  localparam int DEPTH = 2**ADDR_WIDTH;
  localparam int PAYLOAD_WIDTH = DATA_WIDTH + 1; // Data + Last

  // -------------------------------------------------------------------------
  // Function: Gray to Binary Conversion
  // -------------------------------------------------------------------------
  function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] gray);
    logic [ADDR_WIDTH:0] bin;
    bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
    for (int i = ADDR_WIDTH-1; i >= 0; i--)
    begin
      bin[i] = bin[i+1] ^ gray[i];
    end
    return bin;
  endfunction

  // -------------------------------------------------------------------------
  // Signal Declarations
  // -------------------------------------------------------------------------
  // FIFO Memory Signals
  logic [PAYLOAD_WIDTH-1:0] s_payload_packed, m_payload_packed;
  logic [PAYLOAD_WIDTH-1:0] mem [0:DEPTH-1];

  // Data Pointers
  logic [ADDR_WIDTH:0] w_ptr_bin, w_ptr_gray, w_ptr_gray_next, w_ptr_bin_next;
  logic [ADDR_WIDTH:0] r_ptr_bin, r_ptr_gray, r_ptr_gray_next, r_ptr_bin_next;
  logic [ADDR_WIDTH:0] w_ptr_gray_sync, r_ptr_gray_sync;
  logic [ADDR_WIDTH:0] meta_wr, meta_rd;

  // Packet Pointers (For Packet Mode Counting)
  logic [ADDR_WIDTH:0] w_pkt_bin, w_pkt_gray, w_pkt_gray_next, w_pkt_bin_next;
  logic [ADDR_WIDTH:0] r_pkt_bin;
  logic [ADDR_WIDTH:0] w_pkt_gray_sync; // Write packet ptr synced to read domain

  // Status Flags
  logic full, empty;

  // Internal Interfaces
  logic                     fifo_valid_gated;
  logic                     fifo_valid_raw;
  logic                     fifo_ready;
  logic [PAYLOAD_WIDTH-1:0] fifo_data;

  // -------------------------------------------------------------------------
  // 1. Write Domain Logic
  // -------------------------------------------------------------------------
  assign s_payload_packed = {s_axis_tlast, s_axis_tdata};

  // Full Detection (Standard Gray Code check)
  assign full = (w_ptr_gray_next == {~r_ptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1], r_ptr_gray_sync[ADDR_WIDTH-2:0]});

  wire write_en = s_axis_tvalid && s_axis_tready;

  // Data Pointer Update
  assign w_ptr_bin_next  = w_ptr_bin + write_en;
  assign w_ptr_gray_next = (w_ptr_bin_next >> 1) ^ w_ptr_bin_next;

  // Packet Pointer Update (Increments on TLAST write)
  wire pkt_write_en = write_en && s_axis_tlast;
  assign w_pkt_bin_next  = w_pkt_bin + pkt_write_en;
  assign w_pkt_gray_next = (w_pkt_bin_next >> 1) ^ w_pkt_bin_next;

  always_ff @(posedge s_axis_aclk) if (!s_axis_aresetn)
    begin
      w_ptr_bin  <= '0;
      w_ptr_gray <= '0;
      w_pkt_bin  <= '0;
      w_pkt_gray <= '0;
    end
    else
    begin
      w_ptr_bin  <= w_ptr_bin_next;
      w_ptr_gray <= w_ptr_gray_next;
      w_pkt_bin  <= w_pkt_bin_next;
      w_pkt_gray <= w_pkt_gray_next;
      s_axis_tready <= !full;

      if (write_en)
      begin
        mem[w_ptr_bin[ADDR_WIDTH-1:0]] <= s_payload_packed;
      end
    end

  // -------------------------------------------------------------------------
  // 2. Synchronization (Double Flop)
  // -------------------------------------------------------------------------

  // Read Ptr -> Write Domain
  always_ff @(posedge s_axis_aclk or negedge s_axis_aresetn)
  begin
    if (!s_axis_aresetn)
      r_ptr_gray_sync <= '0;
    else
    begin
      logic [ADDR_WIDTH:0] meta;
      meta <= r_ptr_gray;
      r_ptr_gray_sync <= meta;
    end
  end

  // Write Ptr -> Read Domain (Data)
  always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn)
  begin
    if (!m_axis_aresetn)
      w_ptr_gray_sync <= '0;
    else
    begin
      meta_wr <= w_ptr_gray;
      w_ptr_gray_sync <= meta_wr;
    end
  end

  // Write Ptr -> Read Domain (Packets)
  always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn)
  begin
    if (!m_axis_aresetn)
      w_pkt_gray_sync <= '0;
    else
    begin
      meta_rd <= w_pkt_gray;
      w_pkt_gray_sync <= meta_rd;
    end
  end

  // -------------------------------------------------------------------------
  // 3. Read Domain Logic
  // -------------------------------------------------------------------------

  // --- Counter Calculation ---
  // Convert Synced Gray Pointers back to Binary for Arithmetic
  logic [ADDR_WIDTH:0] w_ptr_bin_sync;
  logic [ADDR_WIDTH:0] w_pkt_bin_sync;

  always_comb w_ptr_bin_sync = gray2bin(w_ptr_gray_sync);
  always_comb w_pkt_bin_sync = gray2bin(w_pkt_gray_sync);

  // Calculate Counts (Write Binary - Read Binary)
  assign m_axis_data_count = w_ptr_bin_sync - r_ptr_bin;
  assign m_axis_pkt_count  = w_pkt_bin_sync - r_pkt_bin;

  // --- Core FIFO Logic ---
  assign empty = (r_ptr_gray == w_ptr_gray_sync);
  assign fifo_data = mem[r_ptr_bin[ADDR_WIDTH-1:0]];

  // Packet Mode Gating
  // If PACKET_MODE is 1, we mask Valid until a full packet is available
  assign fifo_valid_raw = !empty;
  assign fifo_valid_gated = (PACKET_MODE) ? (fifo_valid_raw && (m_axis_pkt_count > 0))
         : fifo_valid_raw;

  // Read Enable logic
  wire core_read_en = fifo_valid_gated && fifo_ready;

  // Data Pointer Update
  assign r_ptr_bin_next  = r_ptr_bin + (core_read_en ? 1'b1 : 1'b0);
  assign r_ptr_gray_next = (r_ptr_bin_next >> 1) ^ r_ptr_bin_next;

  // Packet Pointer Update (Increments on TLAST read)
  // We look at the data *leaving* the core FIFO (before skid buffer)
  wire pkt_read_en = core_read_en && fifo_data[PAYLOAD_WIDTH-1]; // Bit [Top] is tlast

  always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn)
  begin
    if (!m_axis_aresetn)
    begin
      r_ptr_bin  <= '0;
      r_ptr_gray <= '0;
      r_pkt_bin  <= '0;
    end
    else
    begin
      r_ptr_bin  <= r_ptr_bin_next;
      r_ptr_gray <= r_ptr_gray_next;
      if (pkt_read_en)
        r_pkt_bin <= r_pkt_bin + 1;
    end
  end

  // -------------------------------------------------------------------------
  // 4. Output Stage (FWFT / Skid Buffer)
  // -------------------------------------------------------------------------
  generate
    if (FWFT_EN)
    begin : gen_skid_buffer
      logic [PAYLOAD_WIDTH-1:0] skid_data_reg, out_data_reg;
      logic skid_valid, out_valid;

      // Stop core if skid is full
      assign fifo_ready = !skid_valid;

      always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn)
      begin
        if (!m_axis_aresetn)
        begin
          skid_valid    <= 1'b0;
          out_valid     <= 1'b0;
          skid_data_reg <= '0;
          out_data_reg  <= '0;
        end
        else
        begin
          // Skid Load
          if (fifo_ready && fifo_valid_gated)
          begin
            skid_valid    <= 1'b1;
            skid_data_reg <= fifo_data;
          end
          else if (m_axis_tready && out_valid)
          begin
            skid_valid <= 1'b0;
          end

          // Output Load
          if (m_axis_tready || !out_valid)
          begin
            if (skid_valid)
            begin
              out_valid    <= 1'b1;
              out_data_reg <= skid_data_reg;
            end
            else if (fifo_valid_gated && fifo_ready)
            begin
              out_valid    <= 1'b1;
              out_data_reg <= fifo_data;
            end
            else
            begin
              out_valid    <= 1'b0;
            end
          end
        end
      end
      assign m_axis_tvalid    = out_valid;
      assign m_payload_packed = out_data_reg;

    end
    else
    begin : gen_simple_reg
      // Note: In Packet Mode + Simple Reg, the latency is minimal,
      // but the 'ready' path is combinational.
      assign m_axis_tvalid    = fifo_valid_gated;
      assign m_payload_packed = fifo_data;
      assign fifo_ready       = m_axis_tready;
    end
  endgenerate

  assign {m_axis_tlast, m_axis_tdata} = m_payload_packed;

endmodule
