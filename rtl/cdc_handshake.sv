`timescale 1ns / 1ps
/**
 * @brief Parameterizable N-bit Clock Domain Crossing (CDC) Handshake.
 *
 * This module uses a 2-phase (toggle-based) handshake to transfer a multi-bit
 * data bus between two asynchronous clock domains.
 *
 * @param WIDTH       Width of the data bus to be transferred.
 * @param SYNC_STAGES Number of synchronization stages for the control signals.
 *
 * @param w_clk       Write (source) clock domain.
 * @param w_reset_n   Write domain active-low reset.
 * @param w_data      Data to be transferred.
 * @param w_valid     Pulse to initiate a transfer (must be high for one cycle).
 * @param w_ready     High when the module is ready to accept a new transfer.
 *
 * @param r_clk       Read (destination) clock domain.
 * @param r_reset_n   Read domain active-low reset.
 * @param r_data      Transferred data.
 * @param r_valid     Pulse indicating new data is available in the read domain.
 */

module cdc_handshake #(
    parameter int WIDTH       = 32,
    parameter int SYNC_STAGES = 2
  )(
    // Write Domain
    input  logic             w_clk,
    input  logic             w_reset_n,
    input  logic [WIDTH-1:0] w_data,
    input  logic             w_valid,
    output logic             w_ready,

    // Read Domain
    input  logic             r_clk,
    input  logic             r_reset_n,
    output logic [WIDTH-1:0] r_data,
    output logic             r_valid
  );

  // -------------------------------------------------------------------------
  // Control Signals
  // -------------------------------------------------------------------------
  logic w_req_toggle;
  logic r_ack_toggle;

  logic [WIDTH-1:0] w_data_reg;

  // -------------------------------------------------------------------------
  // Write Domain Logic
  // -------------------------------------------------------------------------

  // Synchronize r_ack_toggle into w_clk domain
  logic w_ack_sync;
  cdc_sync #(
             .STAGES(SYNC_STAGES),
             .INITIAL_VAL(1'b0)
           ) ack_sync_inst (
             .clk(w_clk),
             .reset_n(w_reset_n),
             .d(r_ack_toggle),
             .q(w_ack_sync)
           );

  // Ready when no request is pending (req and ack are in phase)
  assign w_ready = (w_req_toggle == w_ack_sync);

  always_ff @(posedge w_clk or negedge w_reset_n)
  begin
    if (!w_reset_n)
    begin
      w_req_toggle <= 1'b0;
      w_data_reg   <= '0;
    end
    else if (w_valid && w_ready)
    begin
      w_req_toggle <= ~w_req_toggle;
      w_data_reg   <= w_data;
    end
  end

  // -------------------------------------------------------------------------
  // Read Domain Logic
  // -------------------------------------------------------------------------

  // Synchronize w_req_toggle into r_clk domain
  logic r_req_sync;
  cdc_sync #(
             .STAGES(SYNC_STAGES),
             .INITIAL_VAL(1'b0)
           ) req_sync_inst (
             .clk(r_clk),
             .reset_n(r_reset_n),
             .d(w_req_toggle),
             .q(r_req_sync)
           );

  logic r_req_sync_q;

  // Detect toggle of synchronization request
  assign r_valid = (r_req_sync ^ r_req_sync_q);

  always_ff @(posedge r_clk or negedge r_reset_n)
  begin
    if (!r_reset_n)
    begin
      r_req_sync_q <= 1'b0;
      r_ack_toggle <= 1'b0;
      r_data       <= '0;
    end
    else
    begin
      r_req_sync_q <= r_req_sync;
      if (r_valid)
      begin
        r_ack_toggle <= ~r_ack_toggle;
        r_data       <= w_data_reg; // Stable because of the handshake
      end
    end
  end

endmodule
