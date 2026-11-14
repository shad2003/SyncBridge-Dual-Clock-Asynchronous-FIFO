//-----------------------------------------------------------------------------
// Module: async_fifo
// Description: Top-level Parameterized Dual-Clock Asynchronous FIFO.
//              Implements the Clifford Cummings architecture for robust Clock
//              Domain Crossing (CDC) between independent asynchronous clocks.
//              - Parameterized DATA_WIDTH and ADDR_WIDTH (Depth = 2^ADDR_WIDTH).
//              - Safe 2-FF Gray-code pointer synchronization.
//              - Synchronous write with combinational memory read.
//              - Full and empty flag generation with zero-latency pessimistic assertion.
// Reference: Clifford E. Cummings, "Simulation and Synthesis Techniques for
//            Asynchronous FIFO Design", SNUG 2002.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module async_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4
)(
    // Write Clock Domain
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,

    // Read Clock Domain
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty
);

    // Internal interconnect signals
    logic [ADDR_WIDTH-1:0] waddr;
    logic [ADDR_WIDTH-1:0] raddr;
    logic [ADDR_WIDTH:0]   wptr;
    logic [ADDR_WIDTH:0]   rptr;
    logic [ADDR_WIDTH:0]   wq2_rptr;
    logic [ADDR_WIDTH:0]   rq2_wptr;

    // 2-FF Synchronizer: Read pointer into Write clock domain
    sync_r2w #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sync_r2w (
        .wclk     (wclk),
        .wrst_n   (wrst_n),
        .rptr     (rptr),
        .wq2_rptr (wq2_rptr)
    );

    // 2-FF Synchronizer: Write pointer into Read clock domain
    sync_w2r #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sync_w2r (
        .rclk     (rclk),
        .rrst_n   (rrst_n),
        .wptr     (wptr),
        .rq2_wptr (rq2_wptr)
    );

    // Dual-Port FIFO Memory
    fifomem #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_fifomem (
        .wclk     (wclk),
        .winc     (winc),
        .wfull    (wfull),
        .waddr    (waddr),
        .wdata    (wdata),
        .raddr    (raddr),
        .rdata    (rdata)
    );

    // Read pointer generation & rempty flag logic
    rptr_empty #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_rptr_empty (
        .rclk     (rclk),
        .rrst_n   (rrst_n),
        .rinc     (rinc),
        .rq2_wptr (rq2_wptr),
        .rempty   (rempty),
        .raddr    (raddr),
        .rptr     (rptr)
    );

    // Write pointer generation & wfull flag logic
    wptr_full #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_wptr_full (
        .wclk     (wclk),
        .wrst_n   (wrst_n),
        .winc     (winc),
        .wq2_rptr (wq2_rptr),
        .wfull    (wfull),
        .waddr    (waddr),
        .wptr     (wptr)
    );

endmodule
