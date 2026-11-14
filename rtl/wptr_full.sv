//-----------------------------------------------------------------------------
// Module: wptr_full
// Description: Write-domain pointer handling and full flag generation.
//              Generates binary write address for memory and Gray-code pointer
//              for CDC to the read domain. Full flag is asserted when the
//              next write Gray pointer's top two MSBs are inverted relative
//              to the synchronized read Gray pointer while lower bits match.
// Reference: Clifford E. Cummings, "Simulation and Synthesis Techniques for
//            Asynchronous FIFO Design", SNUG 2002.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module wptr_full #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [ADDR_WIDTH:0]   wq2_rptr,
    output logic                  wfull,
    output logic [ADDR_WIDTH-1:0] waddr,
    output logic [ADDR_WIDTH:0]   wptr
);

    logic [ADDR_WIDTH:0] wbin;
    logic [ADDR_WIDTH:0] wbinnext;
    logic [ADDR_WIDTH:0] wgraynext;
    logic                wfull_val;

    // Memory write address is the lower ADDR_WIDTH bits of the binary counter
    assign waddr = wbin[ADDR_WIDTH-1:0];

    // Binary counter advancement (increment gated by !wfull)
    assign wbinnext  = wbin + (winc & ~wfull);

    // Binary-to-Gray conversion for next state
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;

    // Cummings full condition:
    // 1. MSB inverted: write pointer has wrapped around once more than read pointer
    // 2. 2nd MSB inverted: Gray code reflection property for the same offset
    // 3. Lower LSBs match: identical memory address offset
    generate
        if (ADDR_WIDTH > 1) begin : gen_full_multi_bit
            assign wfull_val = (wgraynext == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1], wq2_rptr[ADDR_WIDTH-2:0]});
        end else begin : gen_full_single_bit
            assign wfull_val = (wgraynext == ~wq2_rptr);
        end
    endgenerate

    // Sequential state updates on wclk with asynchronous active-low reset
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= '0;
            wptr  <= '0;
            wfull <= 1'b0;
        end else begin
            wbin  <= wbinnext;
            wptr  <= wgraynext;
            wfull <= wfull_val;
        end
    end

endmodule
