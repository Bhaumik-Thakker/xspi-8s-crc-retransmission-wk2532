/**
 * @module xspi_sopi_slave
 * @brief xSPI slave for command/address/data transfer and simple memory.
 * @param clk      System clock
 * @param rst_n    Active-low reset
 * @param cs_n     Chip select (active low)
 * @param sck      SPI clock
 * @param io_out   Output to IO bus
 * @param io_in    Input from IO bus
 * @param io_oe    Output enable for IO bus
 * @param ready    Ready flag (debug/status)
 */
module xspi_sopi_slave (
    input  wire        clk,      //!< System clock
    input  wire        rst_n,    //!< Active-low reset

    input  wire        cs_n,     //!< Chip select (active low)
    input  wire        sck,      //!< SPI clock
    output reg [7:0]   io_out,   //!< Output to IO bus
    input  wire [7:0]  io_in,    //!< Input from IO bus
    output reg         io_oe,    //!< Output enable for IO bus

    output reg         ready,     //!< Ready flag (debug/status)
    output wire        data_strobe,
    output reg         crc_ca_match,
    output reg         crc_data_match,
    output reg         crc_ca_error,
    output reg         crc_data_error,
    input wire         crc_ca_error_master,
    input wire         crc_data_error_master
);

    // === FSM States ===
    reg [3:0] state;         //!< Current FSM state
    localparam STATE_IDLE         = 4'd0; //!< Idle state
    localparam STATE_CMD          = 4'd1; //!< Receive command
    localparam STATE_ADDR         = 4'd2; //!< Receive address
    localparam STATE_RECV_CRC_CA  = 4'd3; //!< Receive CRC for command/address
    localparam STATE_WAIT_LATENCY = 4'd4; //!< Wait latency for read
    localparam STATE_WR_DATA      = 4'd5; //!< Receive write data
    localparam STATE_RECV_CRC_DATA= 4'd6; //!< Receive CRC for data
    localparam STATE_RD_DATA      = 4'd7; //!< Send read data
    localparam STATE_SEND_CRC_DATA= 4'd8; //!< Send CRC for data
    localparam STATE_DONE         = 4'd9; //!< Done state
    reg [3:0] byte_cnt;
    reg [2:0] latency_cnt;
    reg [3:0] retransmit_cnt;  // Retransmission counter for slave
    reg [7:0]  command_reg;
    reg [47:0] addr_reg;
    reg [63:0] data_reg;
    reg [63:0] mem;
    reg crc_ca_clear, crc_ca_enable;
    wire [7:0] crc_ca_out;
    reg [7:0] crc_ca_recv;
    reg crc_data_clear, crc_data_enable;
    wire [7:0] crc_data_out;
    reg [7:0] crc_data_recv;
    reg [7:0] data_for_crc;
  assign data_strobe = (state == STATE_RD_DATA || STATE_SEND_CRC_DATA) ? clk : 1'b0;
    crc8 crc_ca_inst (
        .clk(clk),
        .rst(!rst_n),
        .enable(crc_ca_enable),
        .clear(crc_ca_clear),
        .data_in(data_for_crc),
        .crc_out(crc_ca_out)
    );
    crc8_slave crc_data_inst (
        .clk(clk),
        .rst(!rst_n),
        .enable(crc_data_enable),
        .clear(crc_data_clear),
        .data_in(data_for_crc),
        .crc_out(crc_data_out)
    );
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            io_out      <= 8'h00;
            io_oe       <= 1'b0;
            byte_cnt    <= 4'd0;
            latency_cnt <= 3'd0;
            retransmit_cnt <= 4'd0;
            ready       <= 1'b0;
            command_reg <= 8'h00;
            addr_reg    <= 48'h0;
            data_reg    <= 64'h0;
            crc_ca_clear <= 1'b1;
            crc_ca_enable <= 1'b0;
            crc_data_clear <= 1'b1;
            crc_data_enable <= 1'b0;
            crc_ca_match <= 1'b0;
            crc_ca_error <= 1'b0;
            crc_data_match <= 1'b0;
            crc_data_error <= 1'b0;
        end else begin
            crc_ca_enable <= 1'b0;
            crc_data_enable <= 1'b0;
            case (state)
                STATE_IDLE: begin
                    ready <= 0;
                    byte_cnt <= 0;
                    io_oe <= 1'b0;
                    crc_ca_clear <= 1'b1;
                    crc_data_clear <= 1'b1;
                    crc_ca_match <= 1'b0;
                    crc_ca_error <= 1'b0;
                    crc_data_match <= 1'b0;
                    crc_data_error <= 1'b0;
                    // Only transition to CMD if CS_n is asserted
                    //if (!cs_n) begin
                        state <= STATE_CMD;
                   // end
                end
                STATE_CMD: begin
                    if (!cs_n) begin
                        command_reg <= io_in;
                        byte_cnt    <= 1;
                        state       <= STATE_ADDR;
                        crc_ca_clear <= 1'b0;
                        crc_ca_enable <= 1'b1;
                        data_for_crc <= io_in;
                    end //else begin
                       // state <= STATE_IDLE; // Return to idle if CS_n is high
                   // end
                end
                STATE_ADDR: begin
                    case (byte_cnt)
                        1: begin addr_reg[47:40] <= io_in; data_for_crc <= io_in; end
                        2: begin addr_reg[39:32] <= io_in; data_for_crc <= io_in; end
                        3: begin addr_reg[31:24] <= io_in; data_for_crc <= io_in; end
                        4: begin addr_reg[23:16] <= io_in; data_for_crc <= io_in; end
                        5: begin addr_reg[15:8]  <= io_in; data_for_crc <= io_in; end
                        6: begin addr_reg[7:0]   <= io_in; data_for_crc <= io_in; end
                    endcase
                  if (byte_cnt<=5)
                    crc_ca_enable <= 1'b1;
                  else crc_ca_enable <= 1'b0;
                    //crc_ca_enable <= 1'b1;
                    crc_ca_clear <= 1'b0;
                    byte_cnt <= byte_cnt + 1;
                    if (byte_cnt == 6) state <= STATE_RECV_CRC_CA;
                end
                STATE_RECV_CRC_CA: begin
                    crc_ca_recv <= io_in;
                    if (io_in == crc_ca_out) begin
                      if (retransmit_cnt < 3) begin
                        crc_ca_match <= 1'b0;
                        crc_ca_error <= 1'b1;
                      end
                      else begin
                        crc_ca_match <= 1'b1;
                        crc_ca_error <= 1'b0;
                      end
                    end else begin
                        crc_ca_match <= 1'b0;
                        crc_ca_error <= 1'b1;
                    end
                    if (command_reg == 8'hFF) begin
                        latency_cnt <= 0;
                        state <= STATE_WAIT_LATENCY;
                    end else if (command_reg == 8'hA5) begin
                        state <= STATE_WR_DATA;
                    end else begin
                        state <= STATE_DONE;
                    end
                end
                STATE_WAIT_LATENCY: begin
                  crc_ca_match<=0;
                    latency_cnt <= latency_cnt + 1;
                    if (latency_cnt == 3'd5) begin
                        data_reg <= mem;
                        byte_cnt <= 7;
                        io_oe    <= 1'b1;
                        state    <= STATE_RD_DATA;
                        crc_data_clear <= 1'b1;
                    end
                end
                STATE_WR_DATA: begin
                  crc_ca_match<=0;
                    case (byte_cnt)
                        7:  begin data_reg[63:56] <= io_in; data_for_crc <= io_in; end
                        8:  begin data_reg[55:48] <= io_in; data_for_crc <= io_in; end
                        9:  begin data_reg[47:40] <= io_in; data_for_crc <= io_in; end
                        10: begin data_reg[39:32] <= io_in; data_for_crc <= io_in; end
                        11: begin data_reg[31:24] <= io_in; data_for_crc <= io_in; end
                        12: begin data_reg[23:16] <= io_in; data_for_crc <= io_in; end
                        13: begin data_reg[15:8]  <= io_in; data_for_crc <= io_in; end
                        14: begin data_reg[7:0]   <= io_in; data_for_crc <= io_in; end
                    endcase
                   if (byte_cnt>=7 && byte_cnt<=13)
                    crc_data_enable <= 1'b1;
                  else crc_data_enable <= 1'b0;
                    crc_data_clear <= 0;
                    byte_cnt <= byte_cnt + 1;
                    if (byte_cnt == 14) state <= STATE_RECV_CRC_DATA;
                end
                STATE_RECV_CRC_DATA: begin
                    crc_data_clear<=0;
                    crc_data_recv <= io_in;
                    if (io_in == crc_data_out) begin
                        crc_data_match <= 1'b1;
                        crc_data_error <= 1'b0;
                    end else begin
                        crc_data_match <= 1'b0;
                        crc_data_error <= 1'b1;
                    end
                    mem <= data_reg;
                    state <= STATE_DONE;
                end
                STATE_RD_DATA: begin
                    case (byte_cnt)
                        7:  begin io_out <= data_reg[63:56]; data_for_crc <= data_reg[63:56]; end
                        8:  begin io_out <= data_reg[55:48]; data_for_crc <= data_reg[55:48]; end
                        9:  begin io_out <= data_reg[47:40]; data_for_crc <= data_reg[47:40]; end
                        10: begin io_out <= data_reg[39:32]; data_for_crc <= data_reg[39:32]; end
                        11: begin io_out <= data_reg[31:24]; data_for_crc <= data_reg[31:24]; end
                        12: begin io_out <= data_reg[23:16]; data_for_crc <= data_reg[23:16]; end
                        13: begin io_out <= data_reg[15:8];  data_for_crc <= data_reg[15:8];  end
                        14: begin io_out <= data_reg[7:0];   data_for_crc <= data_reg[7:0];   end
                    endcase
                  if (byte_cnt>=7 && byte_cnt<=13)
                    crc_data_enable <= 1'b1;
                  else crc_data_enable <= 1'b0;
                    crc_data_clear <= 0;
                    byte_cnt <= byte_cnt + 1;
                  if (byte_cnt == 14) state <= STATE_SEND_CRC_DATA;
                end
                STATE_SEND_CRC_DATA: begin
                    io_out <= crc_data_out;
                    io_oe <= 1'b1;
                    crc_data_enable <= 1'b0;
                    state <= STATE_DONE;
                end
                STATE_DONE: begin
                    crc_data_match <= 1'b0;
                    io_oe <= 1'b0;
                    
                    // Check for retransmission conditions
                    if ((crc_ca_error_master == 1'b1 || crc_data_error_master == 1'b1 || crc_ca_error == 1'b1 || crc_data_error == 1'b1) && retransmit_cnt < 4'd3) begin
                        // Reset for retransmission
                        byte_cnt <= 4'd0;
                        latency_cnt <= 3'd0;
                        retransmit_cnt <= retransmit_cnt + 1;
                        crc_ca_clear <= 1'b1;
                        crc_data_clear <= 1'b1;
                        crc_ca_match <= 1'b0;
                        crc_ca_error <= 1'b0;
                        crc_data_match <= 1'b0;
                        crc_data_error <= 1'b0;
                        state <= STATE_CMD;
                        ready <= 1'b0;
                    end else begin
                        state <= STATE_IDLE;
                        ready <= 1'b1;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule