// CRC8 module (as provided)
module crc8_slave (
    input  wire       clk,      ///< System clock
    input  wire       rst,      ///< Asynchronous reset
    input  wire       enable,   ///< Enable CRC calculation
    input  wire       clear,    ///< Clear CRC output
    input  wire [7:0] data_in,  ///< 8-bit input data
    output reg  [7:0] crc_out   ///< 8-bit CRC output
);
    parameter POLY = 8'h07; ///< CRC polynomial
    wire [7:0] crc_in = crc_out ^ data_in;
    wire [7:0] stage0 = (crc_in[7]) ? (crc_in << 1) ^ POLY : (crc_in << 1);
    wire [7:0] stage1 = (stage0[7]) ? (stage0 << 1) ^ POLY : (stage0 << 1);
    wire [7:0] stage2 = (stage1[7]) ? (stage1 << 1) ^ POLY : (stage1 << 1);
    wire [7:0] stage3 = (stage2[7]) ? (stage2 << 1) ^ POLY : (stage2 << 1);
    wire [7:0] stage4 = (stage3[7]) ? (stage3 << 1) ^ POLY : (stage3 << 1);
    wire [7:0] stage5 = (stage4[7]) ? (stage4 << 1) ^ POLY : (stage4 << 1);
    wire [7:0] stage6 = (stage5[7]) ? (stage5 << 1) ^ POLY : (stage5 << 1);
    wire [7:0] crc_next = (stage6[7]) ? (stage6 << 1) ^ POLY : (stage6 << 1);
  always @(negedge clk or posedge rst) begin
        if (rst)
            crc_out <= 8'h00;
        else if (clear)
            crc_out <= 8'h00;
        else if (enable)
            crc_out <= crc_next;
    end
endmodule 