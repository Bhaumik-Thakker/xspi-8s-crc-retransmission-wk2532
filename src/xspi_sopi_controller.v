/**
 * @module xspi_sopi_controller
 * @brief xSPI controller (master) for command/address/data transfer.
 * @param clk      System clock
 * @param rst_n    Active-low reset
 * @param cs_n     Chip select (active low)
 * @param sck      SPI clock
 * @param io_out   Output to IO bus
 * @param io_in    Input from IO bus
 * @param io_oe    Output enable for IO bus
 * @param start    Start transaction
 * @param command  8-bit command
 * @param address  48-bit address
 * @param wr_data  64-bit data to write
 * @param rd_data  64-bit data read
 * @param done     Transaction done flag
 */
module xspi_sopi_controller (
    input  wire        clk,      //!< System clock
    input  wire        rst_n,    //!< Active-low reset

    // SPI signals - separated input/output
    output reg         cs_n,     //!< Chip select (active low)
    output reg         sck,      //!< SPI clock
    output reg [7:0]   io_out,   //!< Output to IO bus
    input  wire [7:0]  io_in,    //!< Input from IO bus
    output reg         io_oe,    //!< Output enable for IO bus

    // Control signals
    input  wire        start,    //!< Start transaction
   // input  wire        rw,         // 0 = write, 1 = read
  input  wire [7:0]  command_in,  //!< 8-bit command
  input  wire [47:0] address_in,  //!< 48-bit address
  input  wire [63:0] wr_data_in,  //!< 64-bit data to write
    input wire         data_strobe,

    output reg [63:0]  rd_data,  //!< 64-bit data read
    output reg         done,     //!< Transaction done flag
    output reg         crc_ca_match,
    output reg         crc_data_match,
    output reg         crc_ca_error,
    output reg         crc_data_error,
    input wire         crc_ca_error_slave,
    input wire         crc_data_error_slave
);
    reg [2:0] wait_cycles;
    reg [7:0] command;
    reg [47:0] address;
    reg [63:0] wr_data;
    reg [3:0] retransmit_cnt;  // Retransmission counter
    // === FSM States ===
    reg [3:0] state;         //!< Current FSM state
    reg [3:0] next_state;    //!< Next FSM state
    localparam Latency         = 3'd6;
    localparam STATE_IDLE      = 4'd0; //!< Idle state
    localparam STATE_CMD       = 4'd1; //!< Send command
    localparam STATE_ADDR      = 4'd2; //!< Send address
    localparam STATE_SEND_CRC_CA = 4'd3; //!< Send CRC for command/address
    localparam STATE_WR_DATA   = 4'd4; //!< Write data
    localparam STATE_SEND_CRC_DATA = 4'd5; //!< Send CRC for data
    localparam STATE_RD_DATA   = 4'd6; //!< Read data
    localparam STATE_RECV_CRC_DATA = 4'd7; //!< Receive CRC for data
    localparam STATE_RECV_CRC_CA = 4'd8; //!< Receive CRC for command/address
    localparam STATE_FINISH    = 4'd9; //!< Finish/cleanup
    // === Counters and Buffers ===
    reg [3:0] byte_cnt;      //!< Byte counter for address/data
    reg [63:0] rdata_buf;    //!< Buffer for read data
    // CRC for command/address
    reg crc_ca_clear, crc_ca_enable;
    wire [7:0] crc_ca_out;
    reg [7:0] crc_ca_recv;
    // CRC for data
    reg crc_data_clear, crc_data_enable;
    wire [7:0] crc_data_out;
    reg [7:0] crc_data_recv;
    reg [7:0] data_for_crc;
    // CRC8 for command/address
    crc8 crc_ca_inst (
        .clk(clk),
        .rst(!rst_n),
        .enable(crc_ca_enable),
        .clear(crc_ca_clear),
        .data_in(data_for_crc),
        .crc_out(crc_ca_out)
    );
    // CRC8 for data
    crc8 crc_data_inst (
        .clk(clk),
        .rst(!rst_n),
        .enable(crc_data_enable),
        .clear(crc_data_clear),
        .data_in(data_for_crc),
        .crc_out(crc_data_out)
    );

    /**
     * @brief FSM sequential logic: state update
     */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end

    /**
     * @brief FSM combinational logic: next state logic
     */
    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE:
                if (start)
                    next_state = STATE_CMD;
            STATE_CMD:
                next_state = STATE_ADDR;
            STATE_ADDR:
                if (byte_cnt == 6)
                    next_state = STATE_SEND_CRC_CA;
            STATE_SEND_CRC_CA:
                next_state = (command == 8'hFF) ? STATE_RECV_CRC_CA : (command == 8'hA5) ? STATE_WR_DATA : STATE_FINISH;
            STATE_RECV_CRC_CA:
                next_state = (command == 8'hFF) ? STATE_RD_DATA : STATE_FINISH;
            STATE_WR_DATA:
                if (byte_cnt == 14)
                    next_state = STATE_SEND_CRC_DATA;
            STATE_SEND_CRC_DATA:
                next_state = STATE_FINISH;
            STATE_RD_DATA:
                if (byte_cnt == 15)
                    next_state = STATE_RECV_CRC_DATA;
            STATE_RECV_CRC_DATA:
                next_state = STATE_FINISH;
            STATE_FINISH:
                // Check for retransmission conditions
                if ((crc_ca_error_slave == 1'b1 || crc_data_error_slave == 1'b1 || crc_data_error == 1'b1) && retransmit_cnt < 4'd3) begin
                    next_state = STATE_CMD;  // Retransmit from command
                end else begin
                    next_state = STATE_IDLE;
                end
            default:
                next_state = STATE_IDLE;
        endcase
    end

    /**
     * @brief Main operation: drive SPI signals and manage data transfer
     */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_n     <= 1'b1;
            sck      <= 1'b0;
            io_out   <= 8'h00;
            io_oe    <= 1'b0;
            done     <= 1'b0;
            rd_data  <= 64'h0;
            rdata_buf <= 64'h0;
            byte_cnt <= 4'd0;
            wait_cycles <= 3'd0;
            crc_ca_clear <= 1'b1;
            crc_ca_enable <= 1'b0;
            crc_data_clear <= 1'b1;
            crc_data_enable <= 1'b0;
            crc_ca_match <= 1'b0;
            crc_ca_error <= 1'b0;
            crc_data_match <= 1'b0;
            crc_data_error <= 1'b0;
            retransmit_cnt <= 0;

        end else begin
            // Default disables
            crc_ca_enable <= 1'b0;
            crc_data_enable <= 1'b0;
            case (state)
                STATE_IDLE: begin
                    done     <= 1'b0;
                    cs_n     <= 1'b1;
                    sck      <= 1'b0;
                    io_oe    <= 1'b0;
                    byte_cnt <= 4'd0;
                    wait_cycles <= 0;
                    crc_ca_clear <= 1'b1;
                    crc_data_clear <= 1'b1;
                    crc_ca_match <= 1'b0;
                    crc_ca_error <= 1'b0;
                    crc_data_match <= 1'b0;
                    crc_data_error <= 1'b0;
                    command<=command_in;
                    address<=address_in;
                    wr_data<=wr_data_in;
                end
                STATE_CMD: begin
                    cs_n     <= 1'b0;
                    io_oe    <= 1'b1;
                    io_out   <= command;
                    byte_cnt <= 1;
                    // CRC for command
                    crc_ca_clear <= 1'b0;
                    crc_ca_enable <= 1'b1;
                    data_for_crc <= command;
                end
                STATE_ADDR: begin
                    io_oe    <= 1'b1;
                    case (byte_cnt)
                        1: begin io_out <= address[47:40]; data_for_crc <= address[47:40]; end
                        2: begin io_out <= address[39:32]; data_for_crc <= address[39:32]; end
                        3: begin io_out <= address[31:24]; data_for_crc <= address[31:24]; end
                        4: begin io_out <= address[23:16]; data_for_crc <= address[23:16]; end
                        5: begin io_out <= address[15:8];  data_for_crc <= address[15:8];  end
                        6: begin io_out <= address[7:0];   data_for_crc <= address[7:0];   end
                    endcase
                  if (byte_cnt<=5)
                    crc_ca_enable <= 1'b1;
                  else crc_ca_enable <= 1'b0;
                    crc_ca_clear <= 1'b0;
                    byte_cnt <= byte_cnt + 1;
                end
                STATE_SEND_CRC_CA: begin
                    io_oe <= 1'b1;
                    io_out <= crc_ca_out;
                    crc_ca_enable <= 1'b0;
                end
                STATE_RECV_CRC_CA: begin
                    io_oe <= 1'b0;
                    crc_ca_recv <= io_in;
                    if (io_in == crc_ca_out) begin
                        crc_ca_match <= 1'b1;
                        crc_ca_error <= 1'b0;
                    end else begin
                        crc_ca_match <= 1'b0;
                        crc_ca_error <= 1'b1;
                    end
                end
                STATE_WR_DATA: begin
                    io_oe    <= 1'b1;
                    case (byte_cnt)
                        7: begin io_out <= wr_data[63:56]; data_for_crc <= wr_data[63:56]; end
                        8: begin io_out <= wr_data[55:48]; data_for_crc <= wr_data[55:48]; end
                        9: begin io_out <= wr_data[47:40]; data_for_crc <= wr_data[47:40]; end
                        10: begin io_out <= wr_data[39:32]; data_for_crc <= wr_data[39:32]; end
                        11: begin io_out <= wr_data[31:24]; data_for_crc <= wr_data[31:24]; end
                        12: begin io_out <= wr_data[23:16]; data_for_crc <= wr_data[23:16]; end
                        13: begin io_out <= wr_data[15:8];  data_for_crc <= wr_data[15:8];  end
                        14: begin io_out <= wr_data[7:0];   data_for_crc <= wr_data[7:0];   end
                    endcase
                  if (byte_cnt<=13)
                    crc_data_enable <= 1'b1;
                  else crc_data_enable <= 1'b0;
                    //crc_data_enable <= 1'b1;
                    crc_data_clear <= 0;
                    byte_cnt <= byte_cnt + 1;
                end
                STATE_SEND_CRC_DATA: begin
                    crc_data_clear<=0;
                    io_oe <= 1'b1;
                    io_out <= crc_data_out;
                    crc_data_enable <= 1'b0;
                end
                STATE_RD_DATA: begin
                    crc_ca_match <= 1'b0;
                    io_oe <= 1'b0;
                   // if (data_strobe == 1'b1) begin
                        case (byte_cnt)
                            8: begin rdata_buf[63:56] <= io_in; data_for_crc <= io_in; end
                            9: begin rdata_buf[55:48] <= io_in; data_for_crc <= io_in; end
                            10: begin rdata_buf[47:40] <= io_in; data_for_crc <= io_in; end
                            11: begin rdata_buf[39:32] <= io_in; data_for_crc <= io_in; end
                            12: begin rdata_buf[31:24] <= io_in; data_for_crc <= io_in; end
                            13: begin rdata_buf[23:16] <= io_in; data_for_crc <= io_in; end
                            14: begin rdata_buf[15:8]  <= io_in; data_for_crc <= io_in; end
                            15: begin rdata_buf[7:0]   <= io_in; data_for_crc <= io_in; end
                        endcase
                  if (byte_cnt>=8 && byte_cnt<=14)
                        crc_data_enable <= 1'b1;
                  else crc_data_enable <= 1'b0;
                      crc_data_clear <= 0;
                    //end
                  if (Latency-1 > wait_cycles) begin
                        wait_cycles <= wait_cycles +1;
                    end else begin
                        byte_cnt <= byte_cnt + 1;
                    end
                end
                STATE_RECV_CRC_DATA: begin
                    io_oe <= 1'b0;
                    crc_data_recv <= io_in;
                    if (io_in == crc_data_out) begin
                        crc_data_match <= 1'b1;
                        crc_data_error <= 1'b0;
                    end else begin
                        crc_data_match <= 1'b0;
                        crc_data_error <= 1'b1;
                    end
                end
                STATE_FINISH: begin
                    if (crc_ca_error_slave == 1'b1 || crc_data_error_slave == 1'b1 || crc_data_error == 1'b1) begin
                        // Retransmission needed - reset counters and signals
                        cs_n    <= 1'b1;  // Deassert CS for retransmission
                        io_oe   <= 1'b0;
                        done    <= 1'b0;
                                    byte_cnt <= 4'd0;
                        wait_cycles <= 3'd0;
                        retransmit_cnt <= retransmit_cnt + 1;  // Increment retransmission counter
            crc_ca_clear <= 1'b1;
            crc_data_clear <= 1'b1;
            crc_ca_match <= 1'b0;
            crc_ca_error <= 1'b0;
            crc_data_match <= 1'b0;
            crc_data_error <= 1'b0;
                    end else begin
                        // Normal completion
                        crc_data_match <= 1'b0;
                        cs_n    <= 1'b1;
                        io_oe   <= 1'b0;
                        done    <= 1'b1;
                        rd_data <= rdata_buf;
                    end
                end
            endcase
        end
    end
endmodule
