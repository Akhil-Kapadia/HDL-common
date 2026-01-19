`timescale 1ns / 1ps
/**
 * @brief Parameterizable 1-bit Clock Domain Crossing (CDC) Synchronizer.
 *
 * This module synchronizes a 1-bit signal from an asynchronous clock domain
 * into the destination clock domain using a chain of flip-flops.
 *
 * @param STAGES      Number of synchronization stages (flip-flops). 
 *                   Minimum is 2 to mitigate metastability.
 * @param INITIAL_VAL Initial value for the synchronization flip-flops.
 *
 * @param clk     Destination clock domain.
 * @param reset_n Active-low asynchronous reset (synchronized or asynchronous).
 * @param d       Input signal (from asynchronous domain).
 * @param q       Synchronized output signal (in destination domain).
 */

module cdc_sync #(
    parameter int STAGES      = 2,
    parameter bit INITIAL_VAL = 1'b0
  )(
    input  logic clk,
    input  logic reset_n,
    input  logic d,
    output logic q
  );

  // Use an array of flip-flops for synchronization
  logic [STAGES-1:0] sync_regs;

  always_ff @(posedge clk or negedge reset_n)
  begin
    if (!reset_n)
    begin
      sync_regs <= {STAGES{INITIAL_VAL}};
    end
    else
    begin
      // Shift in the new value
      sync_regs <= {sync_regs[STAGES-2:0], d};
    end
  end

  // The output is the last stage of the synchronizer chain
  assign q = sync_regs[STAGES-1];

endmodule
